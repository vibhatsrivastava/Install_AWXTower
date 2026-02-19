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
    --domain DOMAIN             Domain name for AWX (e.g., awx.local or awx.example.com)
    --email EMAIL               Email for Let's Encrypt SSL certificates
    --enable-ssl                Enable HTTPS (auto-detects certificate type)
    --awx-port PORT             AWX NodePort (default: ${AWX_NODEPORT})
    --uninstall                 Remove Nginx reverse proxy configuration
    -v, --verbose               Enable verbose output

SSL Certificate Behavior:
    ${CYAN}Internal Domains${NC} (.local, .internal, .lan, localhost, IP addresses)
      → Automatically uses self-signed SSL certificate
      → Valid for 10 years
      → Browser will show security warnings (this is normal)
    
    ${CYAN}Public Domains${NC} (registered domains like awx.example.com)
      → Attempts Let's Encrypt certificate (free, valid, trusted)
      → Falls back to self-signed if Let's Encrypt fails
      → Requires domain DNS pointing to server IP

Examples:
    # Basic HTTP reverse proxy (access via http://SERVER_IP)
    sudo $0

    # Internal HTTPS with self-signed certificate (awx.local)
    sudo $0 --domain awx.local --enable-ssl
    
    # Internal HTTPS with custom domain
    sudo $0 --domain tower.internal --enable-ssl

    # Public HTTPS with Let's Encrypt (requires registered domain)
    sudo $0 --domain awx.example.com --email admin@example.com --enable-ssl

    # Custom AWX port
    sudo $0 --domain awx.local --awx-port 30080 --enable-ssl

    # Uninstall reverse proxy
    sudo $0 --uninstall

Requirements:
    - Ubuntu 24.04 LTS (64-bit)
    - Root or sudo privileges
    - AWX Tower already installed and running
    - For public domains: DNS A record pointing to server IP
    - For internal domains: Add hostname to client's hosts file

After Installation:
    ${GREEN}Internal domains:${NC}
      - Access AWX at: https://awx.local (or your chosen domain)
      - Add to client hosts file: SERVER_IP  awx.local
      - Accept browser security warning for self-signed certificate
    
    ${GREEN}Public domains:${NC}
      - Access AWX at: https://awx.example.com
      - Valid SSL certificate (no warnings)
      - Automatic certificate renewal

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
# Setup Self-Signed SSL Certificate
################################################################################

