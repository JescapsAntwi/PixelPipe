#!/bin/bash
# PixelPipe Local Development Setup Script
# Sets up your local development environment

set -e  # Exit on any error

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

echo "🏠 PixelPipe Local Development Setup"
echo "===================================="

# Check if we're in the right directory
check_project_root() {
    if [ ! -f "README.md" ] || [ ! -d "infrastructure" ]; then
        log_error "Please run this script from the PixelPipe project root directory"
        exit 1
    fi
    log_success "Project root directory confirmed"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.8+ first."
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)
    log_info "Found Python $PYTHON_VERSION"
    
    # Check pip
    if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
        log_error "pip is not installed. Please install pip first."
        exit 1
    fi
    
    # Check git
    if ! command -v git &> /dev/null; then
        log_warning "Git is not installed. You may want to install it for version control."
    fi
    
    # Check gcloud (optional for local dev)
    if ! command -v gcloud &> /dev/null; then
        log_warning "gcloud CLI not found. Install it later for deployment."
    else
        log_success "gcloud CLI found"
    fi
    
    log_success "Prerequisites check completed"
}

# Create virtual environment
setup_virtual_environment() {
    log_info "Setting up Python virtual environment..."
    
    if [ -d "venv" ]; then
        log_warning "Virtual environment already exists. Removing old one..."
        rm -rf venv
    fi
    
    # Create new virtual environment
    python3 -m venv venv
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    log_success "Virtual environment created and activated"
}

# Install dependencies
install_dependencies() {
    log_info "Installing Python dependencies..."
    
    # Make sure we're in the virtual environment
    if [ -z "$VIRTUAL_ENV" ]; then
        source venv/bin/activate
    fi
    
    # Install main requirements
    pip install -r requirements.txt
    
    # Install function requirements
    if [ -f "functions/requirements.txt" ]; then
        pip install -r functions/requirements.txt
    fi
    
    # Install service requirements  
    if [ -f "services/requirements.txt" ]; then
        pip install -r services/requirements.txt
    fi
    
    log_success "Dependencies installed"
}

# Set up environment file
setup_environment_file() {
    log_info "Setting up environment configuration..."
    
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            log_success "Created .env file from template"
            log_warning "Please edit .env file with your GCP project details!"
        else
            log_warning "No .env.example found. Creating basic .env file..."
            cat > .env << 'EOF'
# GCP Configuration
PROJECT_ID=your-gcp-project-id
REGION=us-central1
ENVIRONMENT=dev

# Local Development
LOCAL_PORT=8080
DEBUG=true
EOF
            log_warning "Please edit .env file with your actual GCP project ID!"
        fi
    else
        log_info ".env file already exists"
    fi
}

# Create local directories
setup_local_directories() {
    log_info "Setting up local directories..."
    
    # Create directories for local development
    mkdir -p logs
    mkdir -p temp
    mkdir -p local_data
    
    # Add to .gitignore if not already there
    if [ -f ".gitignore" ]; then
        echo "" >> .gitignore  
        echo "# Local development" >> .gitignore
        echo "logs/" >> .gitignore
        echo "temp/" >> .gitignore
        echo "local_data/" >> .gitignore
    fi
    
    log_success "Local directories created"
}

# Generate sample data
generate_sample_data() {
    log_info "Generating sample data..."
    
    if [ -f "data/generate_csv.py" ]; then
        source venv/bin/activate
        cd data
        python generate_csv.py
        cd ..
        log_success "Sample CSV generated in data/image_database.csv"
    else
        log_warning "CSV generator not found. You'll need to create sample data manually."
    fi
}

# Test local setup
test_local_setup() {
    log_info "Testing local setup..."
    
    # Test Python imports
    source venv/bin/activate
    
    python3 -c "
import sys
print(f'Python version: {sys.version}')

try:
    import PIL
    print('✅ Pillow (image processing) - OK')
except ImportError:
    print('❌ Pillow - MISSING')

try:
    from google.cloud import storage
    print('✅ Google Cloud Storage - OK')
except ImportError:
    print('❌ Google Cloud Storage - MISSING')

try:
    import flask
    print('✅ Flask (web framework) - OK') 
except ImportError:
    print('❌ Flask - MISSING')

try:
    import pandas
    print('✅ Pandas (data processing) - OK')
except ImportError:
    print('❌ Pandas - MISSING')
"
    
    log_success "Local setup test completed"
}

