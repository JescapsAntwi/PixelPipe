# 🚀 PixelPipe Deployment Guide

This guide walks you through deploying the PixelPipe pipeline on Google Cloud Platform (GCP).

## Prerequisites

- Google Cloud account with billing enabled
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- [Terraform](https://www.terraform.io/downloads)
- Docker
- Python 3.11+

## 1. Set Up Google Cloud Project

```bash
gcloud auth login
gcloud projects create <your-project-id>
gcloud config set project <your-project-id>
gcloud auth application-default login
```

## 2. Provision Infrastructure

```bash
cd infrastructure
terraform init
terraform apply
```

- This will create storage buckets, Pub/Sub topics, service accounts, and deploy monitoring resources.

## 3. Build & Push Docker Image

```bash
cd services
docker build -t gcr.io/<your-project-id>/pixelpipe-processor:latest .
gcloud auth configure-docker
docker push gcr.io/<your-project-id>/pixelpipe-processor:latest
```

## 4. Deploy Cloud Run Service

```bash
gcloud run deploy pixelpipe-processor-dev \
  --image gcr.io/<your-project-id>/pixelpipe-processor:latest \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated
```

## 5. Deploy Cloud Function

```bash
cd ../functions
gcloud functions deploy process_csv \
  --runtime python311 \
  --trigger-bucket <csv-bucket-name> \
  --entry-point process_csv \
  --region us-central1 \
  --service-account pixelpipe-service-dev@<your-project-id>.iam.gserviceaccount.com
```

## 6. Test the Pipeline

- **Batch:** Upload a CSV to the source bucket:

  ```bash
  gsutil cp data/test_images.csv gs://<csv-bucket-name>/
  ```

- **Direct API:**

  ```bash
  curl -X POST <cloud-run-url>/process \
    -H "Content-Type: application/json" \
    -d '{
      "job_id": "demo-001",
      "image_id": "demo-img-001",
      "url": "https://picsum.photos/800/600",
      "processing_options": {
        "create_thumbnail": true,
        "resize_formats": ["400x300", "200x150"],
        "output_formats": ["jpeg", "webp"]
      }
    }'
  ```

## 7. Monitor & Debug

- View logs:

  ```bash
  gcloud logging read "resource.type=cloud_run_revision" --limit=20
  gcloud functions logs read process_csv --limit=20
  ```

- Check processed images:

  ```bash
  gsutil ls gs://<images-bucket-name>/
  ```

---

For troubleshooting, see [Troubleshooting](troubleshooting.md).
