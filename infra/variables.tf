variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "ticket-notifier-511415"
}

variable "github_repository" {
  description = "GitHub repo allowed to deploy via OIDC, as OWNER/REPO"
  type        = string
}

variable "region" {
  description = "Region for Cloud Run, Artifact Registry and Cloud Scheduler"
  type        = string
  default     = "europe-west4"
}

variable "image_tag" {
  description = "Tag of the ticket-alert image in Artifact Registry (build/push it first, see Makefile)"
  type        = string
  default     = "latest"
}

variable "sender" {
  description = "Gmail from: filter (display name or address)"
  type        = string
  default     = "Celebratix"
}

variable "subject" {
  description = "Gmail subject: phrase filter (empty disables)"
  type        = string
  default     = "SPIELRAUM WEEKENDER OCT"
}

variable "link_pattern" {
  description = "Regex the extracted link must match"
  type        = string
  default     = "^https://shop\\.celebratix\\.io/resale/[\\w-]+(/[\\w-]+)+"
}

variable "pushover_user_key" {
  description = "Pushover user key (from the Pushover dashboard)"
  type        = string
  sensitive   = true
}

variable "pushover_app_token" {
  description = "Pushover application API token"
  type        = string
  sensitive   = true
}

variable "watch_schedule" {
  description = "Cron for renewing the Gmail watch (it expires after 7 days)"
  type        = string
  default     = "0 4 * * *"
}

variable "schedule_time_zone" {
  type    = string
  default = "Europe/Amsterdam"
}

variable "google_client_id" {
  type      = string
  sensitive = true
}

variable "google_client_secret" {
  type      = string
  sensitive = true
}

variable "google_refresh_token" {
  type      = string
  sensitive = true
}