# Create development scripts
create_dev_scripts() {
    log_info "Creating development helper scripts..."
    
    # Create activation script
    cat > activate_env.sh << 'EOF'
#!/bin/bash
# Activate PixelPipe development environment
echo "🚀 Activating PixelPipe development environment..."
source venv/bin/activate
source .env
echo "✅ Environment activated!"
echo "📍 Project: $PROJECT_ID"
echo "🌍 Region: $REGION"
echo ""
echo "💡 Available commands:"
echo "  python data/generate_csv.py    # Generate sample data"
echo "  python services/main.py         # Run image processor locally"
echo "  python tests/test_*.py          # Run tests"
echo ""
EOF
    chmod +x activate_env.sh
    
    # Create test runner
    cat > run_tests.sh << 'EOF'
#!/bin/bash
# Run PixelPipe tests
source venv/bin/activate
source .env

echo "🧪 Running PixelPipe tests..."
python -m pytest tests/ -v
EOF
    chmod +x run_tests.sh
    
    # Create local server runner
    cat > run_local.sh << 'EOF'
#!/bin/bash
# Run PixelPipe services locally
source venv/bin/activate
source .env

echo "🏃 Starting local development server..."
echo "📍 Image processor will run on http://localhost:${LOCAL_PORT:-8080}"

cd services
python main.py
EOF
    chmod +x run_local.sh
    
    log_success "Development scripts created"
}

# Show completion message
show_completion_message() {
    echo ""
    log_success "🎉 Local development setup completed!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 SETUP SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "✅ Virtual environment created in ./venv/"
    echo "✅ Dependencies installed"
    echo "✅ Environment file created (.env)"
    echo "✅ Local directories set up"
    echo "✅ Sample data generated"
    echo "✅ Development scripts created"
    echo ""
    echo "🚀 NEXT STEPS:"
    echo ""
    echo "1. Edit your .env file:"
    echo "   nano .env  # Add your GCP PROJECT_ID"
    echo ""
    echo "2. Activate development environment:"
    echo "   source activate_env.sh"
    echo ""
    echo "3. Test image processing locally:"
    echo "   ./run_local.sh"
    echo ""
    echo "4. Run tests:"
    echo "   ./run_tests.sh"
    echo ""
    echo "5. Deploy to GCP when ready:"
    echo "   ./scripts/deploy.sh"
    echo ""
    echo "📚 USEFUL FILES:"
    echo "   • ./activate_env.sh     - Activate dev environment"
    echo "   • ./run_local.sh        - Run services locally"  
    echo "   • ./run_tests.sh        - Run test suite"
    echo "   • data/image_database.csv - Sample data"
    echo "   • .env                  - Environment config"
    echo ""
    echo "💡 Need help? Check docs/ folder or run:"
    echo "   python services/main.py --help"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution
main() {
    check_project_root
    check_prerequisites
    setup_virtual_environment
    install_dependencies
    setup_environment_file
    setup_local_directories
    generate_sample_data
    create_dev_scripts
    test_local_setup
    show_completion_message
}

# Handle command line arguments
case "${1:-setup}" in
    "setup"|"")
        main
        ;;
    "--test")
        log_info "Testing current setup..."
        source venv/bin/activate 2>/dev/null || log_error "Virtual environment not found. Run setup first."
        test_local_setup
        ;;
    "--clean")
        log_info "Cleaning local setup..."
        rm -rf venv/
        rm -f .env
        rm -rf logs/ temp/ local_data/
        rm -f activate_env.sh run_tests.sh run_local.sh
        log_success "Local setup cleaned"
        ;;
    "--help"|"-h")
        echo "PixelPipe Local Setup Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  setup, (default)  Set up local development environment"
        echo "  --test           Test current setup"
        echo "  --clean          Clean local setup files"
        echo "  --help, -h       Show this help"
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for available options"
        exit 1
        ;;
esac