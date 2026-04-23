data "external" "org_access" {
  for_each = local.org_ids

  program = ["bash", "-c", "gcloud organizations describe '${each.key}' >/dev/null && printf '{\"ok\":\"true\"}' || printf '{\"ok\":\"false\"}'"]
}

data "google_organization" "conf" {
  for_each = toset([for id, r in data.external.org_access : id if r.result.ok == "true"])

  organization = each.key
}

data "google_folder" "conf" {
  for_each = local.folder_ids

  folder = each.key
}

data "google_project" "conf" {
  for_each = local.project_ids

  project_id = each.key
}

locals {
  builtin_roles = local.read_only_roles

  organizations = [
    for org in var.organizations : {
      id   = org.org_id
      name = try(data.google_organization.conf[org.org_id].domain, "Org ${org.org_id}")
      folders = [
        for folder_id in org.folder_ids : {
          id   = folder_id
          name = data.google_folder.conf[folder_id].display_name
        }
      ]
      projects = [
        for project_id in org.project_ids : {
          id     = project_id
          number = data.google_project.conf[project_id].number
        }
      ]
    }
  ]

  infrastructure = {
    project_id = local.project_id
    relay = {
      oauth_id = google_service_account.events_relay.unique_id
    }
    wif = {
      audience = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.aws_access.name}"
      principals = {
        read_only  = google_service_account.sa["stk-read-only"].email
        cost_query = google_service_account.sa["stk-cost-query"].email
      }
    }
    builtin_roles = local.builtin_roles
  }

  security_contexts = [
    for ctx in var.security_contexts : {
      name        = ctx.name
      extra_roles = ctx.extra_roles
      principal   = google_service_account.sa[ctx.name].email
    }
  ]

  cost_sources = [
    for s in var.cost_sources : {
      billing_table = s.billing_table
      location      = data.google_bigquery_dataset.table_datasets[s.billing_table].location
    }
  ]
}

output "infrastructure" {
  description = "Core infrastructure details for this deployment."
  value       = local.infrastructure
}

output "security_contexts" {
  description = "Access details for each security context."
  value       = local.security_contexts
}

output "organizations" {
  description = "The organizations configured in this deployment."
  value       = local.organizations
}

output "cost_sources" {
  description = "The location of each cost source table."
  value       = local.cost_sources
}

output "access_blob" {
  description = "All other outputs crammed into a single copy/pasteable value."
  value = base64encode(jsonencode({
    infrastructure = {
      projectId = local.infrastructure.project_id
      relay     = { oauthId = local.infrastructure.relay.oauth_id }
      wif = {
        audience = local.infrastructure.wif.audience
        principals = {
          readOnly  = local.infrastructure.wif.principals.read_only
          costQuery = local.infrastructure.wif.principals.cost_query
        }
      }
      builtinRoles = local.builtin_roles
    }
    organizations = local.organizations
    costSources = [
      for s in local.cost_sources : {
        billingTable = s.billing_table
        location     = s.location
      }
    ]
    securityContexts = [
      for c in local.security_contexts : {
        name       = c.name
        extraRoles = c.extra_roles
        principal  = c.principal
      }
    ]
    roundtripDigest = var.roundtrip_digest
  }))
}
