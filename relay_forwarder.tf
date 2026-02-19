locals {
  events_relay_function_source = "relay-forwarder-function.zip"
}

# This is needed since when the Cloud Build job runs to create the function, it
# uses default compute@developer.gserviceaccount.com service account to write
# artifacts to registry, write build logs and also be able to view a storage
# bucket which it dynamically creates to hold the source code.
resource "google_project_iam_member" "cloud_build_artifact_registry" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/logging.logWriter",
    "roles/storage.objectViewer"
  ])

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${local.project_number}-compute@developer.gserviceaccount.com"

  depends_on = [google_project_service.service["iam"]]
}

data "archive_file" "events_relay_function_source" {
  type        = "zip"
  source_dir  = "${path.module}/relay_forwarder"
  output_path = "${path.module}/${local.events_relay_function_source}"
}

resource "google_storage_bucket" "events_relay_function_source_bucket" {
  name                        = "${var.resource_prefix}${local.project_id}-gcf-source"
  project                     = local.project_id
  location                    = var.bucket_location
  uniform_bucket_level_access = true

  soft_delete_policy {
    retention_duration_seconds = 0
  }
}

resource "terraform_data" "events_relay_function_source_sha" {
  input = data.archive_file.events_relay_function_source.output_sha
}

resource "google_storage_bucket_object" "events_relay_function_source" {
  name   = local.events_relay_function_source
  bucket = google_storage_bucket.events_relay_function_source_bucket.name
  source = data.archive_file.events_relay_function_source.output_path

  lifecycle {
    replace_triggered_by = [terraform_data.events_relay_function_source_sha]
  }
}

resource "google_service_account" "events_relay" {
  project = local.project_id

  account_id   = "${local.prefix}events-relay"
  display_name = "Stacklet events relay"

  depends_on = [google_project_service.service["iam"]]
}
