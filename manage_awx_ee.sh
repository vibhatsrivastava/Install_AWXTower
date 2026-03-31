#!/bin/bash

################################################################################
# AWX Execution Environment Management Script
################################################################################
#
# This script automates the creation, registration, and deletion of
# Execution Environments (EEs) in AWX Tower.
#
# Features:
#   - Build custom EEs using ansible-builder
#   - Load EE images into K3s containerd
#   - Register/deregister EEs in AWX via REST API
#   - Batch processing from YAML definition files
#   - Comprehensive validation and error handling
#
# Prerequisites:
#   - AWX installed and running (via install_awx.sh)
#   - ansible-builder installed (pip3 install ansible-builder)
#     OR set ANSIBLE_BUILDER_VENV in awx.conf to point to a Python venv
#   - podman or docker installed
#   - kubectl with K3s access
#   - ctr (containerd CLI) available
#
# Usage:
#   ./manage_awx_ee.sh --build --ee-file examples/ee-minimal.yml --tag my-ee:latest
#   ./manage_awx_ee.sh --build-all --definitions ee-definitions.yaml
#   ./manage_awx_ee.sh --list
#   ./manage_awx_ee.sh --delete --name "My EE"
#
# Author: AWX Tower Installation Project
# License: MIT
# Version: 1.0.0
#
################################################################################

set -e
set -o pipefail

################################################################################
# Global Variables
################################################################################

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${EE_LOG_FILE:-/var/log/awx-ee-management.log}"
TEMP_DIR="/tmp/awx-ee-$$"

# Default values (can be overridden by awx.conf or CLI args)
AWX_API_ENDPOINT="${AWX_API_ENDPOINT:-http://localhost:30080}"
AWX_API_USER="${AWX_API_USER:-admin}"
AWX_API_PASSWORD="${AWX_API_PASSWORD}"
EE_DEFAULT_ORGANIZATION="${EE_DEFAULT_ORGANIZATION:-1}"
EE_CONTAINER_RUNTIME="${EE_CONTAINER_RUNTIME:-podman}"
K3S_CONTAINERD_NAMESPACE="${K3S_CONTAINERD_NAMESPACE:-k8s.io}"
EE_DEFINITIONS_FILE="${EE_DEFINITIONS_FILE:-ee-definitions.yaml}"
EE_CLEANUP_TARBALLS="${EE_CLEANUP_TARBALLS:-true}"
EE_PRUNE_SOURCE_IMAGES="${EE_PRUNE_SOURCE_IMAGES:-false}"
EE_BUILDER_VERBOSITY="${EE_BUILDER_VERBOSITY:-0}"
EE_BUILDER_NO_CACHE="${EE_BUILDER_NO_CACHE:-false}"
ANSIBLE_BUILDER_VENV="${ANSIBLE_BUILDER_VENV:-}"

# Internal variables for venv
ANSIBLE_BUILDER_CMD="ansible-builder"
VENV_ACTIVATED=false

# Operation flags
OPERATION=""
EE_FILE=""
IMAGE_TAG=""
EE_NAME=""
EE_DESCRIPTION=""
ORGANIZATION_ID=""
DEFINITIONS_FILE=""
VALIDATE_ONLY=false
SKIP_BUILD=false
SKIP_LOAD=false
SKIP_REGISTER=false
REMOVE_FROM_K3S=false
LIST_FORMAT="table"
VERBOSE=false

# Statistics
BUILD_SUCCESS=0
BUILD_FAILED=0
REGISTER_SUCCESS=0
REGISTER_FAILED=0

################################################################################
# Color Codes for Output
################################################################################

# Colors
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_MAGENTA='\033[0;35m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

# Symbols
SYMBOL_SUCCESS="✓"
SYMBOL_ERROR="✗"
SYMBOL_WARNING="⚠"
SYMBOL_INFO="ℹ"
SYMBOL_ARROW="→"

################################################################################
# Output Functions
################################################################################

print_header() {
    local message="$1"
    echo -e "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    echo -e "${COLOR_CYAN}  $message${COLOR_RESET}"
    echo -e "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    log_message "INFO" "$message"
}

print_success() {
    local message="$1"
    echo -e "${COLOR_GREEN}${SYMBOL_SUCCESS}${COLOR_RESET} $message"
    log_message "SUCCESS" "$message"
}

