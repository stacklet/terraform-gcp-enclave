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

output "access_blob" {
  description = "All other outputs crammed into a single copy/pasteable value."
  value = base64encode(jsonencode({
    projectId                = var.project.id
    wifAudience              = local.wif_audience
    serviceAccountsAccess    = local.service_accounts_access
    costExportTablesLocation = local.cost_export_table_locations
    roundtripDigest          = var.roundtrip_digest
  }))
}

output "old_access_blob" { # XXX matches access_blob from gcp-cost-setup, for testing
  value = base64encode(jsonencode({
    projectId           = local.project_id,
    tableLocations      = local.cost_export_table_locations,
    wifAudience         = local.wif_audience,
    wifImpersonationURL = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.sa["cost-export"].email}:generateAccessToken"
    roundtripDigest     = var.roundtrip_digest,
  }))
}
