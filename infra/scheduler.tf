# Re-registers the Gmail watch daily (watches expire after 7 days).
resource "google_cloud_scheduler_job" "renew_watch" {
  name        = "renew-gmail-watch"
  region      = var.region
  schedule    = var.watch_schedule
  time_zone   = var.schedule_time_zone
  description = "POST /renew on ticket-alert to refresh users.watch"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.alert.uri}/renew"

    oidc_token {
      service_account_email = google_service_account.invoker.email
      audience              = google_cloud_run_v2_service.alert.uri
    }
  }

  depends_on = [google_cloud_run_v2_service_iam_member.invoker]
}