print_error() {
    local message="$1"
    echo -e "${COLOR_RED}${SYMBOL_ERROR}${COLOR_RESET} $message" >&2
    log_message "ERROR" "$message"
}

print_warning() {
    local message="$1"
    echo -e "${COLOR_YELLOW}${SYMBOL_WARNING}${COLOR_RESET} $message"
    log_message "WARNING" "$message"
}

print_info() {
    local message="$1"
    echo -e "${COLOR_BLUE}${SYMBOL_INFO}${COLOR_RESET} $message"
    log_message "INFO" "$message"
}

print_step() {
    local message="$1"
    echo -e "${COLOR_MAGENTA}${SYMBOL_ARROW}${COLOR_RESET} $message"
    log_message "STEP" "$message"
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

################################################################################
# Error Handling
################################################################################

cleanup_on_error() {
    local exit_code=$?
    print_error "Script failed with exit code: $exit_code"
    cleanup_temp_files
    exit "$exit_code"
}

cleanup_temp_files() {
    if [[ -d "$TEMP_DIR" ]]; then
        print_step "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup_on_error ERR
trap cleanup_temp_files EXIT

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

AWX Execution Environment Management Script

OPERATIONS:
  --build                 Build a single EE from execution-environment.yml
  --register              Register an existing image in AWX
  --delete                Delete an EE from AWX (and optionally from K3s)
  --list                  List all EEs registered in AWX
  --build-all             Build all enabled EEs from definitions file
  --validate-only         Validate configuration without building

BUILD OPTIONS:
  --ee-file FILE          Path to execution-environment.yml
  --tag TAG               Image tag (e.g., my-ee:latest)
  --no-cache              Disable build cache
  --skip-load             Skip loading to K3s
  --skip-register         Skip registering in AWX

REGISTER OPTIONS:
  --name NAME             EE name in AWX
  --image IMAGE           Image name/tag
  --description DESC      EE description
  --organization ID       Organization ID (default: 1)

DELETE OPTIONS:
  --name NAME             EE name to delete
  --remove-from-k3s       Also remove image from K3s containerd

LIST OPTIONS:
  --format FORMAT         Output format: table (default), json, yaml

BATCH OPTIONS:
  --definitions FILE      YAML file with EE definitions
                          (default: ee-definitions.yaml)

GLOBAL OPTIONS:
  --api-endpoint URL      AWX API endpoint (default: http://localhost:30080)
  --api-user USER         AWX API username (default: admin)
  --api-password PASS     AWX API password
  --runtime ENGINE        Container runtime: podman (default), docker
  --prune-images          Remove source images after K3s import
  -v, --verbose           Enable verbose output
  -h, --help              Display this help message

EXAMPLES:
  # Build and register a single EE
  $SCRIPT_NAME --build --ee-file examples/ee-minimal.yml --tag my-ee:latest

  # Build all EEs from definitions file
  $SCRIPT_NAME --build-all --definitions examples/ee-definitions-sample.yaml

  # List all registered EEs
  $SCRIPT_NAME --list

  # Register an existing image
  $SCRIPT_NAME --register --name "Custom EE" --image my-ee:latest

  # Delete an EE and remove from K3s
  $SCRIPT_NAME --delete --name "Custom EE" --remove-from-k3s

  # Validate definitions without building
  $SCRIPT_NAME --validate-only --definitions ee-definitions.yaml

CONFIGURATION:
  Source awx.conf for default settings:
    source awx.conf && sudo -E $SCRIPT_NAME --build-all

  Configuration variables:
    AWX_API_ENDPOINT        AWX API URL
    AWX_API_USER            API username
    AWX_API_PASSWORD        API password
    EE_DEFAULT_ORGANIZATION Default organization ID
    EE_CONTAINER_RUNTIME    podman or docker
    EE_DEFINITIONS_FILE     Path to definitions YAML

See EE_MANAGEMENT.md for comprehensive documentation.

EOF
}

################################################################################
# Prerequisite Checks
################################################################################

setup_ansible_builder_venv() {
    # If ANSIBLE_BUILDER_VENV is set, check if it exists and configure paths
    if [[ -n "$ANSIBLE_BUILDER_VENV" ]]; then
        if [[ ! -d "$ANSIBLE_BUILDER_VENV" ]]; then
            print_warning "Virtual environment not found: $ANSIBLE_BUILDER_VENV"
            return 1
        fi
        
        # Check if activate script exists
        if [[ ! -f "$ANSIBLE_BUILDER_VENV/bin/activate" ]]; then
            print_warning "Virtual environment activate script not found: $ANSIBLE_BUILDER_VENV/bin/activate"
            return 1
        fi
        
        # Check if ansible-builder exists in venv
        if [[ ! -f "$ANSIBLE_BUILDER_VENV/bin/ansible-builder" ]]; then
            print_warning "ansible-builder not found in virtual environment: $ANSIBLE_BUILDER_VENV"
            return 1
        fi
        
        # Set the ansible-builder command to use the venv version
        ANSIBLE_BUILDER_CMD="$ANSIBLE_BUILDER_VENV/bin/ansible-builder"
        VENV_ACTIVATED=true
        print_info "Using ansible-builder from virtual environment: $ANSIBLE_BUILDER_VENV"
        return 0
    fi
    
    return 1
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_deps=()
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Try to setup virtual environment first
    setup_ansible_builder_venv
    
    # Check ansible-builder
    print_step "Checking ansible-builder..."
    if [[ "$VENV_ACTIVATED" == "true" ]]; then
        # Check venv version
        if [[ -x "$ANSIBLE_BUILDER_CMD" ]]; then
            local ab_version=$($ANSIBLE_BUILDER_CMD --version 2>&1 | head -n1 || echo "unknown")
            print_success "ansible-builder found in venv: $ab_version"
        else
            print_error "ansible-builder not executable in venv"
            missing_deps+=("ansible-builder")
        fi
    elif command -v ansible-builder &> /dev/null; then
        # Found in system PATH
        local ab_version=$(ansible-builder --version 2>&1 | head -n1 || echo "unknown")
        print_success "ansible-builder found: $ab_version"
        ANSIBLE_BUILDER_CMD="ansible-builder"
    else
        # Not found anywhere
        print_error "ansible-builder not found"
        print_info "Install with: pip3 install ansible-builder"
        print_info "Or set ANSIBLE_BUILDER_VENV in awx.conf to point to your virtual environment"
        missing_deps+=("ansible-builder")
    fi
    
    # Check container runtime
    print_step "Checking container runtime ($EE_CONTAINER_RUNTIME)..."
    if ! command -v "$EE_CONTAINER_RUNTIME" &> /dev/null; then
        print_error "$EE_CONTAINER_RUNTIME not found"
        print_info "Install podman: dnf install podman  OR  apt install podman"
        print_info "Install docker: dnf install docker  OR  apt install docker.io"
        missing_deps+=("$EE_CONTAINER_RUNTIME")
    else
        local runtime_version=$("$EE_CONTAINER_RUNTIME" --version 2>&1 | head -n1 || echo "unknown")
        print_success "$EE_CONTAINER_RUNTIME found: $runtime_version"
    fi
    
    # Check kubectl
    print_step "Checking kubectl..."
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found"
        missing_deps+=("kubectl")
    else
        print_success "kubectl found"
    fi
    
    # Check K3s cluster
    print_step "Checking K3s cluster..."
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to K3s cluster"
        print_info "Ensure K3s is running: sudo systemctl status k3s"
        missing_deps+=("k3s-cluster")
    else
        print_success "K3s cluster is accessible"
    fi
    
    # Check ctr (containerd CLI)
    print_step "Checking ctr (containerd CLI)..."
    if ! command -v ctr &> /dev/null; then
        print_error "ctr command not found"
        print_info "ctr is required for importing images to K3s containerd"
        missing_deps+=("ctr")
    else
        print_success "ctr found"
    fi
    
    # Check AWX API accessibility
    print_step "Checking AWX API accessibility..."
    if ! curl -s -f -o /dev/null "$AWX_API_ENDPOINT/api/v2/ping/" 2>/dev/null; then
        print_warning "AWX API not accessible at $AWX_API_ENDPOINT"
        print_info "Ensure AWX is running: kubectl get pods -n awx"
        print_info "This is only required for registration operations"
    else
        print_success "AWX API is accessible"
    fi
    
    # Check jq for JSON parsing
    print_step "Checking jq..."
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found (recommended for JSON parsing)"
        print_info "Install with: apt install jq  OR  dnf install jq"
    else
        print_success "jq found"
    fi
    
    # Check Python for YAML parsing
    print_step "Checking Python..."
    if ! command -v python3 &> /dev/null; then
        print_error "python3 not found"
        missing_deps+=("python3")
    else
        print_success "python3 found"
    fi
    
    # Exit if critical dependencies are missing
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Install missing dependencies and try again"
        exit 1
    fi
    
    print_success "All prerequisites satisfied"
    echo ""
}

################################################################################
# AWX API Functions
################################################################################

awx_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local response_file="${4:-/tmp/awx-api-response-$$.json}"
    
    local url="${AWX_API_ENDPOINT}${endpoint}"
    local curl_opts=(-s -w "\n%{http_code}" -o "$response_file")
    
    # Add authentication
    curl_opts+=(--user "${AWX_API_USER}:${AWX_API_PASSWORD}")
    
    # Add method and headers
    curl_opts+=(-X "$method")
    curl_opts+=(-H "Content-Type: application/json")
    
    # Add data for POST/PUT/PATCH
    if [[ -n "$data" ]]; then
        curl_opts+=(-d "$data")
    fi
    
    # Make API call
    local http_code
    http_code=$(curl "${curl_opts[@]}" "$url" 2>/dev/null | tail -n1)
    
    # Check response
    if [[ "$http_code" =~ ^20[0-9]$ ]]; then
        return 0
    else
        print_error "API call failed: $method $endpoint (HTTP $http_code)"
        if [[ -f "$response_file" ]]; then
            cat "$response_file" >&2
        fi
        return 1
    fi
}

list_awx_ees() {
    print_header "Listing Execution Environments in AWX"
    
    local response_file="/tmp/awx-ee-list-$$.json"
    
    if ! awx_api_call "GET" "/api/v2/execution_environments/" "" "$response_file"; then
        print_error "Failed to retrieve EE list from AWX"
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        if [[ "$LIST_FORMAT" == "json" ]]; then
            jq '.' "$response_file"
        elif [[ "$LIST_FORMAT" == "yaml" ]]; then
            python3 -c "import json, yaml, sys; print(yaml.dump(json.load(sys.stdin)))" < "$response_file"
        else
            # Table format
            echo ""
            printf "%-5s %-30s %-40s %-10s\n" "ID" "NAME" "IMAGE" "ORG"
            printf "%-5s %-30s %-40s %-10s\n" "-----" "------------------------------" "----------------------------------------" "----------"
            jq -r '.results[] | [.id, .name, .image, .organization] | @tsv' "$response_file" | \
                while IFS=$'\t' read -r id name image org; do
                    printf "%-5s %-30s %-40s %-10s\n" "$id" "$name" "$image" "$org"
                done
            echo ""
            local count=$(jq -r '.count' "$response_file")
            print_info "Total: $count Execution Environment(s)"
        fi
    else
        cat "$response_file"
    fi
    
    rm -f "$response_file"
    return 0
}

register_ee_in_awx() {
    local name="$1"
    local image="$2"
    local description="$3"
    local organization="$4"
    
    print_step "Registering EE in AWX: $name"
    
    # Check if EE already exists
    local response_file="/tmp/awx-ee-check-$$.json"
    if awx_api_call "GET" "/api/v2/execution_environments/?name=$(printf %s "$name" | jq -sRr @uri)" "" "$response_file"; then
        if command -v jq &> /dev/null; then
            local count=$(jq -r '.count' "$response_file" 2>/dev/null || echo "0")
            if [[ "$count" -gt 0 ]]; then
                print_warning "EE '$name' already exists in AWX"
                local ee_id=$(jq -r '.results[0].id' "$response_file")
                print_info "Existing EE ID: $ee_id"
                rm -f "$response_file"
                return 0
            fi
        fi
    fi
    rm -f "$response_file"
    
    # Create JSON payload
    local payload
    payload=$(cat <<EOF
{
  "name": "$name",
  "image": "$image",
  "description": "$description",
  "organization": $organization
}
EOF
)
    
    # Register EE
    response_file="/tmp/awx-ee-register-$$.json"
    if awx_api_call "POST" "/api/v2/execution_environments/" "$payload" "$response_file"; then
        if command -v jq &> /dev/null; then
            local ee_id=$(jq -r '.id' "$response_file" 2>/dev/null || echo "unknown")
            print_success "EE registered successfully (ID: $ee_id)"
        else
            print_success "EE registered successfully"
        fi
        rm -f "$response_file"
        return 0
    else
        print_error "Failed to register EE in AWX"
        rm -f "$response_file"
        return 1
    fi
}

delete_ee_from_awx() {
    local name="$1"
    
    print_step "Deleting EE from AWX: $name"
    
    # Find EE ID by name
    local response_file="/tmp/awx-ee-find-$$.json"
    if ! awx_api_call "GET" "/api/v2/execution_environments/?name=$(printf %s "$name" | jq -sRr @uri)" "" "$response_file"; then
        print_error "Failed to query AWX for EE: $name"
        rm -f "$response_file"
        return 1
    fi
    
    local ee_id
    if command -v jq &> /dev/null; then
        local count=$(jq -r '.count' "$response_file" 2>/dev/null || echo "0")
        if [[ "$count" -eq 0 ]]; then
            print_error "EE '$name' not found in AWX"
            rm -f "$response_file"
            return 1
        fi
        ee_id=$(jq -r '.results[0].id' "$response_file")
    else
        print_error "jq is required for delete operations"
        rm -f "$response_file"
        return 1
    fi
    rm -f "$response_file"
    
    # Delete EE
    print_step "Deleting EE ID: $ee_id"
    if awx_api_call "DELETE" "/api/v2/execution_environments/$ee_id/" ""; then
        print_success "EE deleted from AWX successfully"
        return 0
    else
        print_error "Failed to delete EE from AWX"
        return 1
    fi
}

################################################################################
# Build Functions
################################################################################

validate_ee_file() {
    local ee_file="$1"
    
    print_step "Validating execution-environment.yml: $ee_file"
    
    # Check file exists
    if [[ ! -f "$ee_file" ]]; then
        print_error "File not found: $ee_file"
        return 1
    fi
    
    # Validate YAML syntax
    if ! python3 -c "import yaml, sys; yaml.safe_load(open('$ee_file'))" 2>/dev/null; then
        print_error "Invalid YAML syntax in $ee_file"
        return 1
    fi
    
    # Check for required version field
    if ! grep -q "^version:" "$ee_file"; then
        print_error "Missing required 'version' field in $ee_file"
        return 1
    fi
    
    # Check for base_image (required)
    if ! grep -q "base_image:" "$ee_file"; then
        print_error "Missing required 'base_image' in $ee_file"
        return 1
    fi
    
    # Warn if base image is not RPM-based
    if grep "base_image" "$ee_file" | grep -qiE "(debian|ubuntu|alpine)"; then
        print_warning "Base image appears to be Debian/Ubuntu/Alpine"
        print_warning "ansible-builder requires RPM-based images (CentOS, Rocky, Fedora, UBI)"
    fi
    
    # Check for image tag
    if grep "base_image" "$ee_file" | grep -qvE ":[a-zA-Z0-9._-]+"; then
        print_warning "Base image missing tag (e.g., :stream9)"
        print_warning "Builds may fail without explicit version tags"
    fi
    
    print_success "Validation passed: $ee_file"
    return 0
}

build_ee_image() {
    local ee_file="$1"
    local image_tag="$2"
    
    print_header "Building Execution Environment"
    print_info "Source: $ee_file"
    print_info "Tag: $image_tag"
    
    # Validate EE file
    if ! validate_ee_file "$ee_file"; then
        return 1
    fi
    
    # Prepare build command
    local build_cmd="$ANSIBLE_BUILDER_CMD build"
    build_cmd+=" --file $ee_file"
    build_cmd+=" --tag $image_tag"
    build_cmd+=" --container-runtime $EE_CONTAINER_RUNTIME"
    
    # Add verbosity
    if [[ "$EE_BUILDER_VERBOSITY" -gt 0 ]]; then
        local v_flags=$(printf 'v%.0s' $(seq 1 "$EE_BUILDER_VERBOSITY"))
        build_cmd+=" -$v_flags"
    fi
    
    # Add no-cache option
    if [[ "$EE_BUILDER_NO_CACHE" == "true" ]]; then
        build_cmd+=" --no-cache"
    fi
    
    print_step "Running: $build_cmd"
    
    # Execute build
    local build_log="/tmp/awx-ee-build-$$.log"
    if [[ "$VERBOSE" == "true" ]]; then
        $build_cmd 2>&1 | tee "$build_log"
        local build_result=${PIPESTATUS[0]}
    else
        $build_cmd > "$build_log" 2>&1
        local build_result=$?
    fi
    
    if [[ $build_result -eq 0 ]]; then
        print_success "Build completed successfully"
        rm -f "$build_log"
        
        # Verify image exists
        if $EE_CONTAINER_RUNTIME images "$image_tag" --format "{{.Repository}}:{{.Tag}}" | grep -q "$image_tag"; then
            print_success "Image verified: $image_tag"
            return 0
        else
            print_error "Image build reported success but image not found"
            return 1
        fi
    else
        print_error "Build failed with exit code: $build_result"
        if [[ -f "$build_log" ]]; then
            print_error "Last 30 lines of build output:"
            tail -30 "$build_log" >&2
            rm -f "$build_log"
        fi
        return 1
    fi
}

################################################################################
# K3s Functions
################################################################################

load_image_to_k3s() {
    local image_tag="$1"
    
    print_header "Loading Image to K3s Containerd"
    print_info "Image: $image_tag"
    
    local tarball="$TEMP_DIR/$(echo "$image_tag" | tr '/:' '_').tar"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Export image
    print_step "Exporting image with $EE_CONTAINER_RUNTIME..."
    if ! $EE_CONTAINER_RUNTIME save "$image_tag" -o "$tarball"; then
        print_error "Failed to export image"
        return 1
    fi
    print_success "Image exported to $tarball"
    
    # Import to K3s containerd
    print_step "Importing to K3s containerd namespace: $K3S_CONTAINERD_NAMESPACE..."
    if ! ctr -n "$K3S_CONTAINERD_NAMESPACE" images import "$tarball"; then
        print_error "Failed to import image to K3s"
        return 1
    fi
    print_success "Image imported to K3s"
    
    # Verify import
    print_step "Verifying image in K3s..."
    if ctr -n "$K3S_CONTAINERD_NAMESPACE" images ls | grep -q "$image_tag"; then
        print_success "Image verified in K3s containerd"
    else
        print_warning "Image not found in K3s (import may have failed silently)"
    fi
    
    # Cleanup tarball
    if [[ "$EE_CLEANUP_TARBALLS" == "true" ]]; then
        print_step "Removing temporary tarball..."
        rm -f "$tarball"
    fi
    
    # Optionally prune source image
    if [[ "$EE_PRUNE_SOURCE_IMAGES" == "true" ]]; then
        print_step "Pruning source image from $EE_CONTAINER_RUNTIME..."
        $EE_CONTAINER_RUNTIME rmi "$image_tag" || true
    fi
    
    print_success "Image loaded to K3s successfully"
    return 0
}

remove_image_from_k3s() {
    local image_tag="$1"
    
    print_step "Removing image from K3s: $image_tag"
    
    if ctr -n "$K3S_CONTAINERD_NAMESPACE" images rm "$image_tag" 2>/dev/null; then
        print_success "Image removed from K3s"
        return 0
    else
        print_warning "Failed to remove image from K3s (may not exist)"
        return 1
    fi
}

################################################################################
# Batch Processing Functions
################################################################################

parse_yaml_definitions() {
    local definitions_file="$1"
    
    print_header "Parsing EE Definitions"
    print_info "File: $definitions_file"
    
    if [[ ! -f "$definitions_file" ]]; then
        print_error "Definitions file not found: $definitions_file"
        return 1
    fi
    
    # Validate YAML syntax
    if ! python3 -c "import yaml; yaml.safe_load(open('$definitions_file'))" 2>/dev/null; then
        print_error "Invalid YAML syntax in $definitions_file"
        return 1
    fi
    
    print_success "Definitions file validated"
    return 0
}

process_ee_definitions() {
    local definitions_file="$1"
    
    print_header "Processing EE Definitions"
    
    if ! parse_yaml_definitions "$definitions_file"; then
        return 1
    fi
    
    # Use Python to parse YAML and process each EE
    python3 - "$definitions_file" "$SCRIPT_DIR/$SCRIPT_NAME" <<'PYTHON_SCRIPT'
import yaml
import sys
import subprocess

def run_command(cmd):
    """Execute shell command"""
    result = subprocess.run(cmd, shell=True, capture_output=False)
    return result.returncode == 0

def process_ee(ee_def, defaults, script_path):
    """Process a single EE definition"""
    name = ee_def.get('name', 'Unnamed EE')
    enabled = ee_def.get('enabled', True)
    
    if not enabled:
        print(f"\n⊘ Skipping disabled EE: {name}")
        return True
    
    print(f"\n━━━ Processing: {name} ━━━")
    
    ee_file = ee_def.get('ee_file')
    image_tag = ee_def.get('image_tag')
    description = ee_def.get('description', '')
    organization = ee_def.get('organization', defaults.get('organization', 1))
    
    # Validate required fields
    if not ee_file or not image_tag:
        print(f"✗ Missing required fields (ee_file or image_tag) for: {name}")
        return False
    
    # Build command
    build_cmd = f"bash -c 'source {script_path} && build_ee_image \"{ee_file}\" \"{image_tag}\"'"
    load_cmd = f"bash -c 'source {script_path} && load_image_to_k3s \"{image_tag}\"'"
    register_cmd = f"bash -c 'source {script_path} && register_ee_in_awx \"{name}\" \"{image_tag}\" \"{description}\" \"{organization}\"'"
    
    success = True
    
    # Build
    print(f"→ Building: {ee_file}")
    if not run_command(build_cmd):
        print(f"✗ Build failed for: {name}")
        return False
    
    # Load to K3s
    if defaults.get('load_to_k3s', True):
        print(f"→ Loading to K3s: {image_tag}")
        if not run_command(load_cmd):
            print(f"✗ Load failed for: {name}")
            return False
    
    # Register in AWX
    if defaults.get('register_in_awx', True):
        print(f"→ Registering in AWX: {name}")
        if not run_command(register_cmd):
            print(f"⚠ Registration failed for: {name}")
            # Don't fail entire process if just registration fails
    
    print(f"✓ Completed: {name}")
    return True

# Main processing
try:
    with open(sys.argv[1], 'r') as f:
        data = yaml.safe_load(f)
    
    script_path = sys.argv[2]
    defaults = data.get('defaults', {})
    ee_list = data.get('execution_environments', [])
    
    if not ee_list:
        print("⚠ No execution environments defined")
        sys.exit(0)
    
    success_count = 0
    failed_count = 0
    
    for ee_def in ee_list:
        if process_ee(ee_def, defaults, script_path):
            success_count += 1
        else:
            failed_count += 1
    
    print(f"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"Summary: {success_count} succeeded, {failed_count} failed")
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    
    sys.exit(0 if failed_count == 0 else 1)

except Exception as e:
    print(f"✗ Error processing definitions: {e}")
    sys.exit(1)
PYTHON_SCRIPT

    local result=$?
    
    if [[ $result -eq 0 ]]; then
        print_success "Batch processing completed successfully"
        return 0
    else
        print_error "Batch processing completed with errors"
        return 1
    fi
}

################################################################################
# Main Execution
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build)
                OPERATION="build"
                shift
                ;;
            --register)
                OPERATION="register"
                shift
                ;;
            --delete)
                OPERATION="delete"
                shift
                ;;
            --list)
                OPERATION="list"
                shift
                ;;
            --build-all)
                OPERATION="build-all"
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --ee-file)
                EE_FILE="$2"
                shift 2
                ;;
            --tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --name)
                EE_NAME="$2"
                shift 2
                ;;
            --image)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --description)
                EE_DESCRIPTION="$2"
                shift 2
                ;;
            --organization)
                ORGANIZATION_ID="$2"
                shift 2
                ;;
            --definitions)
                DEFINITIONS_FILE="$2"
                shift 2
                ;;
            --no-cache)
                EE_BUILDER_NO_CACHE="true"
                shift
                ;;
            --skip-load)
                SKIP_LOAD=true
                shift
                ;;
            --skip-register)
                SKIP_REGISTER=true
                shift
                ;;
            --remove-from-k3s)
                REMOVE_FROM_K3S=true
                shift
                ;;
            --format)
                LIST_FORMAT="$2"
                shift 2
                ;;
            --api-endpoint)
                AWX_API_ENDPOINT="$2"
                shift 2
                ;;
            --api-user)
                AWX_API_USER="$2"
                shift 2
                ;;
            --api-password)
                AWX_API_PASSWORD="$2"
                shift 2
                ;;
            --runtime)
                EE_CONTAINER_RUNTIME="$2"
                shift 2
                ;;
            --prune-images)
                EE_PRUNE_SOURCE_IMAGES="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    print_header "AWX Execution Environment Management"
    print_info "Version: 1.0.0"
    print_info "Log file: $LOG_FILE"
    echo ""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check if operation specified
    if [[ -z "$OPERATION" ]]; then
        print_error "No operation specified"
        show_usage
        exit 1
    fi
    
    # Run prerequisite checks
    check_prerequisites
    
    # Execute operation
    case "$OPERATION" in
        build)
            if [[ -z "$EE_FILE" ]] || [[ -z "$IMAGE_TAG" ]]; then
                print_error "--build requires --ee-file and --tag"
                exit 1
            fi
            
            if ! build_ee_image "$EE_FILE" "$IMAGE_TAG"; then
                exit 1
            fi
            
            if [[ "$SKIP_LOAD" == "false" ]]; then
                if ! load_image_to_k3s "$IMAGE_TAG"; then
                    exit 1
                fi
            fi
            
            if [[ "$SKIP_REGISTER" == "false" ]]; then
                local ee_name="${EE_NAME:-$(basename "$EE_FILE" .yml)}"
                local ee_desc="${EE_DESCRIPTION:-Built from $EE_FILE}"
                local org_id="${ORGANIZATION_ID:-$EE_DEFAULT_ORGANIZATION}"
                
                if ! register_ee_in_awx "$ee_name" "$IMAGE_TAG" "$ee_desc" "$org_id"; then
                    print_warning "Build and load succeeded, but registration failed"
                    exit 1
                fi
            fi
            
            print_success "All operations completed successfully"
            ;;
        
        register)
            if [[ -z "$EE_NAME" ]] || [[ -z "$IMAGE_TAG" ]]; then
                print_error "--register requires --name and --image"
                exit 1
            fi
            
            local ee_desc="${EE_DESCRIPTION:-Execution Environment}"
            local org_id="${ORGANIZATION_ID:-$EE_DEFAULT_ORGANIZATION}"
            
            if ! register_ee_in_awx "$EE_NAME" "$IMAGE_TAG" "$ee_desc" "$org_id"; then
                exit 1
            fi
            ;;
        
        delete)
            if [[ -z "$EE_NAME" ]]; then
                print_error "--delete requires --name"
                exit 1
            fi
            
            if ! delete_ee_from_awx "$EE_NAME"; then
                exit 1
            fi
            
            if [[ "$REMOVE_FROM_K3S" == "true" ]]; then
                if [[ -n "$IMAGE_TAG" ]]; then
                    remove_image_from_k3s "$IMAGE_TAG"
                else
                    print_warning "No --image specified, skipping K3s removal"
                fi
            fi
            ;;
        
        list)
            if ! list_awx_ees; then
                exit 1
            fi
            ;;
        
        build-all)
            local def_file="${DEFINITIONS_FILE:-$EE_DEFINITIONS_FILE}"
            
            if [[ "$VALIDATE_ONLY" == "true" ]]; then
                if parse_yaml_definitions "$def_file"; then
                    print_success "Validation passed"
                    exit 0
                else
                    exit 1
                fi
            fi
            
            if ! process_ee_definitions "$def_file"; then
                exit 1
            fi
            ;;
        
        *)
            print_error "Unknown operation: $OPERATION"
            exit 1
            ;;
    esac
    
    print_success "Operation completed successfully"
}

# Run main function only if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
