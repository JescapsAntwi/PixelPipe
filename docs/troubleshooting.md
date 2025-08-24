# 🛠️ PixelPipe Troubleshooting Guide

This guide helps you diagnose and resolve common issues with PixelPipe deployments.

---

## 1. Infrastructure Issues

### Terraform Errors

- **Duplicate resource/variable/output:** Remove duplicates from `.tf` files.
- **Provider errors:** Ensure correct provider version and credentials.
- **API not enabled:** Enable required GCP APIs in the console or via `gcloud services enable`.

### Permission Errors

- **Service account missing permissions:**
  - Check IAM roles for service accounts.
  - Use least privilege principle.

---

## 2. Deployment Issues

### Docker Build Fails

- **Missing dependencies:** Ensure all system and Python dependencies are listed in the Dockerfile and requirements.txt.
- **Build context issues:** Run `docker build` from the correct directory.

### Cloud Run Deploy Fails

- **Image not found:** Make sure you pushed the image to GCR and used the correct tag.
- **Permission denied:** Check service account permissions and GCR access.

---

## 3. Runtime Issues

### Cloud Function Not Triggering

- **CSV not in correct bucket:** Upload to the correct source bucket.
- **Function not deployed:** Redeploy with correct trigger and entry point.

### Cloud Run 500 Errors

- **Check logs:**

  ```bash
  gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=pixelpipe-processor-dev" --limit 20
  ```

- **Common causes:**
  - Invalid request body
  - Missing environment variables
  - GCP credentials not mounted in Docker

---

## 4. Monitoring & Debugging

- **View logs:**

  ```bash
  gcloud functions logs read process_csv --limit=20
  gcloud logging read "resource.type=cloud_run_revision" --limit=20
  ```

- **Check processed images:**

  ```bash
  gsutil ls gs://<images-bucket-name>/
  ```

- **Check Pub/Sub messages:**

  ```bash
  gcloud pubsub subscriptions pull pixelpipe-processing-sub-dev --auto-ack --limit=5
  ```

---

## 5. Getting Help

- Review documentation in the `docs/` folder.
- Search for similar issues on GitHub.
- Open a new issue with detailed logs and error messages.
