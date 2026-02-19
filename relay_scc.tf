resource "google_pubsub_topic" "scc_findings_feed" {
  name    = "${local.prefix}scc-findings-feed"
  project = local.project_id

  depends_on = [google_project_service.service["pubsub"]]
}

resource "google_scc_v2_organization_notification_config" "org_feed" {
  for_each = toset(var.access_scope.org_ids)

  config_id    = "${local.prefix}scc-feed-org-${each.key}"
  organization = each.key
  pubsub_topic = google_pubsub_topic.scc_findings_feed.id

  streaming_config {
    filter = var.events_relay.security_findings_filter
  }

  depends_on = [google_project_service.service["securitycenter"]]
}

resource "google_scc_v2_folder_notification_config" "folder_feed" {
  for_each = toset(var.access_scope.folder_ids)

  config_id    = "${local.prefix}scc-feed-folder-${each.key}"
  folder       = each.key
  pubsub_topic = google_pubsub_topic.scc_findings_feed.id

  streaming_config {
    filter = var.events_relay.security_findings_filter
  }

  depends_on = [google_project_service.service["securitycenter"]]
}

resource "google_scc_v2_project_notification_config" "project_feed" {
  for_each = toset(var.access_scope.project_ids)

  config_id    = "${local.prefix}scc-feed-project-${each.key}"
  project      = each.key
  pubsub_topic = google_pubsub_topic.scc_findings_feed.id

  streaming_config {
    filter = var.events_relay.security_findings_filter
  }

  depends_on = [google_project_service.service["securitycenter"]]
}

module "scc_finding_relay" {
  source = "./relay_function"

  name              = "${local.prefix}scc-finding-relay"
  description       = "Stacklet security command center finding relay"
  relay_detail_type = "GCP SCC Finding"
  pubsub_topic_id   = google_pubsub_topic.scc_findings_feed.id

  project               = local.project_id
  location              = var.location
  source_bucket         = google_storage_bucket.events_relay_function_source_bucket.name
  source_object         = google_storage_bucket_object.events_relay_function_source.name
  source_sha            = terraform_data.events_relay_function_source_sha.output
  aws_bus_arn           = var.events_relay.aws_bus_arn
  aws_role_arn          = var.events_relay.aws_role_arn
  debug                 = var.events_relay.function.debug
  max_concurrency       = var.events_relay.function.max_concurrency
  cpu                   = var.events_relay.function.cpu
  memory                = var.events_relay.function.memory
  service_account_email = google_service_account.events_relay.email

  depends_on = [google_project_service.service["cloudfunctions"]]
}
