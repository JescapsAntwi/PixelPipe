# main.tf - Core Infrastructure for PixelPipe
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}


# Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable Required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "run.googleapis.com", 
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  service = each.key
  disable_on_destroy = false
}

# Storage Buckets
resource "google_storage_bucket" "csv_source" {
  name     = "${var.project_id}-pixelpipe-csv-${var.environment}"
  location = var.region
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "processed_images" {
  name     = "${var.project_id}-pixelpipe-images-${var.environment}"  
  location = var.region
  
  uniform_bucket_level_access = true
  
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}

resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-pixelpipe-functions-${var.environment}"
  location = var.region
  
  uniform_bucket_level_access = true
}

# Pub/Sub Topics and Subscriptions  
resource "google_pubsub_topic" "image_processing" {
  name = "pixelpipe-image-processing-${var.environment}"
  
  message_retention_duration = "86400s" # 24 hours
}

resource "google_pubsub_topic" "dead_letter" {
  name = "pixelpipe-dead-letter-${var.environment}"
}

resource "google_pubsub_subscription" "image_processing_sub" {
  name  = "pixelpipe-processing-sub-${var.environment}"
  topic = google_pubsub_topic.image_processing.name
  
  ack_deadline_seconds = 300 # 5 minutes
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
}

# Service Account for Functions and Cloud Run
resource "google_service_account" "pixelpipe_sa" {
  account_id   = "pixelpipe-service-${var.environment}"
  display_name = "PixelPipe Service Account"
  description  = "Service account for PixelPipe image processing pipeline"
}

# IAM Bindings
resource "google_project_iam_member" "pixelpipe_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.pixelpipe_sa.email}"
}

resource "google_project_iam_member" "pixelpipe_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.editor"  
  member  = "serviceAccount:${google_service_account.pixelpipe_sa.email}"
}

resource "google_project_iam_member" "pixelpipe_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.pixelpipe_sa.email}"
}

# Cloud Run Service for Image Processing
resource "google_cloud_run_v2_service" "image_processor" {
  name     = "pixelpipe-processor-${var.environment}"
  location = var.region
  
  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
    
    containers {
      image = "gcr.io/${var.project_id}/pixelpipe-processor:latest"
      
      resources {
        limits = {
          cpu    = "2"
          memory = "4Gi"  
        }
      }
      
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "BUCKET_NAME" 
        value = google_storage_bucket.processed_images.name
      }
      
      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.image_processing.name
      }
    }
    
    service_account = google_service_account.pixelpipe_sa.email
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
}

# Allow unauthenticated access to Cloud Run (for demo purposes)
resource "google_cloud_run_service_iam_member" "run_all_users" {
  service  = google_cloud_run_v2_service.image_processor.name
  location = google_cloud_run_v2_service.image_processor.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

