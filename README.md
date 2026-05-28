# Terraform module to integrate a Stacklet deployment with GCP

This repository provide a module to deploy a GCP integration setup for
Stacklet.

Please refer to the official documentation for how to configure it.

**Note** that in order to provide back selected organization names to the
Stacklet deployment, the module needs the `gcloud` CLI. This is not required,
in which case a fallback name will be returned.

## Required Permissions for the Terraform Runner

The user or automation running the terraform configuration needs the APIs
and roles listed below. They span billing-account and resource-hierarchy
(organization, folder, or project) scopes.

These permissions are needed **only at deployment time** — while the Terraform
configuration is being applied to set up or update the integration. They are
distinct from the runtime permissions Stacklet uses to operate against the
GCP environment; those are managed by the module itself via the
`security_contexts` input and a baseline set of read-only roles
(`roles/browser`, `roles/cloudasset.viewer`, `roles/iam.securityReviewer`,
`roles/viewer`).


### APIs to enable in the runner's project

The runner makes API calls into its own project to read billing and asset
metadata. Enable the following services on whichever project the runner is
authenticated to:

- `cloudbilling.googleapis.com`
- `cloudasset.googleapis.com`

### Billing-account permissions

Only required when the module is creating the relay project (i.e. when
`infrastructure.create_project` is set). Granted on whichever billing account
will pay for the relay project's resources.

| Role                 | Purpose                                           |
|----------------------|---------------------------------------------------|
| `roles/billing.user` | Attach the billing account to the relay project. |

### Required IAM roles

Granted on the scope (organization, folder, or project) that contains the
resources the module manages. GCP IAM inheritance means a higher-scope grant
(e.g. at the organization root) covers all resources beneath it, which is
the simplest setup; narrower grants also work when onboarding is limited to
specific folders or projects.

| Role                                      | Purpose                                              |
|-------------------------------------------|------------------------------------------------------|
| `roles/resourcemanager.projectCreator` †  | Create the relay project.                            |
| `roles/resourcemanager.organizationAdmin` | Set IAM bindings on resources the module manages.    |
| `roles/cloudasset.owner`                  | Create Cloud Asset feeds.                            |
| `roles/logging.admin`                     | Create logging sinks.                                |
| `roles/securitycenter.admin`              | Create Security Command Center notification configs. |

† Only required when the module is creating the relay project (i.e. when
`infrastructure.create_project` is set). Grant this role at the project's
parent — the organization (`create_project.org_id`) or folder
(`create_project.folder_id`) where the project will be created. It cannot
be granted at project scope.

**When using a pre-existing relay project** (`infrastructure.create_project` is
not set), omit `roles/resourcemanager.projectCreator` and
`roles/billing.user`. Instead:

1. Enable the following APIs on the relay project before running Terraform:
   - `cloudasset.googleapis.com`
   - `cloudbilling.googleapis.com`
   - `cloudresourcemanager.googleapis.com`
   - `serviceusage.googleapis.com`
2. Grant `roles/owner` to the runner service account on the relay project.
3. Grant the org/folder-level roles (`roles/resourcemanager.organizationAdmin`,
   `roles/cloudasset.owner`, `roles/logging.admin`, `roles/securitycenter.admin`)
   as described above, and the cost export permissions below if applicable.

### Cost export — additional permissions when billing export lives outside the relay project

If the BigQuery dataset that holds the GCP billing export is in a different
project than the relay project this module creates, the runner needs owner
access on the export so the module can grant Stacklet read access to it.

| Role                       | Granted where                                                                                         |
|----------------------------|-------------------------------------------------------------------------------------------------------|
| `roles/bigquery.dataOwner` | The billing-export project specifically, or at the org level to cover all current and future exports. |

