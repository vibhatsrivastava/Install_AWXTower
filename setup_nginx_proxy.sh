#!/bin/bash

################################################################################
# Nginx Reverse Proxy Setup for AWX Tower
################################################################################
# Description: Automated setup of Nginx reverse proxy to access AWX Tower
#              without specifying port numbers (HTTP/HTTPS)
# Version: 1.0.0
# Date: February 19, 2026
# Requirements: Ubuntu 24.04 LTS, AWX already installed, root/sudo privileges
################################################################################

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure

################################################################################
# Configuration Variables
################################################################################

AWX_NAMESPACE="${AWX_NAMESPACE:-awx}"
AWX_INSTANCE_NAME="${AWX_INSTANCE_NAME:-awx}"
AWX_NODEPORT="${AWX_NODEPORT:-30080}"
DOMAIN_NAME="${DOMAIN_NAME:-}"  # Leave empty for IP-only access
ENABLE_SSL="${ENABLE_SSL:-false}"
EMAIL_ADDRESS="${EMAIL_ADDRESS:-}"  # Required for Let's Encrypt SSL
LOG_FILE="/var/log/nginx-awx-proxy.log"
UNINSTALL_MODE=false

################################################################################
# Color Codes for Output
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'  # No Color

################################################################################
# Output Functions
################################################################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
    log "HEADER: $1"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}✗ Error: $1${NC}" >&2
    log "ERROR: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ Warning: $1${NC}"
    log "WARNING: $1"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
    log "INFO: $1"
}

print_step() {
    echo -e "${MAGENTA}➜ $1${NC}"
    log "STEP: $1"
}

################################################################################
# Usage Information
################################################################################

usage() {
    cat <<EOF
${CYAN}Nginx Reverse Proxy Setup for AWX Tower${NC}

Usage: $0 [OPTIONS]

Options:
    -h, --help                  Display this help message
    --domain DOMAIN             Domain name for AWX (optional, for SSL)
    --email EMAIL               Email for Let's Encrypt SSL certificates
    --enable-ssl                Enable HTTPS with Let's Encrypt
    --awx-port PORT             AWX NodePort (default: ${AWX_NODEPORT})
    --uninstall                 Remove Nginx reverse proxy configuration
    -v, --verbose               Enable verbose output

Examples:
    # Basic HTTP reverse proxy (access via http://SERVER_IP)
    sudo $0

    # With custom AWX port
    sudo $0 --awx-port 30080

    # Enable HTTPS with domain name
    sudo $0 --domain awx.example.com --email admin@example.com --enable-ssl

    # Uninstall reverse proxy
    sudo $0 --uninstall

Requirements:
    - Ubuntu 24.04 LTS (64-bit)
    - Root or sudo privileges
    - AWX Tower already installed and running
    - Domain name (optional, required for SSL)

After Installation:
    - Access AWX at: http://YOUR_SERVER_IP (or https://YOUR_DOMAIN if SSL enabled)
    - No port number needed in the URL!

EOF
    exit 0
}

################################################################################
# Cleanup Function
################################################################################

cleanup_on_error() {
    print_error "Setup failed. Check logs at $LOG_FILE"
    exit 1
}

trap cleanup_on_error ERR

################################################################################
# Prerequisites Check
################################################################################

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
    print_success "Running as root"

    # Check Ubuntu version
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect OS version"
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This script is designed for Ubuntu. Detected: $ID"
        exit 1
    fi
    print_success "Operating system: Ubuntu $VERSION_ID"

    # Check if AWX is accessible
    print_step "Checking if AWX is accessible on port ${AWX_NODEPORT}..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${AWX_NODEPORT}" | grep -q "200\|301\|302"; then
        print_success "AWX is accessible on port ${AWX_NODEPORT}"
    else
        print_warning "Cannot verify AWX accessibility on port ${AWX_NODEPORT}"
        print_info "Make sure AWX is running before continuing"
        read -p "Continue anyway? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Setup cancelled"
            exit 0
        fi
    fi

    # Check if port 80 is available
    if netstat -tuln 2>/dev/null | grep -q ":80 " || ss -tuln 2>/dev/null | grep -q ":80 "; then
        print_warning "Port 80 is already in use"
        print_info "Existing service will be replaced with Nginx configuration"
    fi

    # If SSL is enabled, verify requirements
    if [[ "$ENABLE_SSL" == "true" ]]; then
        if [[ -z "$DOMAIN_NAME" ]]; then
            print_error "Domain name is required for SSL (--domain option)"
            exit 1
        fi
        if [[ -z "$EMAIL_ADDRESS" ]]; then
            print_error "Email address is required for SSL (--email option)"
            exit 1
        fi
        print_success "SSL requirements verified"
    fi

    print_success "All prerequisites met"
}

