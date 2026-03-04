locals {
  service_accounts = concat(
    [
      {
        name = "stk-read-only"
        trust = [
          var.integration_surface.trust_aws.assetdb_role_name,
          var.integration_surface.trust_aws.execution_role_name,
          var.integration_surface.trust_aws.platform_role_name,
        ]
        roles = local.read_only_roles
      },
    ],
    [{
      name  = "stk-cost-query"
      trust = [var.integration_surface.trust_aws.cost_query_role_name]
      roles = []
    }],
    [
      for ctx in var.security_contexts : {
        name  = ctx.name
        trust = [var.integration_surface.trust_aws.execution_role_name]
        roles = concat(local.read_only_roles, ctx.extra_roles)
      }
    ],
  )

  aws_principal_prefix = join("", [
    "principalSet://iam.googleapis.com/",
    google_iam_workload_identity_pool.wif_access.name,
    "/attribute.aws_role/arn:aws:sts::",
    var.integration_surface.trust_aws.account_id,
    ":assumed-role/",
  ])

  sa_bindings = {
    for sa in local.service_accounts : sa.name => [
      for role_name in sa.trust : "${local.aws_principal_prefix}${role_name}"
    ]
  }

  org_bindings = flatten([
    for sa in local.service_accounts : [
      for role in sa.roles : [
        for org_id in local.whole_org_ids : {
          key      = "${sa.name}|${role}|${org_id}"
          sa_email = google_service_account.sa[sa.name].email
          role     = role
          org_id   = org_id
        }
      ]
    ]
  ])

  folder_bindings = flatten([
    for sa in local.service_accounts : [
      for role in sa.roles : [
        for folder_id in local.folder_ids : {
          key       = "${sa.name}|${role}|${folder_id}"
          sa_email  = google_service_account.sa[sa.name].email
          role      = role
          folder_id = folder_id
        }
      ]
    ]
  ])

  project_bindings = flatten([
    for sa in local.service_accounts : [
      for role in sa.roles : [
        for project_id in local.project_ids : {
          key        = "${sa.name}|${role}|${project_id}"
          sa_email   = google_service_account.sa[sa.name].email
          role       = role
          project_id = project_id
        }
      ]
    ]
  ])

  org_bindings_map     = { for binding in local.org_bindings : binding.key => binding }
  folder_bindings_map  = { for binding in local.folder_bindings : binding.key => binding }
  project_bindings_map = { for binding in local.project_bindings : binding.key => binding }
}

resource "google_service_account" "sa" {
  for_each = toset(local.service_accounts[*].name)

  project      = local.project_id
  account_id   = "${local.prefix}${each.key}"
  display_name = "Stacklet access - ${each.key}"

  depends_on = [google_project_service.service["iam"]]
}

# Grant WIF-based service account access
data "google_iam_policy" "sa_access" {
  for_each = local.sa_bindings

  binding {
    role    = "roles/iam.serviceAccountTokenCreator"
    members = each.value
  }
}

resource "google_service_account_iam_policy" "sa_access" {
  for_each = local.sa_bindings

  service_account_id = google_service_account.sa[each.key].name
  policy_data        = data.google_iam_policy.sa_access[each.key].policy_data
}

# Grant service account roles at organization level
resource "google_organization_iam_member" "sa_org_access" {
  for_each = local.org_bindings_map

  org_id = each.value.org_id
  role   = each.value.role
  member = "serviceAccount:${each.value.sa_email}"
}

# Grant service account roles at folder level
resource "google_folder_iam_member" "sa_folder_access" {
  for_each = local.folder_bindings_map

  folder = "folders/${each.value.folder_id}"
  role   = each.value.role
  member = "serviceAccount:${each.value.sa_email}"
}

# Grant service account roles at project level
resource "google_project_iam_member" "sa_project_access" {
  for_each = local.project_bindings_map

  project = each.value.project_id
  role    = each.value.role
  member  = "serviceAccount:${each.value.sa_email}"
}
