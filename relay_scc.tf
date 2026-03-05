locals {
  # Only forward active findings. Filtering further (by severity, category, etc.)
  # would silently drop findings before the platform's policy engine sees them.
  scc_filter = "state = \"ACTIVE\""
}

resource "google_pubsub_topic" "scc_findings_feed" {
  name    = "${local.prefix}scc-findings-feed"
  project = local.project_id

  depends_on = [google_project_service.service["pubsub"]]
}

resource "google_scc_v2_organization_notification_config" "org_feed" {
  for_each = local.whole_org_ids

  config_id    = "${local.prefix}scc-feed-org-${each.key}"
  organization = each.key
  pubsub_topic = google_pubsub_topic.scc_findings_feed.id

  streaming_config {
    filter = local.scc_filter
  }

  depends_on = [google_project_service.service["securitycenter"]]
}

resource "google_scc_v2_folder_notification_config" "folder_feed" {
  for_each = local.folder_ids

  config_id    = "${local.prefix}scc-feed-folder-${each.key}"
  folder       = each.key
  pubsub_topic = google_pubsub_topic.scc_findings_feed.id

  streaming_config {
    filter = local.scc_filter
  }

  depends_on = [google_project_service.service["securitycenter"]]
}

resource "google_scc_v2_project_notification_config" "project_feed" {
  for_each = local.project_ids

  config_id    = "${local.prefix}scc-feed-project-${each.key}"
  project      = each.key
  pubsub_topic = google_pubsub_topic.scc_findings_feed.id

  streaming_config {
    filter = local.scc_filter
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
  location              = var.infrastructure.resource_location
  source_bucket         = google_storage_bucket.events_relay_function_source_bucket.name
  source_object         = google_storage_bucket_object.events_relay_function_source.name
  source_sha            = terraform_data.events_relay_function_source_sha.output
  aws_bus_arn           = var.integration_surface.aws_relay.bus_arn
  aws_role_arn          = var.integration_surface.aws_relay.role_arn
  debug                 = var.relay.debug
  memory                = var.relay.memory
  max_age_s             = var.relay.max_age_s
  max_instances         = var.relay.max_instances
  service_account_email = google_service_account.events_relay.email

  depends_on = [google_project_service.service["cloudfunctions"]]
}
