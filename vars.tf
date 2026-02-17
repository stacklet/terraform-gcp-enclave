variable "resource_prefix" {
  type        = string
  default     = ""
  description = "If set, prepended to all non-project resource identifiers."

  validation {
    condition     = length(var.resource_prefix) <= 14
    error_message = "resource_prefix can be no longer than 14 characters."
  }
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
  - create: Whehter to create the project.
  - id: ID of project to hold all resources.
  - org_id: Where to create the project (exclusive of folder_id).
  - folder_id: Where to create the project (exclusive of org_id).
  - billing_account_id: billing account responsible for any costs incurred.
  - labels: labels to apply to the project and applicable resources.
EOT

  validation {
    condition     = (var.project.org_id == null) || var.project.create
    error_message = "org_id is only meaningful when this module is responsible for the project."
  }

  validation {
    condition     = (var.project.folder_id == null) || var.project.create
    error_message = "folder_id is only meaningful when this module is responsible for the project."
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
  - name: the service account name.
  - assumable_from: list of names (possibly with path prefix) for AWS roles that can assumed the role via WIF.
  - roles: GCP roles to be provided to the service account.
EOT

  validation {
    # max account id lenght is 30, leave room for prefix and dash
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
  - org_ids: list of organization IDs.
  - folder_ids: list of folder IDs.
  - project_ids: list of project IDs.
  - denied_folder_ids: list of folder IDs to explicitly deny access to.
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

variable "stacklet_aws" {
  type = object({
    account_id       = string
    collector_role   = string
    execution_role   = string
    platform_role    = string
    cost_export_role = string
  })
  description = <<EOT
"Details of the Stacklet deployment to integrate with in AWS (Provided by Stacklet)."
  - account_id: The AWS account for the deployment.
  - collector_role: Name of the role used by account discovery.
  - execution_role: Name of the role used by Execution.
  - platform_role: Name of the role used by Platform.
  - cost_import_role: Name of the role used for billing cost import.
EOT
}

variable "roundtrip_digest" {
  type        = string
  default     = null
  description = "Token used by the Stacklet Platform to detect mismatch between customerConfig and accessConfig."
}
