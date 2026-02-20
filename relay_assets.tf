locals {
  assets_org_excluded_folders_filter = {
    for org_id, folder_ids in local.org_excluded_folder_ids :
    org_id => join(", ", [for id in folder_ids : "\"folders/${id}\""])
  }
}

resource "google_pubsub_topic" "assets_feed" {
  name = "${local.prefix}assets-feed"

  project = local.project_id

  depends_on = [google_project_service.service["pubsub"]]
}

resource "google_cloud_asset_organization_feed" "org_feed" {
  for_each = local.whole_org_ids

  feed_id         = "${local.prefix}resource-feed-org-${each.key}"
  billing_project = local.project_id
  org_id          = each.key
  content_type    = "RESOURCE"

  asset_types = var.events_relay.asset_types

  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.assets_feed.id
    }
  }

  # asset.ancestors contains the full ancestry chain, so this excludes assets
  # in excluded folders and all their descendants.
  dynamic "condition" {
    for_each = length(local.org_excluded_folder_ids[each.key]) > 0 ? [1] : []
    content {
      expression = "!asset.ancestors.exists(a, a in [${local.assets_org_excluded_folders_filter[each.key]}])"
      title      = "Exclude specific folders"
    }
  }
}

resource "google_cloud_asset_folder_feed" "folder_feed" {
  for_each = local.folder_ids

  feed_id         = "${local.prefix}resource-feed-folder-${each.key}"
  billing_project = local.project_id
  folder          = each.key
  content_type    = "RESOURCE"

  asset_types = var.events_relay.asset_types

  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.assets_feed.id
    }
  }
}

resource "google_cloud_asset_project_feed" "project_feed" {
  for_each = local.project_ids

  feed_id         = "${local.prefix}resource-feed-project-${each.key}"
  billing_project = local.project_id
  project         = each.key
  content_type    = "RESOURCE"

  asset_types = var.events_relay.asset_types

  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.assets_feed.id
    }
  }
}

module "assets_relay" {
  source = "./relay_function"

  name              = "${local.prefix}asset-change-relay"
  description       = "Stacklet cloud asset changes relay"
  relay_detail_type = "GCP Cloud Asset Change"
  pubsub_topic_id   = google_pubsub_topic.assets_feed.id

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
