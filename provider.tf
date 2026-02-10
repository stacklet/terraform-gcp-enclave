terraform {
  required_version = ">= 1.11"

  required_providers {
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
