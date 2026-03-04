locals {
  # "cloudaudit.googleapis.com/activity" is the log name for "Admin Activity"
  # audit logs. The %2F encoding represents / when using filters in Terraform.
  # This filter ensures that only logs related to user-initiated API calls are
  # forwarded to the Pub/Sub topic.
  audit_filter = "logName:\"cloudaudit.googleapis.com%2Factivity\""
}

resource "google_pubsub_topic" "audit_feed" {
  name = "${local.prefix}audit-feed"

  project = local.project_id

  depends_on = [google_project_service.service["pubsub"]]
}

resource "google_logging_organization_sink" "audit_feed" {
  for_each = local.whole_org_ids

  name             = "${local.prefix}audit-feed-org-${each.key}"
  org_id           = each.key
  filter           = local.audit_filter
  include_children = true
  destination      = "pubsub.googleapis.com/${google_pubsub_topic.audit_feed.id}"
}

resource "google_pubsub_topic_iam_member" "audit_feed_publisher_org" {
  for_each = local.whole_org_ids

  project = local.project_id
  topic   = google_pubsub_topic.audit_feed.id
  role    = "roles/pubsub.publisher"
  member  = google_logging_organization_sink.audit_feed[each.key].writer_identity
}

resource "google_logging_folder_sink" "audit_feed" {
  for_each = local.folder_ids

  name             = "${local.prefix}audit-feed-folder-${each.key}"
  folder           = each.key
  filter           = local.audit_filter
  include_children = true
  destination      = "pubsub.googleapis.com/${google_pubsub_topic.audit_feed.id}"
}

resource "google_pubsub_topic_iam_member" "audit_feed_publisher_folder" {
  for_each = local.folder_ids

  project = local.project_id
  topic   = google_pubsub_topic.audit_feed.id
  role    = "roles/pubsub.publisher"
  member  = google_logging_folder_sink.audit_feed[each.key].writer_identity

}

resource "google_logging_project_sink" "audit_feed" {
  for_each = local.project_ids

  name        = "${local.prefix}audit-feed-project-${each.key}"
  project     = each.key
  filter      = local.audit_filter
  destination = "pubsub.googleapis.com/${google_pubsub_topic.audit_feed.id}"
}

resource "google_pubsub_topic_iam_member" "audit_feed_publisher_project" {
  for_each = local.project_ids

  project = local.project_id
  topic   = google_pubsub_topic.audit_feed.id
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.audit_feed[each.key].writer_identity
}

module "audit_relay" {
  source = "./relay_function"

  name              = "${local.prefix}audit-log-relay"
  description       = "Stacklet audit log relay"
  relay_detail_type = "GCP Audit Log"
  pubsub_topic_id   = google_pubsub_topic.audit_feed.id

  project               = local.project_id
  location              = var.infrastructure.resource_location
  source_bucket         = google_storage_bucket.events_relay_function_source_bucket.name
  source_object         = google_storage_bucket_object.events_relay_function_source.name
  source_sha            = terraform_data.events_relay_function_source_sha.output
  aws_bus_arn           = var.integration_surface.aws_relay.bus_arn
  aws_role_arn          = var.integration_surface.aws_relay.role_arn
  debug                 = var.advanced.debug
  memory                = var.advanced.memory
  event_max_age_s       = var.advanced.max_age_s
  service_account_email = google_service_account.events_relay.email

  depends_on = [google_project_service.service["cloudfunctions"]]
}
