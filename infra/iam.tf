# Identity the Rust service runs as: may read the three OAuth secrets and nothing else.
resource "google_service_account" "runtime" {
  account_id   = "ticket-alert-run"
  display_name = "ticket-alert Cloud Run runtime"

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_iam_member" "runtime_reads" {
  for_each  = google_secret_manager_secret.oauth
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

# Identity Pub/Sub and Cloud Scheduler use to call the (private) service.
resource "google_service_account" "invoker" {
  account_id   = "ticket-alert-invoker"
  display_name = "ticket-alert invoker (Pub/Sub push + Scheduler)"

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  name     = google_cloud_run_v2_service.alert.name
  location = google_cloud_run_v2_service.alert.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.invoker.email}"
}

# Lets the Pub/Sub service agent mint OIDC tokens as the invoker account.
resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.invoker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  depends_on = [google_project_service.apis]
}
