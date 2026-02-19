locals {
  wif_audience = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.aws_access.name}"
  service_accounts_access = [
    for sa in local.service_accounts : {
      name  = sa.name
      email = google_service_account.sa[sa.name].email
    }
  ]
  cost_export_table_locations = [
    for key in var.cost_export_billing_tables : {
      table    = key,
      location = data.google_bigquery_dataset.table_datasets[key].location,
    }
  ]
}

output "project_id" {
  description = "The project the created resources exist in."
  value       = var.project.id
}

output "wif_audience" {
  description = "The audience value required for impersonation interactions."
  value       = local.wif_audience
}

output "service_accounts_access" {
  description = "Access details for each service account."
  value       = local.service_accounts_access
}

output "cost_export_table_locations" {
  description = "The data location for each cost export table made accessible."
  value       = local.cost_export_table_locations
}

output "relay_service_account_oauth_id" {
  description = "OAuth ID for the the service account used for events relay"
  value       = google_service_account.events_relay.unique_id
}

output "access_blob" {
  description = "All other outputs crammed into a single copy/pasteable value."
  value = base64encode(jsonencode({
    costExportTablesLocation   = local.cost_export_table_locations
    projectId                  = var.project.id
    relayServiceAccountOAuthID = google_service_account.events_relay.unique_id
    roundtripDigest            = var.roundtrip_digest
    serviceAccountsAccess      = local.service_accounts_access
    wifAudience                = local.wif_audience
  }))
}

output "old_access_blob" { # XXX matches access_blob from gcp-cost-setup, for testing
  value = base64encode(jsonencode({
    projectId           = local.project_id
    roundtripDigest     = var.roundtrip_digest
    tableLocations      = local.cost_export_table_locations
    wifAudience         = local.wif_audience,
    wifImpersonationURL = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.sa["cost-export"].email}:generateAccessToken"
  }))
}