If the billing export is co-located with the relay project and the runner
created the relay project (making it project owner), the additional
`roles/bigquery.dataOwner` grant is not required — project ownership already
includes those permissions.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | ~> 2.7 |
| <a name="requirement_external"></a> [external](#requirement\_external) | ~> 2.3 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.18 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.12 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | ~> 2.7 |
| <a name="provider_external"></a> [external](#provider\_external) | ~> 2.3 |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 7.18 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |
| <a name="provider_time"></a> [time](#provider\_time) | ~> 0.12 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cost_sources"></a> [cost\_sources](#input\_cost\_sources) | Cost sources to collect billing data from. For each one:<br/>  - billing\_table: The BigQuery billing export table, in '<project\_id>.<dataset\_id>.<table\_id>' format. | <pre>list(object({<br/>    billing_table = string<br/>  }))</pre> | `[]` | no |
| <a name="input_infrastructure"></a> [infrastructure](#input\_infrastructure) | Project and resource infrastructure configuration:<br/>  - project\_id: ID of the GCP project to hold all resources.<br/>  - resource\_prefix: If set, prepended (with a dash) to all non-project resource identifiers. Max 14 characters.<br/>  - resource\_location: GCP region for Cloud Functions and associated resources (e.g. "us-central1").<br/>    Must be a region, not a multi-region string — storage buckets here are transient deployment staging only.<br/>  - create\_project: If set, the module creates the project; omit when supplying a pre-existing project.<br/>    - org\_id: Where to create the project (exclusive of folder\_id).<br/>    - folder\_id: Where to create the project (exclusive of org\_id).<br/>    - billing\_account\_id: Billing account responsible for any costs incurred.<br/>    - labels: Labels to apply to the project. | <pre>object({<br/>    project_id        = string<br/>    resource_prefix   = optional(string, "")<br/>    resource_location = string<br/>    # Presence of create_project signals that the module should create the project.<br/>    # Omit (null) when supplying a pre-existing project.<br/>    create_project = optional(object({<br/>      org_id             = optional(string)<br/>      folder_id          = optional(string)<br/>      billing_account_id = string<br/>      labels             = optional(map(string), {})<br/>    }))<br/>  })</pre> | n/a | yes |
| <a name="input_integration_surface"></a> [integration\_surface](#input\_integration\_surface) | Stacklet-supplied integration configuration. Provided by Stacklet:<br/>  - trust\_aws: Workload identity federation trust configuration for Stacklet's AWS account.<br/>    - account\_id: The AWS account ID of the Stacklet deployment.<br/>    - assetdb\_role\_name: Name of the AWS role used by the asset database.<br/>    - execution\_role\_name: Name of the AWS role used by policy execution.<br/>    - platform\_role\_name: Name of the AWS role used by the platform.<br/>    - cost\_query\_role\_name: Name of the AWS role used for cost source queries.<br/>  - aws\_relay: Configuration for forwarding GCP events to Stacklet's AWS event bus.<br/>    - role\_arn: ARN of the AWS role used to publish events.<br/>    - bus\_arn: ARN of the AWS EventBridge bus to receive events. | <pre>object({<br/>    trust_aws = object({<br/>      account_id           = string<br/>      assetdb_role_name    = string<br/>      execution_role_name  = string<br/>      platform_role_name   = string<br/>      cost_query_role_name = string<br/>    })<br/>    aws_relay = object({<br/>      role_arn = string<br/>      bus_arn  = string<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_organizations"></a> [organizations](#input\_organizations) | Organizations to onboard. For each one:<br/>  - org\_id: The organization ID.<br/>  - folder\_ids: Optional list of folder IDs; if set (with or without project\_ids), only<br/>    the specified folders and projects are onboarded rather than the whole org.<br/>  - project\_ids: Optional list of project IDs; see folder\_ids.<br/><br/>An empty list is valid — the identity and relay infrastructure will still be deployed,<br/>which is useful when setting up access ahead of time before organizations are added. | <pre>list(object({<br/>    org_id      = string<br/>    folder_ids  = optional(list(string), [])<br/>    project_ids = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_relay"></a> [relay](#input\_relay) | Relay function configuration. Each instance handles 100 concurrent requests; 256Mi memory<br/>provides ~50% headroom at full concurrency; 10 instances sustains >1000 events/sec with low latency.<br/>  - max\_instances: Maximum instances per relay. Increase for higher throughput; decrease to control<br/>    cost. Set to 0 for unlimited. Default (10) sustains >1000 events/sec.<br/>  - memory: Memory per instance. Default (256Mi) is calibrated for ~50% consumption at full<br/>    concurrency. Increase only if you observe memory pressure.<br/>  - max\_age\_s: Events older than this many seconds are silently dropped before forwarding. Default 3600.<br/>  - debug: Enable verbose debug logging in relay Cloud Functions. | <pre>object({<br/>    max_instances = optional(number, 10)<br/>    memory        = optional(string, "256Mi")<br/>    max_age_s     = optional(number, 3600)<br/>    debug         = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_roundtrip_digest"></a> [roundtrip\_digest](#input\_roundtrip\_digest) | Token used by the Stacklet Platform to detect mismatch between customerConfig and accessConfig. Provided by Stacklet. | `string` | n/a | yes |
| <a name="input_security_contexts"></a> [security\_contexts](#input\_security\_contexts) | Additional execution security contexts. For each one:<br/>  - name: The security context name (used as the service account identifier).<br/>  - extra\_roles: GCP roles granted in addition to the baseline read-only roles<br/>    (roles/browser, roles/cloudasset.viewer, roles/iam.securityReviewer, roles/viewer). | <pre>list(object({<br/>    name        = string<br/>    extra_roles = list(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_blob"></a> [access\_blob](#output\_access\_blob) | All other outputs crammed into a single copy/pasteable value. |
| <a name="output_cost_sources"></a> [cost\_sources](#output\_cost\_sources) | The location of each cost source table. |
| <a name="output_infrastructure"></a> [infrastructure](#output\_infrastructure) | Core infrastructure details for this deployment. |
| <a name="output_organizations"></a> [organizations](#output\_organizations) | The organizations configured in this deployment. |
| <a name="output_security_contexts"></a> [security\_contexts](#output\_security\_contexts) | Access details for each security context. |
<!-- END_TF_DOCS -->
