resource "google_cloud_run_v2_service" "alert" {
  name                = "ticket-alert"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL" # still private: no allUsers invoker binding
  deletion_protection = false

  template {
    service_account = google_service_account.runtime.email

    # One instance only: the in-process mutex is what prevents double notifications.
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    containers {
      image = local.image

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }

        # CPU only while handling a request (all our work happens inside the request).
        # Much cheaper than "always allocated", which also requires >= 512Mi.
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "SENDER"
        value = var.sender
      }
      env {
        name  = "SUBJECT"
        value = var.subject
      }
      env {
        name  = "LINK_PATTERN"
        value = var.link_pattern
      }
      env {
        name  = "NTFY_SERVER"
        value = var.ntfy_server
      }
      env {
        name  = "NTFY_TOPIC"
        value = var.ntfy_topic
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.gmail_push.id
      }

      dynamic "env" {
        for_each = google_secret_manager_secret.oauth
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_id
              version = google_secret_manager_secret_version.oauth[env.key].version
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_version.oauth,
    google_secret_manager_secret_iam_member.runtime_reads,
  ]
}