################################################################################
# Install Nginx
################################################################################

install_nginx() {
    print_header "Installing Nginx"

    if command -v nginx &> /dev/null; then
        print_warning "Nginx is already installed"
        NGINX_VERSION=$(nginx -v 2>&1 | awk -F'/' '{print $2}')
        print_info "Existing version: nginx/${NGINX_VERSION}"
        print_info "Continuing with existing installation..."
        return 0
    fi

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    # Enable Nginx service
    print_step "Enabling Nginx service..."
    systemctl enable nginx > /dev/null 2>&1
    print_success "Nginx service enabled"

    # Verify installation
    if systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    else
        print_step "Starting Nginx service..."
        systemctl start nginx
        print_success "Nginx started"
    fi

    NGINX_VERSION=$(nginx -v 2>&1 | awk -F'/' '{print $2}')
    print_info "Installed version: nginx/${NGINX_VERSION}"
}

################################################################################
# Configure Nginx Reverse Proxy
################################################################################

configure_nginx_proxy() {
    print_header "Configuring Nginx Reverse Proxy"

    # Backup existing configuration if it exists
    if [[ -f /etc/nginx/sites-available/awx ]]; then
        print_step "Backing up existing configuration..."
        cp /etc/nginx/sites-available/awx "/etc/nginx/sites-available/awx.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Existing configuration backed up"
    fi

    # Determine server_name
    if [[ -n "$DOMAIN_NAME" ]]; then
        SERVER_NAME="$DOMAIN_NAME"
    else
        SERVER_NAME="_"  # Accept all hostnames
    fi

    print_step "Creating Nginx configuration for AWX..."
    cat > /etc/nginx/sites-available/awx <<EOF
# Nginx Reverse Proxy Configuration for AWX Tower
# Generated: $(date)
# Proxies requests from port 80 to AWX NodePort ${AWX_NODEPORT}

server {
    listen 80;
    server_name ${SERVER_NAME};
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Increase buffer sizes for AWX
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
    
    # Increase body size limit for file uploads
    client_max_body_size 100M;
    
    # Main location - proxy to AWX
    location / {
        proxy_pass http://localhost:${AWX_NODEPORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support (for AWX live updates and job output)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Increase timeouts for long-running jobs
        proxy_connect_timeout 600s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;
        
        # Disable buffering for real-time job output
        proxy_buffering off;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

    print_success "Nginx configuration created"

    # Enable the site
    print_step "Enabling AWX site configuration..."
    ln -sf /etc/nginx/sites-available/awx /etc/nginx/sites-enabled/awx
    print_success "AWX site enabled"

    # Remove default site if it exists
    if [[ -f /etc/nginx/sites-enabled/default ]]; then
        print_step "Removing default Nginx site..."
        rm -f /etc/nginx/sites-enabled/default
        print_success "Default site removed"
    fi

    # Test Nginx configuration
    print_step "Testing Nginx configuration..."
    if nginx -t 2>&1 | grep -q "successful"; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi

    # Reload Nginx
    print_step "Reloading Nginx..."
    systemctl reload nginx
    print_success "Nginx reloaded"
}

################################################################################
# Configure Firewall
################################################################################

configure_firewall() {
    print_header "Configuring Firewall"

    if ! command -v ufw &> /dev/null; then
        print_warning "UFW not found, skipping firewall configuration"
        return 0
    fi

    # Allow HTTP
    print_step "Opening HTTP port (80)..."
    ufw allow 80/tcp comment 'Nginx HTTP for AWX' > /dev/null
    print_success "HTTP port opened"

    # Allow HTTPS if SSL is enabled
    if [[ "$ENABLE_SSL" == "true" ]]; then
        print_step "Opening HTTPS port (443)..."
        ufw allow 443/tcp comment 'Nginx HTTPS for AWX' > /dev/null
        print_success "HTTPS port opened"
    fi

    print_success "Firewall configured"
}

################################################################################
# Setup SSL with Let's Encrypt
################################################################################

setup_ssl() {
    print_header "Setting Up SSL with Let's Encrypt"

    # Install Certbot
    print_step "Installing Certbot..."
    if ! command -v certbot &> /dev/null; then
        apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
        print_success "Certbot installed"
    else
        print_info "Certbot already installed"
    fi

    # Obtain SSL certificate
    print_step "Obtaining SSL certificate for ${DOMAIN_NAME}..."
    print_info "This will communicate with Let's Encrypt servers"
    
    if certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL_ADDRESS" \
        --domain "$DOMAIN_NAME" \
        --redirect; then
        print_success "SSL certificate obtained and configured"
    else
        print_error "Failed to obtain SSL certificate"
        print_info "Make sure your domain points to this server's IP address"
        print_info "You can try again later with: certbot --nginx -d $DOMAIN_NAME"
        exit 1
    fi

    # Test auto-renewal
    print_step "Testing certificate auto-renewal..."
    if certbot renew --dry-run > /dev/null 2>&1; then
        print_success "Certificate auto-renewal is configured"
    else
        print_warning "Auto-renewal test failed, but certificate is installed"
    fi

    print_success "SSL setup completed"
}

################################################################################
# Display Access Information
################################################################################

display_access_info() {
    print_header "Reverse Proxy Setup Complete!"

    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')

    # Determine access URL
    if [[ "$ENABLE_SSL" == "true" ]]; then
        ACCESS_URL="https://${DOMAIN_NAME}"
        PROTOCOL="HTTPS"
    elif [[ -n "$DOMAIN_NAME" ]]; then
        ACCESS_URL="http://${DOMAIN_NAME}"
        PROTOCOL="HTTP"
    else
        ACCESS_URL="http://${SERVER_IP}"
        PROTOCOL="HTTP"
    fi

    # Save access info to file
    INFO_FILE="/root/awx-proxy-info.txt"
    cat > "$INFO_FILE" <<EOF
AWX Tower Reverse Proxy Information
========================================
Generated: $(date)

Access URL:
  ${ACCESS_URL}
  
Alternative access (by IP):
  http://${SERVER_IP}

Configuration:
  - Nginx reverse proxy: Active
  - Protocol: ${PROTOCOL}
  - AWX Backend Port: ${AWX_NODEPORT}
  - Domain: ${DOMAIN_NAME:-None (IP-based access)}

Nginx Commands:
  # Check status
  systemctl status nginx
  
  # Reload configuration
  systemctl reload nginx
  
  # View access logs
  tail -f /var/log/nginx/access.log
  
  # View error logs
  tail -f /var/log/nginx/error.log
  
  # Test configuration
  nginx -t

SSL Certificate (if enabled):
  # Renew certificate manually
  certbot renew
  
  # Check certificate status
  certbot certificates

Configuration Files:
  - Nginx config: /etc/nginx/sites-available/awx
  - Setup log: ${LOG_FILE}

========================================
EOF

    chmod 600 "$INFO_FILE"

    # Display access information
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       Nginx Reverse Proxy Successfully Configured!        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"

    echo -e "${CYAN}Access AWX Tower at:${NC}"
    echo -e "  ${YELLOW}${ACCESS_URL}${NC}\n"

    if [[ -z "$DOMAIN_NAME" ]]; then
        echo -e "${BLUE}ℹ ${NC} ${BLUE}No port number needed! Access directly via your server IP.${NC}\n"
    fi

    if [[ "$ENABLE_SSL" == "true" ]]; then
        echo -e "${GREEN}✓${NC} ${GREEN}HTTPS is enabled with automatic certificate renewal${NC}\n"
    fi

    echo -e "${CYAN}Additional Information:${NC}"
    echo -e "  Server IP: ${YELLOW}${SERVER_IP}${NC}"
    echo -e "  Backend Port: ${YELLOW}${AWX_NODEPORT}${NC}"
    echo -e "  Configuration: ${YELLOW}/etc/nginx/sites-available/awx${NC}"
    echo -e "  Info saved to: ${YELLOW}${INFO_FILE}${NC}\n"

    print_info "Nginx is now proxying requests from port 80 to AWX on port ${AWX_NODEPORT}"
    
    if [[ "$ENABLE_SSL" != "true" && -n "$DOMAIN_NAME" ]]; then
        echo -e "\n${YELLOW}💡 Tip:${NC} Enable HTTPS by running:"
        echo -e "  ${CYAN}sudo certbot --nginx -d ${DOMAIN_NAME}${NC}\n"
    fi
}

################################################################################
# Uninstall Function
################################################################################

uninstall_proxy() {
    print_header "Uninstalling Nginx Reverse Proxy"

    print_warning "This will remove the Nginx reverse proxy configuration for AWX"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi

    # Remove site configuration
    if [[ -f /etc/nginx/sites-enabled/awx ]]; then
        print_step "Removing AWX site configuration..."
        rm -f /etc/nginx/sites-enabled/awx
        print_success "Site configuration removed"
    fi

    if [[ -f /etc/nginx/sites-available/awx ]]; then
        print_step "Removing AWX configuration file..."
        rm -f /etc/nginx/sites-available/awx
        print_success "Configuration file removed"
    fi

    # Restore default site
    if [[ -f /etc/nginx/sites-available/default ]] && [[ ! -f /etc/nginx/sites-enabled/default ]]; then
        print_step "Restoring default Nginx site..."
        ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
        print_success "Default site restored"
    fi

    # Test and reload Nginx
    print_step "Testing Nginx configuration..."
    if nginx -t > /dev/null 2>&1; then
        print_step "Reloading Nginx..."
        systemctl reload nginx
        print_success "Nginx reloaded"
    else
        print_warning "Nginx configuration has errors, stopping Nginx..."
        systemctl stop nginx
    fi

    # Clean up info file
    if [[ -f /root/awx-proxy-info.txt ]]; then
        rm -f /root/awx-proxy-info.txt
    fi

    print_success "Reverse proxy configuration removed"
    print_info "Nginx is still installed. To remove it completely, run:"
    echo -e "  ${CYAN}apt-get remove --purge nginx nginx-common${NC}"
    print_info "AWX is still accessible at: http://$(hostname -I | awk '{print $1}'):${AWX_NODEPORT}"
}

################################################################################
# Main Function
################################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            --domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --email)
                EMAIL_ADDRESS="$2"
                shift 2
                ;;
            --enable-ssl)
                ENABLE_SSL=true
                shift
                ;;
            --awx-port)
                AWX_NODEPORT="$2"
                shift 2
                ;;
            --uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Initialize log file
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"

    # Display banner
    echo -e "${CYAN}"
    cat <<'EOF'
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║        Nginx Reverse Proxy Setup                     ║
    ║        for AWX Tower                                 ║
    ║                                                       ║
    ║        Access AWX without port numbers!              ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"

    log "==================== Nginx Reverse Proxy Setup Started ===================="
    print_info "Setup log: $LOG_FILE"

    # Handle uninstall mode
    if $UNINSTALL_MODE; then
        uninstall_proxy
        exit 0
    fi

    # Run setup steps
    check_prerequisites
    install_nginx
    configure_nginx_proxy
    configure_firewall

    # Setup SSL if requested
    if [[ "$ENABLE_SSL" == "true" ]]; then
        setup_ssl
    fi

    display_access_info

    print_header "Setup Complete!"
    print_success "You can now access AWX Tower without specifying a port number"
    
    log "==================== Nginx Reverse Proxy Setup Completed ===================="
}

################################################################################
# Execute Main Function
################################################################################

main "$@"
