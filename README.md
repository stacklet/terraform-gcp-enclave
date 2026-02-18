# Terraform module to integrate a Stacklet deployment with GCP

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.18 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.12 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 7.18 |
| <a name="provider_time"></a> [time](#provider\_time) | ~> 0.12 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_scope"></a> [access\_scope](#input\_access\_scope) | Scope where service account permissions should be granted:<br/>  - org\_ids: list of organization IDs.<br/>  - folder\_ids: list of folder IDs.<br/>  - project\_ids: list of project IDs.<br/>  - denied\_folder\_ids: list of folder IDs to explicitly deny access to. | <pre>object({<br/>    org_ids           = optional(list(string), [])<br/>    folder_ids        = optional(list(string), [])<br/>    project_ids       = optional(list(string), [])<br/>    denied_folder_ids = optional(list(string), [])<br/>  })</pre> | <pre>{<br/>  "denied_folder_ids": [],<br/>  "folder_ids": [],<br/>  "org_ids": [],<br/>  "project_ids": []<br/>}</pre> | no |
| <a name="input_cost_export_billing_tables"></a> [cost\_export\_billing\_tables](#input\_cost\_export\_billing\_tables) | Billing cost export tables in '<project\_id>.<dataset\_id>.<table\_id>' format. | `list(string)` | `[]` | no |
| <a name="input_extra_service_accounts"></a> [extra\_service\_accounts](#input\_extra\_service\_accounts) | Additional service accounts to create. For each one:<br/>  - name: the service account name.<br/>  - assumable\_from: list of names (possibly with path prefix) for AWS roles that can assumed the role via WIF.<br/>  - roles: GCP roles to be provided to the service account. | <pre>list(object({<br/>    name           = string<br/>    assumable_from = list(string)<br/>    roles          = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_project"></a> [project](#input\_project) | Project configuration:<br/>  - create: Whehter to create the project.<br/>  - id: ID of project to hold all resources.<br/>  - org\_id: Where to create the project (exclusive of folder\_id).<br/>  - folder\_id: Where to create the project (exclusive of org\_id).<br/>  - billing\_account\_id: billing account responsible for any costs incurred.<br/>  - labels: labels to apply to the project and applicable resources. | <pre>object({<br/>    create             = optional(bool, true)<br/>    id                 = string<br/>    org_id             = optional(string)<br/>    folder_id          = optional(string)<br/>    billing_account_id = optional(string)<br/>    labels             = optional(map(string), {})<br/>  })</pre> | n/a | yes |
| <a name="input_resource_prefix"></a> [resource\_prefix](#input\_resource\_prefix) | If set, prepended to all non-project resource identifiers. | `string` | `""` | no |
| <a name="input_roundtrip_digest"></a> [roundtrip\_digest](#input\_roundtrip\_digest) | Token used by the Stacklet Platform to detect mismatch between customerConfig and accessConfig. | `string` | `null` | no |
| <a name="input_stacklet_aws"></a> [stacklet\_aws](#input\_stacklet\_aws) | "Details of the Stacklet deployment to integrate with in AWS (Provided by Stacklet)."<br/>  - account\_id: The AWS account for the deployment.<br/>  - collector\_role: Name of the role used by account discovery.<br/>  - execution\_role: Name of the role used by Execution.<br/>  - platform\_role: Name of the role used by Platform.<br/>  - cost\_import\_role: Name of the role used for billing cost import. | <pre>object({<br/>    account_id       = string<br/>    collector_role   = string<br/>    execution_role   = string<br/>    platform_role    = string<br/>    cost_export_role = string<br/>  })</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_blob"></a> [access\_blob](#output\_access\_blob) | All other outputs crammed into a single copy/pasteable value. |
| <a name="output_cost_export_table_locations"></a> [cost\_export\_table\_locations](#output\_cost\_export\_table\_locations) | The data location for each cost export table made accessible. |
| <a name="output_old_access_blob"></a> [old\_access\_blob](#output\_old\_access\_blob) | n/a |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The project the created resources exist in. |
| <a name="output_service_accounts_access"></a> [service\_accounts\_access](#output\_service\_accounts\_access) | Access details for each service account. |
| <a name="output_wif_audience"></a> [wif\_audience](#output\_wif\_audience) | The audience value required for impersonation interactions. |
<!-- END_TF_DOCS -->
