resource "google_artifact_registry_repository" "images" {
  repository_id = "ticket-alert"
  location      = var.region
  format        = "DOCKER"
  description   = "ticket-alert container images"

  depends_on = [google_project_service.apis]
}

locals {
  image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}/ticket-alert:${var.image_tag}"
}
