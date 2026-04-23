locals {
  project_resource_count = var.infrastructure.create_project != null ? 1 : 0
  project_data_count     = var.infrastructure.create_project != null ? 0 : 1

  prefix = var.infrastructure.resource_prefix == "" ? "" : "${var.infrastructure.resource_prefix}-"

  project_id = var.infrastructure.create_project != null ? google_project.integration[0].project_id : var.infrastructure.project_id
  project_number = (
    var.infrastructure.create_project != null
    ? google_project.integration[0].number
    : data.google_project.integration[0].number
  )

  whole_org_ids = toset(compact([
    for e in var.organizations :
    (length(e.folder_ids) + length(e.project_ids)) == 0 ? e.org_id : null
  ]))
  org_ids     = toset([for org in var.organizations : org.org_id])
  folder_ids  = toset(flatten([for e in var.organizations : e.folder_ids]))
  project_ids = toset(flatten([for e in var.organizations : e.project_ids]))

  read_only_roles = [
    "roles/browser",
    "roles/cloudasset.viewer",
    "roles/iam.securityReviewer",
    "roles/viewer",
  ]

  asset_types = [
    "apikeys.googleapis.com/Key",
    "appengine.googleapis.com/Application",
    "bigquery.googleapis.com/Dataset",
    "bigtableadmin.googleapis.com/Instance",
    "cloudbilling.googleapis.com/BillingAccount",
    "cloudfunctions.googleapis.com/CloudFunction",
    "cloudkms.googleapis.com/KeyRing",
    "cloudresourcemanager.googleapis.com/Folder",
    "cloudresourcemanager.googleapis.com/Organization",
    "cloudresourcemanager.googleapis.com/Project",
    "compute.googleapis.com/Address",
    "compute.googleapis.com/Autoscaler",
    "compute.googleapis.com/BackendBucket",
    "compute.googleapis.com/BackendService",
    "compute.googleapis.com/Disk",
    "compute.googleapis.com/Firewall",
    "compute.googleapis.com/ForwardingRule",
    "compute.googleapis.com/GlobalAddress",
    "compute.googleapis.com/GlobalForwardingRule",
    "compute.googleapis.com/HealthCheck",
    "compute.googleapis.com/HttpHealthCheck",
    "compute.googleapis.com/HttpsHealthCheck",
    "compute.googleapis.com/Image",
    "compute.googleapis.com/Instance",
    "compute.googleapis.com/InstanceTemplate",
    "compute.googleapis.com/Interconnect",
    "compute.googleapis.com/InterconnectAttachment",
    "compute.googleapis.com/Network",
    "compute.googleapis.com/Project",
    "compute.googleapis.com/Route",
    "compute.googleapis.com/Router",
    "compute.googleapis.com/SecurityPolicy",
    "compute.googleapis.com/Snapshot",
    "compute.googleapis.com/SslCertificate",
    "compute.googleapis.com/SslPolicy",
    "compute.googleapis.com/Subnetwork",
    "compute.googleapis.com/TargetHttpProxy",
    "compute.googleapis.com/TargetHttpsProxy",
    "compute.googleapis.com/TargetInstance",
    "compute.googleapis.com/TargetPool",
    "compute.googleapis.com/TargetSslProxy",
    "compute.googleapis.com/TargetTcpProxy",
    "compute.googleapis.com/UrlMap",
    "container.googleapis.com/Cluster",
    "dataflow.googleapis.com/Job",
    "datafusion.googleapis.com/Instance",
    "dns.googleapis.com/ManagedZone",
    "dns.googleapis.com/Policy",
    "iam.googleapis.com/Role",
    "iam.googleapis.com/ServiceAccount",
    "logging.googleapis.com/LogMetric",
    "logging.googleapis.com/LogSink",
    "osconfig.googleapis.com/PatchDeployment",
    "pubsub.googleapis.com/Snapshot",
    "pubsub.googleapis.com/Subscription",
    "pubsub.googleapis.com/Topic",
    "redis.googleapis.com/Instance",
    "run.googleapis.com/Job",
    "run.googleapis.com/Revision",
    "run.googleapis.com/Service",
    "secretmanager.googleapis.com/Secret",
    "serviceusage.googleapis.com/Service",
    "spanner.googleapis.com/Instance",
    "sqladmin.googleapis.com/Instance",
    "storage.googleapis.com/Bucket",
  ]
}

resource "google_project" "integration" {
  count = local.project_resource_count

  name            = "Stacklet integration"
  project_id      = var.infrastructure.project_id
  org_id          = var.infrastructure.create_project.org_id
  folder_id       = var.infrastructure.create_project.folder_id
  billing_account = var.infrastructure.create_project.billing_account_id
  labels          = var.infrastructure.create_project.labels

  deletion_policy = "DELETE"
}

data "google_project" "integration" {
  count = local.project_data_count

  project_id = var.infrastructure.project_id
}

resource "google_project_service" "service" {
  for_each = toset([
    "artifactregistry",
    "bigquery",
    "cloudasset",
    "cloudbuild",
    "cloudfunctions",
    "cloudresourcemanager",
    "compute",
    "eventarc",
    "iam",
    "iamcredentials",
    "logging",
    "pubsub",
    "run",
    "securitycenter",
  ])

  project = local.project_id
  service = "${each.key}.googleapis.com"
}

resource "time_sleep" "stacklet_access_creation_delay" {
  count = local.project_resource_count

  create_duration = "60s"

  depends_on = [google_project.integration[0]]
}

resource "google_iam_workload_identity_pool" "wif_access" {
  project                   = local.project_id
  workload_identity_pool_id = "${local.prefix}wif-access"
  display_name              = "Stacklet WIF access"

  # Identity pool creation fails if executed too soon after project creation.
  depends_on = [
    time_sleep.stacklet_access_creation_delay,
    google_project_service.service["iam"],
  ]
}

resource "google_iam_workload_identity_pool_provider" "aws_access" {
  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.wif_access.workload_identity_pool_id
  workload_identity_pool_provider_id = "${local.prefix}aws-access"
  display_name                       = "Stacklet AWS access"
  disabled                           = false

  aws {
    account_id = var.integration_surface.trust_aws.account_id
  }
}
