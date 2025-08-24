# 🏗️ PixelPipe Architecture Overview

PixelPipe is designed as a modular, cloud-native image processing pipeline leveraging Google Cloud Platform (GCP) services for scalability, reliability, and cost-efficiency.

## Core Components

- **Cloud Storage Buckets**
  - *CSV Source Bucket*: Triggers batch processing when a CSV is uploaded.
  - *Processed Images Bucket*: Stores all processed images in various formats and sizes.

- **Cloud Functions**
  - *CSV Ingestion Function*: Parses uploaded CSV files and publishes image processing jobs to Pub/Sub.

- **Pub/Sub**
  - *Image Processing Topic*: Decouples ingestion from processing, enabling scalable job distribution.

- **Cloud Run Service**
  - *Image Processor API*: Processes images (download, resize, convert, store) and exposes a `/process` endpoint for direct API jobs.

- **Firestore (optional)**
  - *Job Metadata*: Stores job status and metadata for tracking and querying.

- **Monitoring & Logging**
  - Integrated with Google Cloud Monitoring and Logging for real-time observability.

## Data Flow Diagram

```mermaid
graph TD;
    A[CSV Upload to Source Bucket] --> B[Cloud Function: CSV Ingestion];
    B --> C[Pub/Sub: Image Processing Topic];
    C --> D[Cloud Run: Image Processor];
    D --> E[Processed Images Bucket];
    D --> F[Firestore (Job Metadata)];
    D --> G[Monitoring & Logging];
    H[Direct API Request] --> D;
```

## Sequence of Operations

1. **Batch Processing:**
   - User uploads a CSV file to the source bucket.
   - Cloud Function parses the CSV and publishes jobs to Pub/Sub.
   - Cloud Run service processes each job, downloads the image, applies transformations, and stores results.

2. **Direct API Processing:**
   - User sends a POST request to the `/process` endpoint.
   - Cloud Run service processes the image and stores results.

3. **Monitoring:**
   - All components emit logs and metrics to Google Cloud Monitoring for observability.

---

For more details, see the [Deployment Guide](deployment.md) and [API Reference](api.md).
