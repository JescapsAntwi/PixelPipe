# 🚀 PixelPipe - Intelligent Image Processing Pipeline

PixelPipe is a scalable, cloud-native image processing pipeline built on Google Cloud Platform (GCP). It enables automated, serverless, and highly available image ingestion, transformation, and storage, supporting both batch (CSV-driven) and direct API workflows.

---

## 🌟 Features

- **CSV-driven batch processing:** Upload a CSV file to trigger automated image processing for multiple images.
- **Direct API processing:** Submit single image jobs via a RESTful endpoint.
- **Multi-format output:** Generate images in multiple formats (JPEG, WebP, etc.) and sizes (thumbnails, resized).
- **Automatic thumbnails & resizing:** On-the-fly generation of thumbnails and custom sizes.
- **Real-time monitoring:** Integrated with Google Cloud Monitoring and Logging for observability.
- **Serverless architecture:** Built using Cloud Functions, Cloud Run, Pub/Sub, and Cloud Storage for scalability and cost-efficiency.
- **Extensible:** Modular codebase for easy addition of new processing features.

---

## 🏗️ Architecture Overview

PixelPipe consists of the following core components:

- **Cloud Storage Buckets:**
  - *CSV Source Bucket*: Triggers batch processing when a CSV is uploaded.
  - *Processed Images Bucket*: Stores all processed images.

- **Cloud Functions:**
  - *CSV Ingestion Function*: Parses uploaded CSV files and publishes image processing jobs to Pub/Sub.

- **Pub/Sub:**
  - *Image Processing Topic*: Decouples ingestion from processing, enabling scalable job distribution.

- **Cloud Run Service:**  
  - *Image Processor API*: Processes images (download, resize, convert, store) and exposes a `/process` endpoint for direct API jobs.

- **Firestore (optional):**  
  - *Job Metadata*: Stores job status and metadata for tracking and querying.

- **Monitoring & Logging:**  
  - Integrated with Google Cloud Monitoring and Logging for real-time observability.

See [docs/architecture.md](docs/architecture.md) for a detailed system diagram.

---

## 🚀 Quick Start

### 1. **Set Up Google Cloud Project**

- Install [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- Authenticate and create a new project:

  ```bash
  gcloud auth login
  gcloud projects create <your-project-id>
  gcloud config set project <your-project-id>
  gcloud auth application-default login
  ```

### 2. **Provision Infrastructure**

- Install [Terraform](https://www.terraform.io/downloads)
- Configure variables in `infrastructure/terraform.tfvars`
- Deploy resources:

  ```bash
  cd infrastructure
  terraform init
  terraform apply
  ```

### 3. **Build & Deploy Services**

- Build and push the Docker image:

  ```bash
  cd services
  docker build -t gcr.io/<your-project-id>/pixelpipe-processor:latest .
  gcloud auth configure-docker
  docker push gcr.io/<your-project-id>/pixelpipe-processor:latest
  ```

- Deploy Cloud Run and Cloud Functions (see [deployment guide](docs/deployment.md) for details).

### 4. **Batch Processing via CSV**

- Prepare a CSV file:

  ```csv
  image_id,url,priority,category
  img-001,https://example.com/image1.jpg,high,portrait
  img-002,https://example.com/image2.jpg,medium,landscape
  ```

- Upload to the CSV bucket:

  ```bash
  gsutil cp your_images.csv gs://<csv-bucket-name>/
  ```

### 5. **Direct API Processing**

- Send a POST request to the Cloud Run `/process` endpoint:

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

### 6. **Monitor & Debug**

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

## 🧩 Folder Structure

```
pixelpipe/
├── infrastructure/      # Terraform IaC scripts
├── functions/           # Cloud Functions source code
├── services/            # Cloud Run service (API & processor)
├── data/                # Schemas, sample data, CSV generator
├── scripts/             # Helper scripts for setup and deployment
├── tests/               # Unit and integration tests
├── docs/                # Documentation and architecture diagrams
└── .github/workflows/   # CI/CD pipelines
```

---

## 🛡️ Security & Best Practices

- Uses IAM service accounts with least privilege.
- Secrets and credentials are never stored in code; use environment variables and GCP Secret Manager.
- All endpoints are authenticated (optionally allow unauthenticated for demo).
- Follows Google Cloud and Terraform best practices for resource management.

---

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [Deployment Guide](docs/deployment.md)
- [API Reference](docs/api.md)
- [Troubleshooting](docs/troubleshooting.md)

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

---

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## 🙋‍♂️ Support

For questions or support, please open an issue or contact the maintainers.
