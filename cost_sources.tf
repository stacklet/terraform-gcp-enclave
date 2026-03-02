locals {
  source_tables = [for s in var.cost_sources : {
    "key" : s.billing_table,
    "project_id" : split(".", s.billing_table)[0],
    "dataset_id" : split(".", s.billing_table)[1],
    "table_id" : split(".", s.billing_table)[2],
  }]
}

resource "google_bigquery_table_iam_member" "sa_bq_tables" {
  for_each = { for table in local.source_tables : table.key => table }

  project    = each.value.project_id
  dataset_id = each.value.dataset_id
  table_id   = each.value.table_id
  role       = "roles/bigquery.dataViewer"
  member     = google_service_account.sa["stk-cost-query"].member
}


resource "google_project_iam_member" "cost_query_job_user" {
  count = length(var.cost_sources) > 0 ? 1 : 0

  project = local.project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.sa["stk-cost-query"].member
}

# Discover dataset locations for output.
data "google_bigquery_dataset" "table_datasets" {
  for_each = { for table in local.source_tables : table.key => table }

  project    = each.value.project_id
  dataset_id = each.value.dataset_id
}
