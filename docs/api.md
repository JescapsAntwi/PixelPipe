# 📖 PixelPipe API Reference

## Cloud Run Service: Image Processor API

### Base URL

```
https://<cloud-run-url>
```

### Endpoints

---

### `POST /process`

**Description:** Submit an image processing job directly to the pipeline.

**Request Body (JSON):**

```
{
  "job_id": "string",            // Unique job identifier
  "image_id": "string",          // Unique image identifier
  "url": "string",               // Source image URL
  "priority": "low|medium|high", // (optional) Processing priority
  "category": "string",          // (optional) Image category
  "processing_options": {
    "create_thumbnail": true,
    "extract_metadata": true,
    "resize_formats": ["800x600", "400x300"],
    "output_formats": ["jpeg", "webp"]
  }
}
```

**Response:**

- `200 OK` with job status and output locations
- `400 Bad Request` for invalid input
- `500 Internal Server Error` for processing errors

**Example:**

```
curl -X POST https://<cloud-run-url>/process \
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

---

### `GET /health`

**Description:** Health check endpoint for service monitoring.

**Response:**

- `200 OK` with status message

---

## Cloud Function: CSV Ingestion

Triggered automatically when a CSV is uploaded to the source bucket. No direct API.

**CSV Format:**

```
image_id,url,priority,category
img-001,https://example.com/image1.jpg,high,portrait
img-002,https://example.com/image2.jpg,medium,landscape
```

---

## Error Codes

- `400`: Invalid request or missing fields
- `404`: Resource not found
- `500`: Internal server error

---

For more details, see [Architecture Overview](architecture.md) and [Deployment Guide](deployment.md).
