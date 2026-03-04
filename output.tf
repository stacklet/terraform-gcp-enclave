locals {
  wif_audience = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.aws_access.name}"
  service_accounts_access = [
    for sa in local.service_accounts : {
      name  = sa.name
      roles = sa.roles
      email = google_service_account.sa[sa.name].email
    }
  ]
  cost_source_locations = [
    for s in var.cost_sources : {
      billing_table = s.billing_table
      location      = data.google_bigquery_dataset.table_datasets[s.billing_table].location
    }
  ]
}

output "project_id" {
  description = "The project the created resources exist in."
  value       = local.project_id
}

output "wif_audience" {
  description = "The audience value required for impersonation interactions."
  value       = local.wif_audience
}

output "service_accounts_access" {
  description = "Access details for each service account."
  value       = local.service_accounts_access
}

output "organizations" {
  description = "The organizations configured in this deployment."
  value       = var.organizations
}

output "cost_source_locations" {
  description = "The location of each cost source table."
  value       = local.cost_source_locations
}

output "relay_service_account_oauth_id" {
  description = "OAuth ID for the service account used to relay events to AWS."
  value       = google_service_account.events_relay.unique_id
}

output "access_blob" {
  description = "All other outputs crammed into a single copy/pasteable value."
  value = base64encode(jsonencode({
    infrastructure = {
      projectId    = local.project_id
      relayOAuthId = google_service_account.events_relay.unique_id
      wifAudience  = local.wif_audience
    }
    organizations = [
      for org in var.organizations : {
        orgId      = org.org_id
        folderIds  = org.folder_ids
        projectIds = org.project_ids
      }
    ]
    costSources = [
      for s in local.cost_source_locations : {
        billingTable = s.billing_table
        location     = s.location
      }
    ]
    serviceAccounts = local.service_accounts_access
    roundtripDigest = var.roundtrip_digest
  }))
}

output "legacy_cost_access_blob" { # XXX matches access_blob from gcp-cost-setup, for testing
  value = base64encode(jsonencode({
    projectId       = local.project_id
    roundtripDigest = var.roundtrip_digest
    tableLocations = [
      for s in var.cost_sources : {
        table    = s.billing_table
        location = data.google_bigquery_dataset.table_datasets[s.billing_table].location
      }
    ]
    wifAudience         = local.wif_audience,
    wifImpersonationURL = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.sa["stk-cost-query"].email}:generateAccessToken"
  }))
}
