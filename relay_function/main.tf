resource "terraform_data" "source_sha" {
  input = var.source_sha
}

resource "google_cloudfunctions2_function" "relay" {
  name        = var.name
  project     = var.project
  location    = var.location
  description = var.description

  build_config {
    runtime     = "go124"
    entry_point = "ForwardEvent"

    source {
      storage_source {
        bucket = var.source_bucket
        object = var.source_object
      }
    }
  }

  service_config {
    # explicitly set concurrency and cpu values.  When CPU < 1, concurrency
    # value is set to 1 and can cause 429 errors when large numbers of
    # concurrent requests come in
    max_instance_request_concurrency = var.max_concurrency
    available_cpu                    = var.cpu
    available_memory                 = var.memory

    environment_variables = {
      AWS_EVENT_BUS     = var.aws_bus_arn
      AWS_ROLE          = var.aws_role_arn
      LOG_DEBUG         = var.debug ? "DEBUG" : ""
      RELAY_DETAIL_TYPE = var.relay_detail_type
    }
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    service_account_email = var.service_account_email
  }

  event_trigger {
    trigger_region        = var.location
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = var.pubsub_topic_id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = var.service_account_email
  }

  lifecycle {
    replace_triggered_by = [terraform_data.source_sha]
  }
}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project
  location       = var.location
  cloud_function = var.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${var.service_account_email}"
}

resource "google_cloud_run_service_iam_member" "invoker" {
  project  = var.project
  location = var.location
  service  = var.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.service_account_email}"
}
