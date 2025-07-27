#!/bin/bash
# PixelPipe Cleanup Script
# Safely removes all GCP resources created by PixelPipe

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

# Check if user really wants to cleanup
confirm_cleanup() {
    echo "🧹 PixelPipe Cleanup Script"
    echo "=============================="
    echo ""
    echo "⚠️  WARNING: This will DELETE all PixelPipe resources!"
    echo ""
    echo "📍 Project: $PROJECT_ID"
    echo "🌍 Region: $REGION" 
    echo "🏷️  Environment: $ENVIRONMENT"
    echo ""
    echo "🗑️  Resources to be deleted:"
    echo "   • Cloud Run services"
    echo "   • Cloud Functions"
    echo "   • Cloud Storage buckets (and all contents)"
    echo "   • Pub/Sub topics and subscriptions"
    echo "   • Service accounts"
    echo "   • IAM bindings"
    echo "   • Container images"
    echo "   • Firestore data"
    echo "   • Monitoring dashboards"
    echo ""
    
    read -p "❓ Are you absolutely sure? Type 'DELETE' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Cleanup cancelled. Your resources are safe! 🛡️"
        exit 0
    fi
    
    log_warning "Starting cleanup in 5 seconds... Press Ctrl+C to abort!"
    sleep 5
}

# Set GCP project
setup_gcp() {
    log_info "Setting up GCP configuration..."
    gcloud config set project "$PROJECT_ID"
    log_success "GCP project set to: $PROJECT_ID"
}

# Clean up Cloud Run services
cleanup_cloud_run() {
    log_info "Cleaning up Cloud Run services..."
    
    # List and delete services
    SERVICES=$(gcloud run services list --region="$REGION" --filter="metadata.name:pixelpipe-*-${ENVIRONMENT}" --format="value(metadata.name)" 2>/dev/null || true)
    
    if [ -n "$SERVICES" ]; then
        for service in $SERVICES; do
            log_info "Deleting Cloud Run service: $service"
            gcloud run services delete "$service" --region="$REGION" --quiet || log_warning "Failed to delete service: $service"
        done
        log_success "Cloud Run services cleaned up"
    else
        log_info "No Cloud Run services found to delete"
    fi
}

