resource "google_pubsub_topic" "gmail_push" {
  name = "gmail-push"

  depends_on = [google_project_service.apis]
}

# Gmail publishes change notifications as this Google-owned account.
resource "google_pubsub_topic_iam_member" "gmail_publisher" {
  topic  = google_pubsub_topic.gmail_push.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:gmail-api-push@system.gserviceaccount.com"
}

resource "google_pubsub_subscription" "push" {
  name                 = "gmail-push-sub"
  topic                = google_pubsub_topic.gmail_push.id
  ack_deadline_seconds = 30

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.alert.uri}/"

    oidc_token {
      service_account_email = google_service_account.invoker.email
      audience              = google_cloud_run_v2_service.alert.uri
    }
  }

  # Fail fast, retry fast: a missed alert is worse than a duplicate request.
  retry_policy {
    minimum_backoff = "1s"
    maximum_backoff = "10s"
  }

  depends_on = [
    google_cloud_run_v2_service_iam_member.invoker,
    google_service_account_iam_member.pubsub_token_creator,
  ]
}
