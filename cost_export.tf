locals {
  source_tables = [for key in var.cost_export_billing_tables : {
    "key" : key,
    "project_id" : split(".", key)[0],
    "dataset_id" : split(".", key)[1],
    "table_id" : split(".", key)[2],
  }]
}

resource "google_project_service" "bigquery" {
  count = length(var.cost_export_billing_tables) > 0 ? 1 : 0

  project = local.project_id
  service = "bigquery.googleapis.com"

  disable_on_destroy         = false
  disable_dependent_services = true
}

resource "google_bigquery_table_iam_member" "sa_bq_tables" {
  for_each = { for table in local.source_tables : table.key => table }

  project    = each.value.project_id
  dataset_id = each.value.dataset_id
  table_id   = each.value.table_id
  role       = "roles/bigquery.dataViewer"
  member     = google_service_account.sa["cost-export"].member
}


# Discover dataset locations for output.
data "google_bigquery_dataset" "table_datasets" {
  for_each = { for table in local.source_tables : table.key => table }

  project    = each.value.project_id
  dataset_id = each.value.dataset_id
}
