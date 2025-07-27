#!/bin/bash
# PixelPipe Deployment Script
# Deploy the entire pipeline to Google Cloud Platform

set -e  # Exit on any error

# Configuration
PROJECT_ID="${PROJECT_ID:-your-project-id}"
REGION="${REGION:-us-central1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if project ID is set
    if [ "$PROJECT_ID" = "your-project-id" ]; then
        log_error "Please set PROJECT_ID environment variable"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Set up GCP authentication and project
setup_gcp() {
    log_info "Setting up GCP configuration..."
    
    # Set project
    gcloud config set project "$PROJECT_ID"
    
    # Enable required APIs
    log_info "Enabling required GCP APIs..."
    gcloud services enable \
        cloudfunctions.googleapis.com \
        run.googleapis.com \
        pubsub.googleapis.com \
        storage.googleapis.com \
        cloudbuild.googleapis.com \
        eventarc.googleapis.com \
        logging.googleapis.com \
        monitoring.googleapis.com \
        firestore.googleapis.com
    
    log_success "GCP setup complete"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd infrastructure
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan \
        -var="project_id=$PROJECT_ID" \
        -var="region=$REGION" \
        -var="environment=$ENVIRONMENT"
    
    # Apply deployment
    terraform apply -auto-approve \
        -var="project_id=$PROJECT_ID" \
        -var="region=$REGION" \
        -var="environment=$ENVIRONMENT"
    
    # Save outputs
    CSV_BUCKET=$(terraform output -raw csv_bucket_name)
    IMAGES_BUCKET=$(terraform output -raw images_bucket_name)
    CLOUD_RUN_URL=$(terraform output -raw cloud_run_url)
    PUBSUB_TOPIC=$(terraform output -raw pubsub_topic)
    SERVICE_ACCOUNT=$(terraform output -raw service_account_email)
    
    cd ..
    
    log_success "Infrastructure deployed successfully"
}

# Build and deploy Cloud Run service
deploy_cloud_run() {
    log_info "Building and deploying Cloud Run service..."
    
    # Build container image
    IMAGE_NAME="gcr.io/$PROJECT_ID/pixelpipe-processor:latest"
    
    log_info "Building container image: $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" -f services/Dockerfile services/
    
    # Push to Container Registry
    log_info "Pushing image to Container Registry..."
    docker push "$IMAGE_NAME"
    
    # Deploy to Cloud Run
    log_info "Deploying to Cloud Run..."
    gcloud run deploy "pixelpipe-processor-$ENVIRONMENT" \
        --image "$IMAGE_NAME" \
        --region "$REGION" \
        --platform managed \
        --allow-unauthenticated \
        --memory 4Gi \
        --cpu 2 \
        --timeout 900 \
        --concurrency 10 \
        --min-instances 0 \
        --max-instances 10 \
        --set-env-vars "PROJECT_ID=$PROJECT_ID,BUCKET_NAME=$IMAGES_BUCKET,ENVIRONMENT=$ENVIRONMENT"
    
    log_success "Cloud Run service deployed"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    cd functions
    
    # Deploy CSV ingestion function (triggered by storage)
    log_info "Deploying CSV ingestion function..."
    gcloud functions deploy "pixelpipe-csv-ingestion-$ENVIRONMENT" \
        --gen2 \
        --runtime python311 \
        --region "$REGION" \
        --source . \
        --entry-point csv_upload_trigger \
        --trigger-bucket "$CSV_BUCKET" \
        --memory 1GB \
        --timeout 540 \
        --set-env-vars "PUBSUB_TOPIC=$PUBSUB_TOPIC" \
        --service-account "$SERVICE_ACCOUNT"
    
    # Deploy manual trigger function (HTTP)
    log_info "Deploying manual trigger function..."
    gcloud functions deploy "pixelpipe-manual-trigger-$ENVIRONMENT" \
        --gen2 \
        --runtime python311 \
        --region "$REGION" \
        --source . \
        --entry-point manual_csv_trigger \
        --trigger-http \
        --allow-unauthenticated \
        --memory 512MB \
        --timeout 300 \
        --set-env-vars "PUBSUB_TOPIC=$PUBSUB_TOPIC" \
        --service-account "$SERVICE_ACCOUNT"
    
    cd ..
    
    log_success "Cloud Functions deployed"
}

# Generate and upload sample CSV
generate_sample_data() {
    log_info "Generating and uploading sample CSV..."
    
    # Generate CSV using Python script
    python3 data/generate_csv.py
    
    # Upload to bucket
    gsutil cp data/image_database.csv "gs://$CSV_BUCKET/sample_data.csv"
    
    log_success "Sample data uploaded to gs://$CSV_BUCKET/sample_data.csv"
}

# Setup monitoring dashboard
setup_monitoring() {
    log_info "Setting up monitoring dashboard..."
    
    # Create custom dashboard (simplified version)
    cat > monitoring/dashboard_config.json << EOF
{
  "displayName": "PixelPipe Dashboard - $ENVIRONMENT",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Processing Jobs Status",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create dashboard
    gcloud monitoring dashboards create --config-from-file=monitoring/dashboard_config.json
    
    log_success "Monitoring dashboard created"
}

# Print deployment summary
print_summary() {
    log_success "🎉 PixelPipe deployment completed!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 DEPLOYMENT SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🌍 Environment: $ENVIRONMENT"
    echo "📍 Region: $REGION"
    echo "🎯 Project: $PROJECT_ID"
    echo ""
    echo "📦 RESOURCES CREATED:"
    echo "   • CSV Bucket: gs://$CSV_BUCKET"
    echo "   • Images Bucket: gs://$IMAGES_BUCKET"  
    echo "   • Cloud Run URL: $CLOUD_RUN_URL"
    echo "   • Pub/Sub Topic: $PUBSUB_TOPIC"
    echo ""
    echo "🚀 NEXT STEPS:"
    echo "   1. Upload your CSV file to: gs://$CSV_BUCKET/"
    echo "   2. Monitor processing at: $CLOUD_RUN_URL/stats"
    echo "   3. Check logs: gcloud logging read 'resource.type=cloud_run_revision'"
    echo "   4. View processed images: gs://$IMAGES_BUCKET/"
    echo ""
    echo "🔧 MANUAL TESTING:"
    echo "   curl -X POST $CLOUD_RUN_URL/process \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"url\": \"https://picsum.photos/800/600\"}'"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution
main() {
    echo "🚀 Starting PixelPipe deployment..."
    echo ""
    
    check_prerequisites
    setup_gcp
    deploy_infrastructure
    deploy_cloud_run
    deploy_functions
    generate_sample_data
    setup_monitoring
    print_summary
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "destroy")
        log_warning "Destroying infrastructure..."
        cd infrastructure
        terraform destroy -auto-approve \
            -var="project_id=$PROJECT_ID" \
            -var="region=$REGION" \
            -var="environment=$ENVIRONMENT"
        log_success "Infrastructure destroyed"
        ;;
    "status")
        log_info "Checking deployment status..."
        gcloud run services list --region="$REGION"
        gcloud functions list --region="$REGION"
        gsutil ls "gs://$PROJECT_ID-pixelpipe-*"
        ;;
    *)
        echo "Usage: $0 [deploy|destroy|status]"
        exit 1
        ;;
esac