setup_self_signed_ssl() {
    print_header "Setting Up Self-Signed SSL Certificate"

    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    HOSTNAME_FOR_CERT="${DOMAIN_NAME:-awx.local}"

    # Create SSL directory
    print_step "Creating SSL directory..."
    mkdir -p /etc/nginx/ssl
    chmod 755 /etc/nginx/ssl
    print_success "SSL directory created"

    # Generate self-signed certificate
    print_step "Generating self-signed SSL certificate for ${HOSTNAME_FOR_CERT}..."
    log "Generating SSL certificate with CN=${HOSTNAME_FOR_CERT}, IP=${SERVER_IP}"

    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout /etc/nginx/ssl/awx.key \
        -out /etc/nginx/ssl/awx.crt \
        -subj "/CN=${HOSTNAME_FOR_CERT}/O=AWX Internal/C=US" \
        -addext "subjectAltName=DNS:${HOSTNAME_FOR_CERT},DNS:localhost,DNS:$(hostname),IP:${SERVER_IP}" 2>> "${LOG_FILE}"

    if [ $? -eq 0 ]; then
        chmod 600 /etc/nginx/ssl/awx.key
        chmod 644 /etc/nginx/ssl/awx.crt
        print_success "Self-signed SSL certificate generated successfully"
        log "SSL certificate created at /etc/nginx/ssl/ (valid for 10 years)"
    else
        print_error "Failed to generate SSL certificate"
        log "ERROR: SSL certificate generation failed"
        return 1
    fi

    # Update Nginx configuration for HTTPS
    print_step "Updating Nginx configuration for HTTPS..."
    
    # Backup existing configuration
    if [[ -f /etc/nginx/sites-available/awx ]]; then
        cp /etc/nginx/sites-available/awx "/etc/nginx/sites-available/awx.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Determine server_name
    if [[ -n "$DOMAIN_NAME" ]]; then
        SERVER_NAME="$DOMAIN_NAME"
    else
        SERVER_NAME="_"  # Accept all hostnames
    fi

    # Create HTTPS-enabled configuration
    cat > /etc/nginx/sites-available/awx <<EOF
# Nginx Reverse Proxy Configuration for AWX Tower with Self-Signed SSL
# Generated: $(date)
# Proxies requests from ports 80/443 to AWX NodePort ${AWX_NODEPORT}

# HTTP server - redirect to HTTPS
server {
    listen 80;
    server_name ${SERVER_NAME};
    
    # Redirect all HTTP requests to HTTPS
    return 301 https://\$host\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name ${SERVER_NAME};
    
    # SSL certificate paths (self-signed)
    ssl_certificate /etc/nginx/ssl/awx.crt;
    ssl_certificate_key /etc/nginx/ssl/awx.key;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Increase buffer sizes for AWX
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
    
    # Increase body size limit for file uploads
    client_max_body_size 100M;
    
    # Logging
    access_log /var/log/nginx/awx-access.log;
    error_log /var/log/nginx/awx-error.log;
    
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

    print_success "Nginx HTTPS configuration created"

    # Test and reload Nginx
    print_step "Testing Nginx configuration..."
    if nginx -t >> "${LOG_FILE}" 2>&1; then
        print_success "Nginx configuration is valid"
        print_step "Reloading Nginx..."
        systemctl reload nginx
        print_success "Nginx reloaded with HTTPS enabled"
    else
        print_error "Nginx configuration test failed"
        nginx -t
        return 1
    fi

    print_success "Self-signed SSL setup completed"
    return 0
}

################################################################################
# Setup SSL with Let's Encrypt
################################################################################

setup_ssl() {
    print_header "Setting Up SSL Certificate"

    # Check if domain is internal/local
    print_step "Validating domain configuration..."
    log "Checking domain: ${DOMAIN_NAME}"

    # Detect internal/local/reserved domains
    if [[ "${DOMAIN_NAME}" =~ \.local$ ]] || \
       [[ "${DOMAIN_NAME}" =~ \.internal$ ]] || \
       [[ "${DOMAIN_NAME}" =~ \.lan$ ]] || \
       [[ "${DOMAIN_NAME}" == "localhost" ]] || \
       [[ "${DOMAIN_NAME}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        print_warning "Domain '${DOMAIN_NAME}' is internal/reserved"
        print_info "Let's Encrypt cannot issue certificates for internal domains"
        print_info "Using self-signed certificate instead..."
        log "Internal domain detected, falling back to self-signed certificate"

        # Use self-signed certificate for internal domains
        setup_self_signed_ssl
        return $?
    fi

    # For public domains, proceed with Let's Encrypt
    print_info "Public domain detected: ${DOMAIN_NAME}"
    print_info "Attempting Let's Encrypt certificate..."
    log "Public domain detected, proceeding with Let's Encrypt"

    # Install Certbot
    print_step "Installing Certbot..."
    log "Installing certbot and python3-certbot-nginx"
    if ! command -v certbot &> /dev/null; then
        apt-get install -y -qq certbot python3-certbot-nginx >> "${LOG_FILE}" 2>&1
        if [ $? -eq 0 ]; then
            print_success "Certbot installed"
            log "Certbot installation successful"
        else
            print_error "Failed to install Certbot"
            log "ERROR: Certbot installation failed"
            return 1
        fi
    else
        print_info "Certbot already installed"
        log "Certbot already present on system"
    fi

    # Obtain certificate
    print_step "Obtaining SSL certificate for ${DOMAIN_NAME}..."
    print_info "This will communicate with Let's Encrypt servers"
    log "Running certbot for domain ${DOMAIN_NAME} with email ${EMAIL_ADDRESS}"

    if certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL_ADDRESS" \
        --domain "$DOMAIN_NAME" \
        --redirect >> "${LOG_FILE}" 2>&1; then
        print_success "SSL certificate obtained successfully"
        log "Let's Encrypt certificate obtained for ${DOMAIN_NAME}"

        # Test auto-renewal
        print_step "Testing certificate auto-renewal..."
        if certbot renew --dry-run >> "${LOG_FILE}" 2>&1; then
            print_success "Certificate auto-renewal is configured"
            log "Certbot auto-renewal test passed"
        else
            print_warning "Auto-renewal test failed, but certificate is installed"
            log "WARNING: Certbot auto-renewal test failed"
        fi

        print_success "Let's Encrypt SSL setup completed"
        log "Let's Encrypt setup completed successfully"
    else
        print_error "Failed to obtain Let's Encrypt certificate"
        log "ERROR: Let's Encrypt certificate request failed"
        print_warning "Falling back to self-signed certificate..."
        log "Falling back to self-signed certificate"

        # Fallback to self-signed certificate
        setup_self_signed_ssl
        return $?
    fi

    return 0
}

################################################################################
# Display Access Information
################################################################################

display_access_info() {
    print_header "Reverse Proxy Setup Complete!"

    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')

    # Determine certificate type and access URL
    CERT_TYPE="None"
    if [[ "$ENABLE_SSL" == "true" ]]; then
        if [[ -f /etc/nginx/ssl/awx.crt ]]; then
            CERT_TYPE="Self-Signed"
        elif [[ -f /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem ]]; then
            CERT_TYPE="Let's Encrypt"
        fi
        ACCESS_URL="https://${DOMAIN_NAME}"
        PROTOCOL="HTTPS"
    elif [[ -n "$DOMAIN_NAME" ]]; then
        ACCESS_URL="http://${DOMAIN_NAME}"
        PROTOCOL="HTTP"
    else
        ACCESS_URL="http://${SERVER_IP}"
        PROTOCOL="HTTP"
    fi

    # Determine if internal domain
    IS_INTERNAL_DOMAIN=false
    if [[ "${DOMAIN_NAME}" =~ \\.local$ ]] || \
       [[ "${DOMAIN_NAME}" =~ \\.internal$ ]] || \
       [[ "${DOMAIN_NAME}" =~ \\.lan$ ]] || \
       [[ "${DOMAIN_NAME}" == "localhost" ]]; then
        IS_INTERNAL_DOMAIN=true
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
  ${PROTOCOL,,}://${SERVER_IP}

Configuration:
  - Nginx reverse proxy: Active
  - Protocol: ${PROTOCOL}
  - SSL Certificate: ${CERT_TYPE}
  - AWX Backend Port: ${AWX_NODEPORT}
  - Domain: ${DOMAIN_NAME:-None (IP-based access)}

Nginx Commands:
  # Check status
  systemctl status nginx
  
  # Reload configuration
  systemctl reload nginx
  
  # View access logs
  tail -f /var/log/nginx/awx-access.log
  
  # View error logs
  tail -f /var/log/nginx/awx-error.log
  
  # Test configuration
  nginx -t

SSL Certificate Information:
  - Type: ${CERT_TYPE}
EOF

    if [[ "$CERT_TYPE" == "Self-Signed" ]]; then
        cat >> "$INFO_FILE" <<EOF
  - Certificate: /etc/nginx/ssl/awx.crt
  - Private Key: /etc/nginx/ssl/awx.key
  - Valid for: 10 years
  
  Note: Browsers will show security warnings for self-signed certificates.
  This is normal for internal installations. Click 'Advanced' and proceed.
EOF
        
        if $IS_INTERNAL_DOMAIN; then
            cat >> "$INFO_FILE" <<EOF
  
  Add this to client hosts file to use domain name:
    Windows: C:\\Windows\\System32\\drivers\\etc\\hosts
    Linux/Mac: /etc/hosts
    
    ${SERVER_IP}  ${DOMAIN_NAME}
EOF
        fi
    elif [[ "$CERT_TYPE" == "Let's Encrypt" ]]; then
        cat >> "$INFO_FILE" <<EOF
  - Certificate: /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem
  - Private Key: /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem
  - Auto-renewal: Enabled
  
  Renewal Commands:
    # Renew certificate manually
    certbot renew
    
    # Check certificate status
    certbot certificates
EOF
    fi

    cat >> "$INFO_FILE" <<EOF

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
    echo -e "  ${YELLOW}${ACCESS_URL}${NC}"
    
    if [[ -n "$DOMAIN_NAME" ]]; then
        echo -e "  ${YELLOW}${PROTOCOL,,}://${SERVER_IP}${NC} ${BLUE}(alternative)${NC}\n"
    else
        echo -e "${BLUE}ℹ  No port number needed! Access directly via your server IP.${NC}\n"
    fi

    # SSL-specific information
    if [[ "$ENABLE_SSL" == "true" ]]; then
        if [[ "$CERT_TYPE" == "Self-Signed" ]]; then
            echo -e "${GREEN}✓${NC} ${GREEN}HTTPS enabled with self-signed SSL certificate${NC}\n"
            echo -e "${YELLOW}⚠  Browser Security Warning:${NC}"
            echo -e "   Your browser will show a security warning (self-signed certificate)"
            echo -e "   This is ${GREEN}normal for internal installations${NC}"
            echo -e "   Click ${CYAN}'Advanced'${NC} → ${CYAN}'Proceed to site'${NC} to continue\n"
            
            if $IS_INTERNAL_DOMAIN; then
                echo -e "${CYAN}💡 To use domain name, add to client machines:${NC}"
                echo -e "   ${MAGENTA}Windows:${NC} ${YELLOW}C:\\Windows\\System32\\drivers\\etc\\hosts${NC}"
                echo -e "   ${MAGENTA}Linux/Mac:${NC} ${YELLOW}/etc/hosts${NC}"
                echo -e "   ${BLUE}${SERVER_IP}  ${DOMAIN_NAME}${NC}\n"
            fi
        elif [[ "$CERT_TYPE" == "Let's Encrypt" ]]; then
            echo -e "${GREEN}✓${NC} ${GREEN}HTTPS enabled with valid Let's Encrypt certificate${NC}"
            echo -e "${GREEN}✓${NC} ${GREEN}Automatic certificate renewal configured${NC}\n"
        fi
    fi

    echo -e "${CYAN}Additional Information:${NC}"
    echo -e "  Server IP: ${YELLOW}${SERVER_IP}${NC}"
    echo -e "  Backend Port: ${YELLOW}${AWX_NODEPORT}${NC}"
    echo -e "  SSL Certificate: ${YELLOW}${CERT_TYPE}${NC}"
    echo -e "  Configuration: ${YELLOW}/etc/nginx/sites-available/awx${NC}"
    echo -e "  Info saved to: ${YELLOW}${INFO_FILE}${NC}\n"

    print_info "Nginx is now proxying requests to AWX on port ${AWX_NODEPORT}"
    
    if [[ "$ENABLE_SSL" != "true" && -n "$DOMAIN_NAME" ]] && ! $IS_INTERNAL_DOMAIN; then
        echo -e "\n${YELLOW}💡 Tip:${NC} Enable HTTPS with Let's Encrypt by running:"
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
