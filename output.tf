locals {
  builtin_roles = local.read_only_roles
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
  value       = var.organizations
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
    organizations = [
      for org in var.organizations : {
        orgId      = org.org_id
        folderIds  = org.folder_ids
        projectIds = org.project_ids
      }
    ]
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
