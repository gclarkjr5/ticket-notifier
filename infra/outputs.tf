output "service_url" {
  value = google_cloud_run_v2_service.alert.uri
}

output "image" {
  value = local.image
}

output "pubsub_topic" {
  value = google_pubsub_topic.gmail_push.id
}

output "start_watch_command" {
  description = "Run once after the first apply to start the Gmail watch immediately"
  value       = "gcloud scheduler jobs run ${google_cloud_scheduler_job.renew_watch.name} --location ${var.region} --project ${var.project_id}"
}

output "github_workload_identity_provider" {
  description = "Set as GitHub repo variable GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_deployer_service_account" {
  description = "Set as GitHub repo variable GCP_DEPLOYER_SA"
  value       = google_service_account.deployer.email
}
