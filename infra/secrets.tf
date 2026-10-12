locals {
  secrets = {
    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REFRESH_TOKEN = var.google_refresh_token
    PUSHOVER_USER_KEY    = var.pushover_user_key
    PUSHOVER_APP_TOKEN   = var.pushover_app_token
  }
}

resource "google_secret_manager_secret" "oauth" {
  for_each  = toset(keys(local.secrets))
  secret_id = each.value

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "oauth" {
  for_each    = toset(keys(local.secrets))
  secret      = google_secret_manager_secret.oauth[each.value].id
  secret_data = local.secrets[each.value]

  # New version first, so Cloud Run can move to it before the old one is destroyed.
  lifecycle {
    create_before_destroy = true
  }
}
