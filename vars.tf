variable "infrastructure" {
  type = object({
    project_id        = string
    resource_prefix   = optional(string, "")
    resource_location = string
    # Presence of create_project signals that the module should create the project.
    # Omit (null) when supplying a pre-existing project.
    create_project = optional(object({
      org_id             = optional(string)
      folder_id          = optional(string)
      billing_account_id = string
      labels             = optional(map(string), {})
    }))
  })

  description = <<EOT
Project and resource infrastructure configuration:
  - project_id: ID of the GCP project to hold all resources.
  - resource_prefix: If set, prepended (with a dash) to all non-project resource identifiers. Max 14 characters.
  - resource_location: GCP region for Cloud Functions and associated resources (e.g. "us-central1").
    Must be a region, not a multi-region string — storage buckets here are transient deployment staging only.
  - create_project: If set, the module creates the project; omit when supplying a pre-existing project.
    - org_id: Where to create the project (exclusive of folder_id).
    - folder_id: Where to create the project (exclusive of org_id).
    - billing_account_id: Billing account responsible for any costs incurred.
    - labels: Labels to apply to the project.
EOT

  validation {
    condition     = length(var.infrastructure.resource_prefix) <= 14
    error_message = "resource_prefix can be no longer than 14 characters."
  }

  validation {
    condition = (
      var.infrastructure.create_project == null ||
      var.infrastructure.create_project.org_id != null ||
      var.infrastructure.create_project.folder_id != null
    )
    error_message = "One of org_id or folder_id is required when creating the project."
  }

  validation {
    condition = (
      var.infrastructure.create_project == null ||
      var.infrastructure.create_project.org_id == null ||
      var.infrastructure.create_project.folder_id == null
    )
    error_message = "org_id and folder_id are mutually exclusive."
  }
}

variable "integration_surface" {
  type = object({
    trust_aws = object({
      account_id           = string
      assetdb_role_name    = string
      execution_role_name  = string
      platform_role_name   = string
      cost_query_role_name = string
    })
    aws_relay = object({
      role_arn = string
      bus_arn  = string
    })
  })
  description = <<EOT
Stacklet-supplied integration configuration. Provided by Stacklet:
  - trust_aws: Workload identity federation trust configuration for Stacklet's AWS account.
    - account_id: The AWS account ID of the Stacklet deployment.
    - assetdb_role_name: Name of the AWS role used by the asset database.
    - execution_role_name: Name of the AWS role used by policy execution.
    - platform_role_name: Name of the AWS role used by the platform.
    - cost_query_role_name: Name of the AWS role used for cost source queries.
  - aws_relay: Configuration for forwarding GCP events to Stacklet's AWS event bus.
    - role_arn: ARN of the AWS role used to publish events.
    - bus_arn: ARN of the AWS EventBridge bus to receive events.
EOT
}

variable "organizations" {
  type = list(object({
    org_id      = string
    folder_ids  = optional(list(string), [])
    project_ids = optional(list(string), [])
  }))
  description = <<EOT
Organizations to onboard. For each one:
  - org_id: The organization ID.
  - folder_ids: Optional list of folder IDs; if set (with or without project_ids), only
    the specified folders and projects are onboarded rather than the whole org.
  - project_ids: Optional list of project IDs; see folder_ids.

An empty list is valid — the identity and relay infrastructure will still be deployed,
which is useful when setting up access ahead of time before organizations are added.
EOT
}

variable "cost_sources" {
  type = list(object({
    billing_table = string
  }))
  default     = []
  description = <<EOT
Cost sources to collect billing data from. For each one:
  - billing_table: The BigQuery billing export table, in '<project_id>.<dataset_id>.<table_id>' format.
EOT

  validation {
    condition     = alltrue([for s in var.cost_sources : length(split(".", s.billing_table)) == 3])
    error_message = "billing_table must be in the form '<project_id>.<dataset_id>.<table_id>'."
  }
}

variable "security_contexts" {
  type = list(object({
    name        = string
    extra_roles = list(string)
  }))
  default     = []
  description = <<EOT
Additional execution security contexts. For each one:
  - name: The security context name (used as the service account identifier).
  - extra_roles: GCP roles granted in addition to the baseline read-only roles
    (roles/browser, roles/cloudasset.viewer, roles/iam.securityReviewer, roles/viewer).
EOT

  validation {
    # max account id length is 30, leave room for prefix and dash
    condition     = alltrue([for ctx in var.security_contexts : length(ctx.name) <= 15])
    error_message = "name can be no longer than 15 characters."
  }

  validation {
    condition     = alltrue([for ctx in var.security_contexts : !startswith(ctx.name, "stk-")])
    error_message = "name cannot start with 'stk-' (reserved for built-in security contexts)."
  }
}

variable "roundtrip_digest" {
  type        = string
  description = "Token used by the Stacklet Platform to detect mismatch between customerConfig and accessConfig. Provided by Stacklet."
}

variable "relay" {
  type = object({
    max_instances = optional(number, 10)
    memory        = optional(string, "256Mi")
    max_age_s     = optional(number, 3600)
    debug         = optional(bool, false)
  })
  default     = {}
  description = <<EOT
Relay function configuration. Each instance handles 100 concurrent requests; 256Mi memory
provides ~50% headroom at full concurrency; 10 instances sustains >1000 events/sec with low latency.
  - max_instances: Maximum instances per relay. Increase for higher throughput; decrease to control
    cost. Set to 0 for unlimited. Default (10) sustains >1000 events/sec.
  - memory: Memory per instance. Default (256Mi) is calibrated for ~50% consumption at full
    concurrency. Increase only if you observe memory pressure.
  - max_age_s: Events older than this many seconds are silently dropped before forwarding. Default 3600.
  - debug: Enable verbose debug logging in relay Cloud Functions.
EOT
}
