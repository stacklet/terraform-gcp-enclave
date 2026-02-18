locals {
  project_resource_count = var.project.create ? 1 : 0
  project_data_count     = var.project.create ? 0 : 1

  resource_prefix = var.resource_prefix == "" ? "" : "${var.resource_prefix}-"

  project_id     = var.project.create ? google_project.integration[0].project_id : var.project.id
  project_number = var.project.create ? google_project.integration[0].number : data.google_project.integration[0].number
}

resource "google_project" "integration" {
  count = local.project_resource_count

  name            = "Stacklet integration"
  project_id      = var.project.id
  org_id          = var.project.org_id
  folder_id       = var.project.folder_id
  billing_account = var.project.billing_account_id
  labels          = var.project.labels

  deletion_policy = "DELETE"
}

data "google_project" "integration" {
  count = local.project_data_count

  project_id = var.project.id
}

resource "google_project_service" "service" {
  for_each = toset([
    "artifactregistry",
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

  project = google_project.integration[0].project_id
  service = "${each.key}.googleapis.com"
}

resource "time_sleep" "stacklet_access_creation_delay" {
  count = local.project_resource_count

  create_duration = "60s"

  depends_on = [google_project.integration[0]]
}

resource "google_iam_workload_identity_pool" "wif_access" {
  project                   = local.project_id
  workload_identity_pool_id = "${local.resource_prefix}wif-access"
  display_name              = "Stacklet WIF access"

  # Identity pool creation fails if executed too soon after project creation.
  depends_on = [time_sleep.stacklet_access_creation_delay]
}

resource "google_iam_workload_identity_pool_provider" "aws_access" {
  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.wif_access.workload_identity_pool_id
  workload_identity_pool_provider_id = "${local.resource_prefix}aws-access"
  display_name                       = "Stacklet AWS access"
  disabled                           = false

  aws {
    account_id = var.stacklet_aws.account_id
  }
}
