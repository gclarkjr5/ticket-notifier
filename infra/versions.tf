terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote state so CI and your laptop share it. The bucket is created by `just bootstrap`
  # (backend config can't use variables, hence the literal name).
  backend "gcs" {
    bucket = "ticket-notifier-511415-tfstate"
    prefix = "ticket-notifier"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