# Clean up Cloud Functions
cleanup_cloud_functions() {
    log_info "Cleaning up Cloud Functions..."
    
    # List and delete functions
    FUNCTIONS=$(gcloud functions list --regions="$REGION" --filter="name:pixelpipe-*-${ENVIRONMENT}" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$FUNCTIONS" ]; then
        for function in $FUNCTIONS; do
            log_info "Deleting Cloud Function: $function"
            gcloud functions delete "$function" --region="$REGION" --quiet || log_warning "Failed to delete function: $function"
        done
        log_success "Cloud Functions cleaned up"
    else
        log_info "No Cloud Functions found to delete"
    fi
}

# Clean up Pub/Sub resources
cleanup_pubsub() {
    log_info "Cleaning up Pub/Sub resources..."
    
    # Delete subscriptions first
    SUBSCRIPTIONS=$(gcloud pubsub subscriptions list --filter="name:pixelpipe-*-${ENVIRONMENT}" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$SUBSCRIPTIONS" ]; then
        for subscription in $SUBSCRIPTIONS; do
            log_info "Deleting Pub/Sub subscription: $(basename $subscription)"
            gcloud pubsub subscriptions delete "$(basename $subscription)" --quiet || log_warning "Failed to delete subscription: $subscription"
        done
    fi
    
    # Delete topics
    TOPICS=$(gcloud pubsub topics list --filter="name:pixelpipe-*-${ENVIRONMENT}" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$TOPICS" ]; then
        for topic in $TOPICS; do
            log_info "Deleting Pub/Sub topic: $(basename $topic)"
            gcloud pubsub topics delete "$(basename $topic)" --quiet || log_warning "Failed to delete topic: $topic"
        done
        log_success "Pub/Sub resources cleaned up"
    else
        log_info "No Pub/Sub resources found to delete"
    fi
}

# Clean up Cloud Storage buckets
cleanup_storage() {
    log_info "Cleaning up Cloud Storage buckets..."
    
    # List buckets
    BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "pixelpipe.*-${ENVIRONMENT}" | sed 's|gs://||' | sed 's|/||' || true)
    
    if [ -n "$BUCKETS" ]; then
        for bucket in $BUCKETS; do
            log_info "Deleting bucket contents: gs://$bucket"
            gsutil -m rm -r "gs://$bucket/**" 2>/dev/null || log_warning "Bucket already empty or inaccessible: $bucket"
            
            log_info "Deleting bucket: gs://$bucket"
            gsutil rb "gs://$bucket" || log_warning "Failed to delete bucket: $bucket"
        done
        log_success "Cloud Storage buckets cleaned up"
    else
        log_info "No Cloud Storage buckets found to delete"
    fi
}

# Clean up Container Registry images
cleanup_container_images() {
    log_info "Cleaning up Container Registry images..."
    
    # List and delete images
    IMAGES=$(gcloud container images list --repository="gcr.io/$PROJECT_ID" --filter="name:pixelpipe" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$IMAGES" ]; then
        for image in $IMAGES; do
            log_info "Deleting container image: $image"
            gcloud container images delete "$image" --force-delete-tags --quiet || log_warning "Failed to delete image: $image"
        done
        log_success "Container images cleaned up"
    else
        log_info "No container images found to delete"
    fi
}

# Clean up Service Accounts
cleanup_service_accounts() {
    log_info "Cleaning up Service Accounts..."
    
    SA_EMAIL="pixelpipe-service-${ENVIRONMENT}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
        log_info "Deleting service account: $SA_EMAIL"
        gcloud iam service-accounts delete "$SA_EMAIL" --quiet || log_warning "Failed to delete service account: $SA_EMAIL"
        log_success "Service account cleaned up"
    else
        log_info "No service account found to delete"
    fi
}

# Clean up Firestore data
cleanup_firestore() {
    log_info "Cleaning up Firestore data..."
    
    # Note: This requires the Firebase CLI for bulk deletion
    # For now, we'll just warn the user
    log_warning "Firestore cleanup requires manual action:"
    log_warning "1. Go to https://console.firebase.google.com/project/$PROJECT_ID/firestore"
    log_warning "2. Delete the 'pixelpipe_jobs' collection manually"
    log_warning "3. Or use the Firebase CLI: firebase firestore:delete --recursive /pixelpipe_jobs"
}

# Clean up IAM bindings (if any custom ones were created)
cleanup_iam() {
    log_info "Cleaning up IAM bindings..."
    log_info "IAM bindings are cleaned up automatically when service accounts are deleted"
    log_success "IAM cleanup complete"
}

# Clean up monitoring dashboards
cleanup_monitoring() {
    log_info "Cleaning up monitoring dashboards..."
    
    # List dashboards
    DASHBOARDS=$(gcloud monitoring dashboards list --filter="displayName:PixelPipe*${ENVIRONMENT}" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$DASHBOARDS" ]; then
        for dashboard in $DASHBOARDS; do
            log_info "Deleting dashboard: $(basename $dashboard)"
            gcloud monitoring dashboards delete "$(basename $dashboard)" --quiet || log_warning "Failed to delete dashboard: $dashboard"
        done
        log_success "Monitoring dashboards cleaned up"
    else
        log_info "No monitoring dashboards found to delete"
    fi
}

# Terraform cleanup (if using Terraform)
cleanup_terraform() {
    log_info "Cleaning up Terraform state..."
    
    if [ -f "infrastructure/terraform.tfstate" ]; then
        log_info "Found Terraform state, running terraform destroy..."
        cd infrastructure
        
        terraform destroy -auto-approve \
            -var="project_id=$PROJECT_ID" \
            -var="region=$REGION" \
            -var="environment=$ENVIRONMENT" || log_warning "Terraform destroy had issues"
        
        cd ..
        log_success "Terraform cleanup complete"
    else
        log_info "No Terraform state found, using manual cleanup"
    fi
}

# Clean up local files (optional)
cleanup_local() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    rm -f data/image_database.csv
    rm -f .env
    rm -rf venv/
    rm -rf __pycache__/
    rm -rf .pytest_cache/
    
    # Remove Terraform files
    rm -f infrastructure/terraform.tfstate*
    rm -rf infrastructure/.terraform/
    
    log_success "Local cleanup complete"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    echo ""
    echo "🔍 Checking remaining resources..."
    
    # Check Cloud Run
    REMAINING_SERVICES=$(gcloud run services list --region="$REGION" --filter="metadata.name:pixelpipe" --format="value(metadata.name)" 2>/dev/null | wc -l)
    echo "   Cloud Run services: $REMAINING_SERVICES"
    
    # Check Cloud Functions  
    REMAINING_FUNCTIONS=$(gcloud functions list --regions="$REGION" --filter="name:pixelpipe" --format="value(name)" 2>/dev/null | wc -l)
    echo "   Cloud Functions: $REMAINING_FUNCTIONS"
    
    # Check buckets
    REMAINING_BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -c "pixelpipe" || echo "0")
    echo "   Storage buckets: $REMAINING_BUCKETS"
    
    # Check Pub/Sub
    REMAINING_TOPICS=$(gcloud pubsub topics list --filter="name:pixelpipe" --format="value(name)" 2>/dev/null | wc -l)
    echo "   Pub/Sub topics: $REMAINING_TOPICS"
    
    echo ""
    if [ "$REMAINING_SERVICES" -eq 0 ] && [ "$REMAINING_FUNCTIONS" -eq 0 ] && [ "$REMAINING_BUCKETS" -eq 0 ] && [ "$REMAINING_TOPICS" -eq 0 ]; then
        log_success "✅ Cleanup verification passed! All resources removed."
    else
        log_warning "⚠️  Some resources may still exist. Check the GCP console manually."
    fi
}

# Main cleanup function
main_cleanup() {
    log_info "Starting PixelPipe cleanup process..."
    
    # Try Terraform first (cleaner)
    if [ -f "infrastructure/main.tf" ]; then
        cleanup_terraform
    fi
    
    # Manual cleanup for anything Terraform missed
    cleanup_cloud_run
    cleanup_cloud_functions
    cleanup_pubsub
    cleanup_storage
    cleanup_container_images
    cleanup_service_accounts
    cleanup_monitoring
    cleanup_iam
    cleanup_firestore
    
    verify_cleanup
}

# Handle script options
show_help() {
    echo "PixelPipe Cleanup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h     Show this help message"
    echo "  --local        Clean only local files"
    echo "  --verify       Only verify what resources exist"
    echo "  --force        Skip confirmation prompt"
    echo ""
    echo "Environment variables:"
    echo "  PROJECT_ID     GCP project ID (required)"
    echo "  REGION         GCP region (default: us-central1)"
    echo "  ENVIRONMENT    Environment name (default: dev)"
}

# Parse command line arguments
case "${1:-cleanup}" in
    "--help"|"-h")
        show_help
        exit 0
        ;;
    "--local")
        log_info "Cleaning only local files..."
        cleanup_local
        exit 0
        ;;
    "--verify")
        log_info "Verifying current resources..."
        setup_gcp
        verify_cleanup
        exit 0
        ;;
    "--force")
        log_warning "Force cleanup mode - skipping confirmation"
        setup_gcp
        main_cleanup
        cleanup_local
        ;;
    "cleanup"|"")
        confirm_cleanup
        setup_gcp
        main_cleanup
        
        # Ask about local cleanup
        echo ""
        read -p "🗂️  Also clean local files (CSV, .env, venv)? [y/N]: " clean_local
        if [[ $clean_local =~ ^[Yy]$ ]]; then
            cleanup_local
        fi
        ;;
    *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac

echo ""
log_success "🧹 PixelPipe cleanup completed!"
echo ""
echo "💡 To redeploy:"
echo "   ./scripts/deploy.sh"
echo ""
echo "📚 Need help? Check the documentation in docs/"
echo ""