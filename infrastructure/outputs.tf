
output "csv_bucket_name" {
  description = "Name of the CSV source bucket"
  value       = google_storage_bucket.csv_source.name
}

output "images_bucket_name" {
  description = "Name of the processed images bucket"
  value       = google_storage_bucket.processed_images.name
}

output "cloud_run_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.image_processor.uri
}

output "pubsub_topic" {
  description = "Pub/Sub topic for image processing"
  value       = google_pubsub_topic.image_processing.name
}

output "service_account_email" {
  description = "Service account email"
  value       = google_service_account.pixelpipe_sa.email
}
