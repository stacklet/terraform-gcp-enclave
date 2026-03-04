# Terraform module to integrate a Stacklet deployment with GCP

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | ~> 2.7 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.18 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.12 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | ~> 2.7 |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 7.18 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |
| <a name="provider_time"></a> [time](#provider\_time) | ~> 0.12 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_advanced"></a> [advanced](#input\_advanced) | Advanced configuration not exposed in the Platform UI. For operator/debug use. | <pre>object({<br/>    # Enable debug logging in relay Cloud Functions.<br/>    debug = optional(bool, false)<br/>    # Memory for relay Cloud Function instances. Valid values: "128M" to "32G".<br/>    # The relay is I/O-bound and events are small; 128M is sufficient in practice.<br/>    memory = optional(string, "128M")<br/>    # Events older than this many seconds are silently dropped before forwarding.<br/>    max_age_s = optional(number, 3600)<br/>  })</pre> | `{}` | no |
| <a name="input_cost_sources"></a> [cost\_sources](#input\_cost\_sources) | Cost sources to collect billing data from. For each one:<br/>  - billing\_table: The BigQuery billing export table, in '<project\_id>.<dataset\_id>.<table\_id>' format. | <pre>list(object({<br/>    billing_table = string<br/>  }))</pre> | `[]` | no |
| <a name="input_infrastructure"></a> [infrastructure](#input\_infrastructure) | Project and resource infrastructure configuration:<br/>  - project\_id: ID of the GCP project to hold all resources.<br/>  - resource\_prefix: If set, prepended (with a dash) to all non-project resource identifiers. Max 14 characters.<br/>  - resource\_location: GCP region for Cloud Functions and associated resources (e.g. "us-central1").<br/>    Must be a region, not a multi-region string — storage buckets here are transient deployment staging only.<br/>  - create\_project: If set, the module creates the project; omit when supplying a pre-existing project.<br/>    - org\_id: Where to create the project (exclusive of folder\_id).<br/>    - folder\_id: Where to create the project (exclusive of org\_id).<br/>    - billing\_account\_id: Billing account responsible for any costs incurred.<br/>    - labels: Labels to apply to the project. | <pre>object({<br/>    project_id        = string<br/>    resource_prefix   = optional(string, "")<br/>    resource_location = string<br/>    # Presence of create_project signals that the module should create the project.<br/>    # Omit (null) when supplying a pre-existing project.<br/>    create_project = optional(object({<br/>      org_id             = optional(string)<br/>      folder_id          = optional(string)<br/>      billing_account_id = string<br/>      labels             = optional(map(string), {})<br/>    }))<br/>  })</pre> | n/a | yes |
| <a name="input_integration_surface"></a> [integration\_surface](#input\_integration\_surface) | Stacklet-supplied integration configuration. Provided by Stacklet:<br/>  - trust\_aws: Workload identity federation trust configuration for Stacklet's AWS account.<br/>    - account\_id: The AWS account ID of the Stacklet deployment.<br/>    - assetdb\_role\_name: Name of the AWS role used by the asset database.<br/>    - execution\_role\_name: Name of the AWS role used by policy execution.<br/>    - platform\_role\_name: Name of the AWS role used by the platform.<br/>    - cost\_query\_role\_name: Name of the AWS role used for cost source queries.<br/>  - aws\_relay: Configuration for forwarding GCP events to Stacklet's AWS event bus.<br/>    - role\_arn: ARN of the AWS role used to publish events.<br/>    - bus\_arn: ARN of the AWS EventBridge bus to receive events. | <pre>object({<br/>    trust_aws = object({<br/>      account_id           = string<br/>      assetdb_role_name    = string<br/>      execution_role_name  = string<br/>      platform_role_name   = string<br/>      cost_query_role_name = string<br/>    })<br/>    aws_relay = object({<br/>      role_arn = string<br/>      bus_arn  = string<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_organizations"></a> [organizations](#input\_organizations) | Organizations to onboard. For each one:<br/>  - org\_id: The organization ID.<br/>  - folder\_ids: Optional list of folder IDs; if set (with or without project\_ids), only<br/>    the specified folders and projects are onboarded rather than the whole org.<br/>  - project\_ids: Optional list of project IDs; see folder\_ids.<br/><br/>An empty list is valid — the identity and relay infrastructure will still be deployed,<br/>which is useful when setting up access ahead of time before organizations are added. | <pre>list(object({<br/>    org_id      = string<br/>    folder_ids  = optional(list(string), [])<br/>    project_ids = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_roundtrip_digest"></a> [roundtrip\_digest](#input\_roundtrip\_digest) | Token used by the Stacklet Platform to detect mismatch between customerConfig and accessConfig. Provided by Stacklet. | `string` | n/a | yes |
| <a name="input_security_contexts"></a> [security\_contexts](#input\_security\_contexts) | Additional execution security contexts. For each one:<br/>  - name: The security context name (used as the service account identifier).<br/>  - extra\_roles: GCP roles granted in addition to the baseline read-only roles<br/>    (roles/browser, roles/cloudasset.viewer, roles/iam.securityReviewer, roles/viewer). | <pre>list(object({<br/>    name        = string<br/>    extra_roles = list(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_blob"></a> [access\_blob](#output\_access\_blob) | All other outputs crammed into a single copy/pasteable value. |
| <a name="output_cost_source_locations"></a> [cost\_source\_locations](#output\_cost\_source\_locations) | The location of each cost source table. |
| <a name="output_legacy_cost_access_blob"></a> [legacy\_cost\_access\_blob](#output\_legacy\_cost\_access\_blob) | n/a |
| <a name="output_organizations"></a> [organizations](#output\_organizations) | The organizations configured in this deployment. |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The project the created resources exist in. |
| <a name="output_relay_service_account_oauth_id"></a> [relay\_service\_account\_oauth\_id](#output\_relay\_service\_account\_oauth\_id) | OAuth ID for the service account used to relay events to AWS. |
| <a name="output_service_accounts_access"></a> [service\_accounts\_access](#output\_service\_accounts\_access) | Access details for each service account. |
| <a name="output_wif_audience"></a> [wif\_audience](#output\_wif\_audience) | The audience value required for impersonation interactions. |
<!-- END_TF_DOCS -->
