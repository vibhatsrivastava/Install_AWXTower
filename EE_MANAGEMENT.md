# AWX Execution Environment Management

Comprehensive guide for building, managing, and deploying custom Execution Environments (EEs) in AWX using the `manage_awx_ee.sh` automation script.

## Table of Contents

- [Overview](#overview)
- [What are Execution Environments?](#what-are-execution-environments)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Execution Environment Definitions](#execution-environment-definitions)
- [Building Custom EEs](#building-custom-ees)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Advanced Topics](#advanced-topics)

---

## Overview

The `manage_awx_ee.sh` script automates the complete lifecycle of Execution Environments in AWX:

1. **Build** custom EE images using `ansible-builder`
2. **Load** images into K3s containerd for use by AWX
3. **Register** EEs in AWX via REST API
4. **Manage** EEs through list and delete operations
5. **Batch process** multiple EEs from YAML definition files

**Key Features:**
- Configuration-driven workflow
- Automatic validation and error handling
- Support for public and local container registries
- Batch processing for multiple EEs
- Comprehensive logging and status reporting

---

## What are Execution Environments?

**Execution Environments (EEs)** are container images that serve as the runtime for Ansible playbooks in AWX. They contain:

- Ansible Core
- Ansible Runner
- Python dependencies
- Ansible Collections
- System packages
- Custom modules and plugins

**Why use custom EEs?**
- Include specialized Ansible collections (network, cloud, security)
- Add Python libraries required by playbooks (netmiko, boto3, pynetbox)
- Install system packages (git, rsync, openssl)
- Standardize automation environments across teams
- Version control dependencies

**Default EE:**
AWX ships with `quay.io/ansible/awx-ee:latest` containing basic Ansible functionality. Custom EEs extend this for specific use cases.

---

## Prerequisites

### System Requirements

**Required:**
- AWX installed and running (via `install_awx.sh`)
- Root/sudo access
- Python 3.9+ with pip
- 2+ GB available disk space for image builds

**Container Runtime (choose one):**
- **Podman** (recommended): `dnf install podman` or `apt install podman`
- **Docker**: `dnf install docker` or `apt install docker.io`

**Kubernetes Tools:**
- `kubectl` with K3s cluster access
- `ctr` (containerd CLI) for image import

### Software Installation

```bash
# Install ansible-builder
pip3 install ansible-builder

# Install jq (optional but recommended)
apt install jq    # Ubuntu/Debian
dnf install jq    # RHEL/CentOS/Fedora

# Verify installations
ansible-builder --version
podman --version
kubectl cluster-info
```

### AWX Access

Ensure AWX is accessible:

```bash
# Check AWX API
curl http://localhost:30080/api/v2/ping/

# Verify admin credentials
export ADMIN_PASSWORD="your-admin-password"
curl -u admin:$ADMIN_PASSWORD http://localhost:30080/api/v2/me/
```

---

## Quick Start

### 1. Build and Register a Single EE

```bash
# Make script executable
chmod +x manage_awx_ee.sh

# Build from example template
sudo ./manage_awx_ee.sh \
  --build \
  --ee-file examples/ee-minimal.yml \
  --tag awx-ee-minimal:latest

# This will:
# 1. Build the EE image
# 2. Load it into K3s containerd
# 3. Register it in AWX automatically
```

### 2. List Registered EEs

```bash
sudo ./manage_awx_ee.sh --list
```

**Output:**
```
ID    NAME                           IMAGE                        ORG
----- ------------------------------ ---------------------------- ----------
1     Default AWX EE                 quay.io/ansible/awx-ee      1
2     AWX EE Minimal                 awx-ee-minimal:latest       1
```

### 3. Build Multiple EEs from Definitions

```bash
# Edit definitions file
cp examples/ee-definitions-sample.yaml my-ees.yaml
vi my-ees.yaml   # Customize for your needs

# Build all enabled EEs
sudo ./manage_awx_ee.sh --build-all --definitions my-ees.yaml
```

### 4. Verify in AWX UI

1. Log into AWX: `http://YOUR_SERVER_IP:30080`
2. Navigate to **Resources → Execution Environments**
3. Your custom EEs should appear in the list
4. Create a Job Template and select your custom EE from the dropdown

---

## Configuration

### Using awx.conf

Source `awx.conf` for default settings:

```bash
# Edit configuration
vi awx.conf

# Source and run
source awx.conf && sudo -E ./manage_awx_ee.sh --build-all
```

### Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AWX_API_ENDPOINT` | `http://localhost:30080` | AWX API URL |
| `AWX_API_USER` | `admin` | AWX API username |
| `AWX_API_PASSWORD` | *(required)* | AWX admin password |
| `EE_DEFAULT_ORGANIZATION` | `1` | Default organization ID |
| `EE_CONTAINER_RUNTIME` | `podman` | Container engine (podman/docker) |
| `EE_BUILDER_VERBOSITY` | `0` | ansible-builder verbosity (0-3) |
| `EE_BUILDER_NO_CACHE` | `false` | Disable build cache |
| `K3S_CONTAINERD_NAMESPACE` | `k8s.io` | K3s containerd namespace |
| `EE_DEFINITIONS_FILE` | `ee-definitions.yaml` | Default definitions file |
| `EE_CLEANUP_TARBALLS` | `true` | Remove temp tarballs after import |
| `EE_PRUNE_SOURCE_IMAGES` | `false` | Remove source images after K3s import |
| `EE_LOG_FILE` | `/var/log/awx-ee-management.log` | Log file location |

### Command-Line Overrides

All configuration variables can be overridden via CLI:

```bash
sudo ./manage_awx_ee.sh \
  --build \
  --ee-file my-ee.yml \
  --tag my-ee:1.0 \
  --api-endpoint http://awx.example.com \
  --api-user admin \
  --api-password MyPassword123 \
  --runtime docker \
  --verbose
```

---

## Usage Examples

### Single EE Operations

#### Build Only (Skip Load and Register)

```bash
sudo ./manage_awx_ee.sh \
  --build \
  --ee-file examples/ee-collections.yml \
  --tag awx-ee-collections:1.0 \
  --skip-load \
  --skip-register
```

#### Build with Custom Options

```bash
sudo ./manage_awx_ee.sh \
  --build \
  --ee-file examples/ee-python-deps.yml \
  --tag awx-ee-network:2.0 \
  --no-cache \
  --prune-images \
  --verbose
```

#### Register Existing Image

If you already have an image in K3s:

```bash
sudo ./manage_awx_ee.sh \
  --register \
  --name "My Custom EE" \
  --image my-custom-ee:latest \
  --description "Custom EE with network automation tools" \
  --organization 1
```

#### Delete EE from AWX

```bash
# Delete from AWX only (keep image in K3s)
sudo ./manage_awx_ee.sh --delete --name "My Custom EE"

# Delete from AWX and K3s
sudo ./manage_awx_ee.sh \
  --delete \
  --name "My Custom EE" \
  --image my-custom-ee:latest \
  --remove-from-k3s
```

### Batch Operations

#### Validate Definitions Without Building

```bash
sudo ./manage_awx_ee.sh \
  --validate-only \
  --definitions my-ees.yaml
```

#### Build All EEs

```bash
sudo ./manage_awx_ee.sh \
  --build-all \
  --definitions examples/ee-definitions-sample.yaml \
  --verbose
```

#### List EEs in Different Formats

```bash
# Table format (default)
sudo ./manage_awx_ee.sh --list

# JSON format
sudo ./manage_awx_ee.sh --list --format json

# YAML format
sudo ./manage_awx_ee.sh --list --format yaml
```

---

## Execution Environment Definitions

### File Structure

The `ee-definitions.yaml` file defines multiple EEs for batch processing:

```yaml
---
# Global defaults
defaults:
  organization: 1
  container_runtime: podman
  load_to_k3s: true
  register_in_awx: true

# EE definitions
execution_environments:
  - name: "Minimal EE"
    description: "Basic Ansible with no extras"
    ee_file: "examples/ee-minimal.yml"
    image_tag: "awx-ee-minimal:latest"
    organization: 1
    enabled: true
  
  - name: "Network Automation EE"
    description: "With netmiko and network collections"
    ee_file: "examples/ee-python-deps.yml"
    image_tag: "awx-ee-network:1.0"
    organization: 1
    enabled: true
  
  - name: "Test EE"
    description: "Disabled for testing"
    ee_file: "test/ee-test.yml"
    image_tag: "awx-ee-test:latest"
    enabled: false  # Will be skipped
```

### Field Reference

#### Defaults Section

| Field | Required | Description |
|-------|----------|-------------|
| `organization` | No | Default organization ID for all EEs |
| `container_runtime` | No | podman or docker |
| `load_to_k3s` | No | Auto-load to K3s after build |
| `register_in_awx` | No | Auto-register in AWX after load |

#### Execution Environment Entry

| Field | Required | Description |
|-------|----------|-------------|
| `name` | **Yes** | EE name displayed in AWX |
| `ee_file` | **Yes** | Path to execution-environment.yml |
| `image_tag` | **Yes** | Container image tag |
| `description` | No | Description shown in AWX |
| `organization` | No | Organization ID (overrides default) |
| `enabled` | No | Set to false to skip (default: true) |

---

## Building Custom EEs

### execution-environment.yml Structure

The `execution-environment.yml` file defines what goes into your custom EE:

```yaml
version: 3

images:
  base_image:
    name: 'quay.io/centos/centos:stream9'

dependencies:
  ansible_core:
    package_pip: ansible-core>=2.15,<2.16
  ansible_runner:
    package_pip: ansible-runner
  
  # Ansible collections
  galaxy: requirements.yml
  
  # Python packages
  python: |
    netmiko>=4.1.0
    jinja2>=3.1.0
    requests>=2.28.0
  
  # System packages (bindep format)
  system: |
    git-core [platform:rpm]
    python3-devel [platform:rpm]
    gcc [platform:rpm]

# Fix for non-root user (CRITICAL)
additional_build_steps:
  append_base:
    - ENV HOME=/tmp
    - ENV TMPDIR=/tmp
    - ENV ANSIBLE_LOCAL_TEMP=/tmp/.ansible/tmp
```

### Key Sections Explained

#### 1. Base Image (Required)

```yaml
images:
  base_image:
    name: 'quay.io/centos/centos:stream9'
```

**Important:**
- **Must be RPM-based**: CentOS Stream 9, Rocky Linux 9, Fedora, UBI9
- **Must include tag**: `:stream9`, not `:latest`
- **Debian/Ubuntu NOT supported** by ansible-builder

**Recommended base images:**
- `quay.io/centos/centos:stream9` (recommended)
- `rockylinux:9`
- `registry.access.redhat.com/ubi9/ubi:latest`

#### 2. Ansible Dependencies

```yaml
dependencies:
  ansible_core:
    package_pip: ansible-core>=2.15,<2.16
  ansible_runner:
    package_pip: ansible-runner
```

Specify versions to ensure compatibility with AWX.

#### 3. Ansible Collections

**Option A: requirements.yml file**

```yaml
dependencies:
  galaxy: requirements.yml
```

`requirements.yml`:
```yaml
collections:
  - name: community.general
    version: ">=8.0.0"
  - name: ansible.posix
  - name: ansible.netcommon
```

**Option B: Inline specification**

```yaml
dependencies:
  galaxy:
    collections:
      - community.general
      - ansible.posix
```

#### 4. Python Packages

```yaml
dependencies:
  python: |
    netmiko>=4.1.0
    paramiko>=2.7.0
    jinja2>=3.1.0
    requests>=2.28.0
    boto3
```

Or reference a requirements.txt:
```yaml
dependencies:
  python: requirements.txt
```

#### 5. System Packages

```yaml
dependencies:
  system: |
    git-core [platform:rpm]
    python3-devel [platform:rpm]
    gcc [platform:rpm]
    openssl-devel [platform:rpm]
    rsync [platform:rpm]
```

Uses bindep format. Common packages:
- `git-core` - Git operations
- `python3-devel` - Build Python packages
- `gcc` - Compile native extensions
- `openssl-devel` - SSL/TLS operations
- `rsync` - File synchronization

#### 6. Non-Root User Fix (CRITICAL)

```yaml
additional_build_steps:
  append_base:
    - ENV HOME=/tmp
    - ENV TMPDIR=/tmp
    - ENV ANSIBLE_LOCAL_TEMP=/tmp/.ansible/tmp
```

**Why this is required:**
- AWX runs containers as UID 1000 (non-root)
- Default home directory (`~/.ansible/tmp`) is read-only
- Collections fail to install without writable temp directories
- **Always include this section** in custom EEs

### Example Templates

See the `examples/` directory for complete templates:

- **[examples/ee-minimal.yml](examples/ee-minimal.yml)** - Basic EE
- **[examples/ee-collections.yml](examples/ee-collections.yml)** - With collections
- **[examples/ee-python-deps.yml](examples/ee-python-deps.yml)** - With Python packages
- **[examples/requirements.yml](examples/requirements.yml)** - Galaxy requirements

---

## Troubleshooting

### Build Failures

#### Error: "Non-RPM-based image not supported"

**Cause:** Base image is Debian/Ubuntu/Alpine

**Solution:** Use RPM-based image:
```yaml
images:
  base_image:
    name: 'quay.io/centos/centos:stream9'
```

#### Error: "Container image requires tag"

**Cause:** Missing version tag on base image

**Solution:** Add explicit tag:
```yaml
images:
  base_image:
    name: 'quay.io/centos/centos:stream9'  # Not 'centos' or 'centos:latest'
```

#### Error: "ansible-galaxy failed to install collections"

**Cause:** Non-root user cannot write to `~/.ansible/tmp`

**Solution:** Add writable HOME environment:
```yaml
additional_build_steps:
  append_base:
    - ENV HOME=/tmp
    - ENV TMPDIR=/tmp
    - ENV ANSIBLE_LOCAL_TEMP=/tmp/.ansible/tmp
```

#### Error: "File not found: requirements.yml"

**Cause:** Referenced file doesn't exist or wrong path

**Solution:** Verify file paths are correct:
```bash
ls -la requirements.yml
# Update ee file with correct path
```

### K3s Import Failures

#### Error: "Failed to import image to K3s"

**Diagnostic steps:**
```bash
# Check K3s is running
sudo systemctl status k3s

# Check containerd is accessible
sudo ctr version

# Try manual import
sudo podman save my-ee:latest -o /tmp/test.tar
sudo ctr -n k8s.io images import /tmp/test.tar
```

#### Image Not Appearing in K3s

**Verify image:**
```bash
# List images in K3s
sudo ctr -n k8s.io images ls | grep my-ee

# Verify with crictl
sudo k3s crictl images | grep my-ee
```

### AWX Registration Failures

#### Error: "AWX API not accessible"

**Diagnostic steps:**
```bash
# Check AWX pods running
kubectl get pods -n awx

# Test API directly
curl http://localhost:30080/api/v2/ping/

# Test authentication
curl -u admin:password http://localhost:30080/api/v2/me/
```

#### Error: "Authentication failed"

**Solution:** Verify credentials:
```bash
# Get admin password from secret
kubectl get secret awx-admin-password -n awx \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Test with correct password
./manage_awx_ee.sh \
  --list \
  --api-password "correct-password"
```

#### Error: "EE already exists in AWX"

**Solution:** Update existing EE or use different name:
```bash
# Delete existing EE first
./manage_awx_ee.sh --delete --name "My EE"

# Or use a different name
./manage_awx_ee.sh --register --name "My EE v2" --image my-ee:latest
```

### Common Issues

#### Issue: "podman: command not found"

```bash
# Install podman
sudo dnf install podman    # RHEL/CentOS/Fedora
sudo apt install podman    # Ubuntu 22.04+

# Or use docker
export EE_CONTAINER_RUNTIME=docker
```

#### Issue: "ansible-builder: command not found"

```bash
# Install ansible-builder
pip3 install --user ansible-builder

# Add to PATH
export PATH="$HOME/.local/bin:$PATH"

# Verify
ansible-builder --version
```

#### Issue: Build succeeds but playbooks fail in AWX

**Check EE in AWX:**
1. Navigate to Job Template
2. Verify correct EE is selected
3. Check job output for import errors
4. Verify collections are installed:
   ```bash
   podman run --rm my-ee:latest ansible-galaxy collection list
   ```

#### Issue: Permission denied errors

**Solution:** Run script with sudo:
```bash
# Many operations require root
sudo ./manage_awx_ee.sh --build-all

# Or preserve environment
source awx.conf && sudo -E ./manage_awx_ee.sh --list
```

---

## Best Practices

### 1. Version Your EEs

Use semantic versioning in image tags:

```yaml
execution_environments:
  - name: "Network Automation EE"
    image_tag: "awx-ee-network:1.0.0"  # Not :latest
```

**Benefits:**
- Track changes over time
- Roll back if issues occur
- Parallel testing of versions

### 2. Pin Dependency Versions

Specify exact or minimum versions:

```yaml
dependencies:
  ansible_core:
    package_pip: ansible-core==2.15.5
  python: |
    netmiko==4.1.2
    requests>=2.28.0,<3.0.0
```

### 3. Test Before Production

```bash
# Build test version
./manage_awx_ee.sh --build \
  --ee-file my-ee.yml \
  --tag my-ee:test

# Test in AWX with non-critical job
# Promote to production after validation
./manage_awx_ee.sh --build \
  --ee-file my-ee.yml \
  --tag my-ee:1.0.0
```

### 4. Document Your EEs

Add descriptive comments to execution-environment.yml:

```yaml
# Production Network Automation EE
# Last updated: 2024-03-15
# Maintainer: Network Team
# 
# Includes:
# - Cisco IOS collections
# - netmiko for SSH
# - paramiko for connection handling
```

### 5. Use Separate EEs for Different Use Cases

Don't create one massive EE with everything:

```yaml
execution_environments:
  - name: "Network Automation EE"
    ee_file: "ee-network.yml"
    
  - name: "Cloud Automation EE"
    ee_file: "ee-cloud.yml"
    
  - name: "Security Automation EE"
    ee_file: "ee-security.yml"
```

### 6. Regular Maintenance

Update EEs periodically:

```bash
# Rebuild with latest package versions
./manage_awx_ee.sh --build \
  --ee-file ee-network.yml \
  --tag awx-ee-network:1.1.0 \
  --no-cache

# Test new version
# Update job templates to new EE
# Delete old version after validation
./manage_awx_ee.sh --delete \
  --name "Network EE v1.0" \
  --remove-from-k3s
```

---

## Advanced Topics

### Building from Custom Base Images

Create organization-standard base images:

```dockerfile
# Dockerfile.base
FROM quay.io/centos/centos:stream9

RUN dnf install -y \
    git-core \
    python3-devel \
    gcc \
    openssl-devel \
    && dnf clean all

# Add custom CA certificates
COPY ca-bundle.crt /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust
```

Build and use:
```bash
podman build -t my-org/ee-base:1.0 -f Dockerfile.base .
```

Reference in execution-environment.yml:
```yaml
images:
  base_image:
    name: 'my-org/ee-base:1.0'
```

### Private Registry Integration

For private registries, manually push after building:

```bash
# Build locally
./manage_awx_ee.sh --build \
  --ee-file my-ee.yml \
  --tag my-ee:1.0 \
  --skip-load

# Push to private registry
podman tag my-ee:1.0 registry.example.com/awx/my-ee:1.0
podman login registry.example.com
podman push registry.example.com/awx/my-ee:1.0

# Register in AWX with registry path
./manage_awx_ee.sh --register \
  --name "My EE" \
  --image "registry.example.com/awx/my-ee:1.0"
```

### Multi-Architecture Builds

Build for multiple architectures:

```bash
# Build for AMD64 and ARM64
podman build \
  --platform linux/amd64,linux/arm64 \
  --manifest my-ee:1.0 \
  -f context/Containerfile \
  context/

# Push manifest
podman manifest push my-ee:1.0 registry.example.com/my-ee:1.0
```

### CI/CD Integration

Example GitLab CI pipeline:

```yaml
# .gitlab-ci.yml
build-ee:
  stage: build
  script:
    - pip3 install ansible-builder
    - ansible-builder build --tag my-ee:$CI_COMMIT_TAG
    - podman push my-ee:$CI_COMMIT_TAG registry.example.com/my-ee:$CI_COMMIT_TAG
  only:
    - tags

register-awx:
  stage: deploy
  script:
    - ./manage_awx_ee.sh --register \
        --name "My EE $CI_COMMIT_TAG" \
        --image "registry.example.com/my-ee:$CI_COMMIT_TAG" \
        --api-password "$AWX_PASSWORD"
  only:
    - tags
```

### Offline/Air-Gapped Environments

1. **Build on connected system:**
   ```bash
   ansible-builder build --tag my-ee:1.0
   podman save my-ee:1.0 -o my-ee-1.0.tar
   ```

2. **Transfer to air-gapped system:**
   ```bash
   scp my-ee-1.0.tar airgapped-server:/tmp/
   ```

3. **Import on air-gapped system:**
   ```bash
   sudo ctr -n k8s.io images import /tmp/my-ee-1.0.tar
   sudo ./manage_awx_ee.sh --register \
     --name "My EE" \
     --image "my-ee:1.0"
   ```

---

## Additional Resources

### Official Documentation

- **Ansible Builder**: https://ansible-builder.readthedocs.io/
- **AWX Documentation**: https://docs.ansible.com/projects/awx/
- **AWX Operator**: https://github.com/ansible/awx-operator
- **Execution Environments**: https://docs.ansible.com/automation-controller/latest/html/userguide/execution_environments.html

### Community Resources

- **AWX GitHub**: https://github.com/ansible/awx
- **Ansible Forum**: https://forum.ansible.com/
- **AWX Mailing List**: https://groups.google.com/g/awx-project

### Related Project Files

- [README.md](README.md) - AWX installation guide
- [QUICKSTART.md](QUICKSTART.md) - First workflow setup
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting
- [awx.conf](awx.conf) - Configuration reference

---

## Support and Contribution

For issues specific to this automation script:
- Check this documentation thoroughly
- Review [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Check logs in `/var/log/awx-ee-management.log`
- Open an issue on the project repository

For general AWX/Ansible issues:
- Consult official AWX documentation
- Search Ansible community forums
- Check AWX GitHub issues

---

**Last Updated:** 2026-03-30  
**Version:** 1.0.0  
**Maintainer:** AWX Tower Installation Project
