terraform {
  required_version = ">= 1.11"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.18"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
