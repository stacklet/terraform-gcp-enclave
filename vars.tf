variable "resource_prefix" {
  type        = string
  default     = ""
  description = "If set, prepended to all non-project resource identifiers."

  validation {
    condition     = length(var.resource_prefix) <= 14
    error_message = "resource_prefix can be no longer than 14 characters."
  }
}

variable "location" {
  type        = string
  default     = "us-central1"
  description = "Location for region-specific resources."
}

variable "bucket_location" {
  type        = string
  default     = "US"
  description = "Location where to create storage buckets."
}


variable "project" {
  type = object({
    create             = optional(bool, true)
    id                 = string
    org_id             = optional(string)
    folder_id          = optional(string)
    billing_account_id = optional(string)
    labels             = optional(map(string), {})
  })
  description = <<EOT
Project configuration:
  - create: Whether to create the project.
  - id: ID of project to hold all resources.
  - org_id: Where to create the project (exclusive of folder_id).
  - folder_id: Where to create the project (exclusive of org_id).
  - billing_account_id: Billing account responsible for any costs incurred.
  - labels: Labels to apply to the project and applicable resources.
EOT

  validation {
    condition     = (var.project.billing_account_id == null) || var.project.create
    error_message = "billing_account_id is only meaningful when this module is responsible for the project."
  }

  validation {
    condition     = (var.project.org_id == null) || var.project.create
    error_message = "org_id is only meaningful when this module is responsible for the project."
  }

  validation {
    condition     = (var.project.folder_id == null) || var.project.create
    error_message = "folder_id is only meaningful when this module is responsible for the project."
  }

  validation {
    condition     = !var.project.create || (var.project.billing_account_id != null)
    error_message = "billing_account_id is required when creating the project."
  }

  validation {
    condition     = !var.project.create || (var.project.org_id != null || var.project.folder_id != null)
    error_message = "One of org_id or folder_id is required when creating the project."
  }

  validation {
    condition     = var.project.org_id == null || var.project.folder_id == null
    error_message = "project.org_id and project.folder_id are mutually exclusive."
  }
}

variable "extra_service_accounts" {
  type = list(object({
    name           = string
    assumable_from = list(string)
    roles          = list(string)
  }))
  default     = []
  description = <<EOT
Additional service accounts to create. For each one:
  - name: The service account name.
  - assumable_from: List of names (possibly with path prefix) for AWS roles that can assume the role via WIF.
  - roles: GCP roles to be provided to the service account.
EOT

  validation {
    # max account id length is 30, leave room for prefix and dash
    condition     = alltrue([for sa in var.extra_service_accounts : length(sa.name) <= 15])
    error_message = "name can be no longer than 15 characters."
  }
}

variable "access_scope" {
  type = object({
    org_ids           = optional(list(string), [])
    folder_ids        = optional(list(string), [])
    project_ids       = optional(list(string), [])
    denied_folder_ids = optional(list(string), [])
  })
  default = {
    org_ids           = []
    folder_ids        = []
    project_ids       = []
    denied_folder_ids = []
  }
  description = <<EOT
Scope where service account permissions should be granted:
  - org_ids: List of organization IDs.
  - folder_ids: List of folder IDs.
  - project_ids: List of project IDs.
  - denied_folder_ids: List of folder IDs to explicitly deny access to.
EOT
}

variable "cost_export_billing_tables" {
  type        = list(string)
  default     = []
  description = "Billing cost export tables in '<project_id>.<dataset_id>.<table_id>' format."

  validation {
    condition     = alltrue([for t in var.cost_export_billing_tables : length(split(".", t)) == 3])
    error_message = "All tables must be in the form '<project_id>.<dataset_id>.<table_id>'."
  }
}

variable "events_relay" {
  type = object({
    aws_role_arn = string
    aws_bus_arn  = string
    asset_types = optional(list(string), [
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
    ])
    audit_log_include_children = optional(bool, false)
    security_findings_filter   = optional(string, "state = \"ACTIVE\"")
    function = optional(object({
      debug           = optional(bool, false)
      max_concurrency = optional(number, 80)
      cpu             = optional(string, "1")
      memory          = optional(string, "512M")
      }),
      {
        debug           = false
        max_concurrency = 80
        cpu             = "1"
        memory          = "512M"
      }
    )
  })
  description = <<EOT
Configuration for GCP events relay to Stacklet.
  - aws_role_arn: The ARN for the AWS role used for forwarding events to the bus.
  - aws_bus_arn: The ARN of the event bus in AWS where events get forwarded.
  - asset_types: The asset types that the cloud asset inventory feed provides.
  - audit_log_include_children: Whether audit log sinks include logs from child resources (folders/projects).
  - security_findings_filter: Filter to apply as streaming config for the security command center findings. By default all active findings are forwarded.
  - function: Relay function options:
    - debug: Whether to enable debug log.
    - max_concurrency: Maximum concurrency for the Cloud function. Higher values increase throughput but require more CPU.
                       Must be paired with adequate CPU allocation (cpu >= 1 required for concurrency > 1).
    - cpu: CPU allocation for Cloud Function instances. Valid values: '0.08' to '8'
           (in increments of 0.001 below 1, or 1/2/4/6/8 for >= 1).
           Default '1' supports high concurrency. Note: GCP requires cpu >= 1 when max_concurrency > 1.
    - memory: Memory allocation for Cloud Function instances. Valid values: '128M' to '32G'
              in increments (e.g., '256M', '512M', '1G', '2G'). Default '512M'. Make sure
              to configure memory values appropriately based on CPU count per GCP docs.
EOT
}

variable "stacklet_aws" {
  type = object({
    account_id       = string
    collector_role   = string
    execution_role   = string
    platform_role    = string
    cost_export_role = string
  })
  description = <<EOT
Details of the Stacklet deployment to integrate with in AWS (Provided by Stacklet).
  - account_id: The AWS account for the deployment.
  - collector_role: Name of the role used by account discovery.
  - execution_role: Name of the role used by Execution.
  - platform_role: Name of the role used by Platform.
  - cost_export_role: Name of the role used for billing cost export.
EOT
}

variable "roundtrip_digest" {
  type        = string
  default     = null
  description = "Token used by the Stacklet Platform to detect mismatch between customerConfig and accessConfig."
}
