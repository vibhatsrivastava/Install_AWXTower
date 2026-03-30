# AWX Python Package Installation Guide

This guide explains how to install Python packages inside running AWX containers using the `install_awx_packages.py` script.

## Table of Contents

- [Overview](#overview)
- [When to Use This Method](#when-to-use-this-method)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Permanent Installation Methods](#permanent-installation-methods)
- [Ansible Collections Installation](#ansible-collections-installation)

---

## Overview

The `install_awx_packages.py` script automates Python package installation in AWX containers by:

1. Discovering running AWX web and task pods in your Kubernetes cluster
2. Executing `pip3 install` commands inside each pod via `kubectl exec`
3. Providing feedback on installation success/failure
4. Supporting bulk installations from requirements files

**Important Limitation**: Packages installed this way are **ephemeral** and will be lost when pods restart. For production environments, consider [permanent installation methods](#permanent-installation-methods).

---

## When to Use This Method

### ✅ **Good Use Cases**

- **Development & Testing**: Quickly test packages before committing to custom images
- **One-time Jobs**: Installing packages needed for a single playbook execution
- **Proof of Concept**: Validating package compatibility with AWX environment
- **Debugging**: Installing diagnostic tools temporarily
- **Ad-hoc Automation**: Quick fixes for urgent automation needs

### ❌ **Not Recommended For**

- **Production Deployments**: Packages disappear on pod restart/upgrade
- **Scheduled Jobs**: If pods restart between job runs, packages will be missing
- **High Availability**: Multiple pods may have inconsistent package states
- **Compliance Environments**: Changes are not version-controlled or audited

---

## Prerequisites

### System Requirements

1. **kubectl Installed**: Command-line tool for Kubernetes
   ```bash
   # Verify kubectl is installed
   kubectl version --client
   ```

2. **Cluster Access**: kubectl configured to access your K3s/Kubernetes cluster
   ```bash
   # Verify cluster connectivity
   kubectl cluster-info
   ```

3. **Python 3.6+**: Required to run the installation script
   ```bash
   # Verify Python version
   python3 --version
   ```

4. **Running AWX Instance**: AWX pods must be in Running state
   ```bash
   # Check AWX pod status
   kubectl get pods -n awx
   ```

### Permissions Required

The user running the script must have:
- `kubectl exec` permissions on AWX pods
- Access to the AWX namespace (default: `awx`)

---

## Quick Start

### 1. Make Script Executable

```bash
chmod +x install_awx_packages.py
```

### 2. Install a Single Package

```bash
python3 install_awx_packages.py requests
```

**Output**:
```
======================================================================
AWX Package Installation
======================================================================

ℹ Checking kubectl availability...
✓ kubectl is available
ℹ Checking namespace 'awx'...
✓ Namespace 'awx' exists
ℹ Finding AWX pods (target: all)...
✓ Found 2 AWX pod(s)
  • awx-web-7d8f9c5b4-xyz12 (web)
  • awx-task-6b9d8a3c2-abc34 (task)

ℹ Installing in pod 'awx-web-7d8f9c5b4-xyz12'...
✓ Successfully installed in 'awx-web-7d8f9c5b4-xyz12'
ℹ Installing in pod 'awx-task-6b9d8a3c2-abc34'...
✓ Successfully installed in 'awx-task-6b9d8a3c2-abc34'

✓ All package installations completed successfully!
⚠ Note: Packages will be lost if pods restart
ℹ Consider building custom AWX images for persistent packages
```

### 3. Verify Installation

```bash
python3 install_awx_packages.py --list
```

---

## Detailed Usage

### Command Syntax

```bash
python3 install_awx_packages.py [OPTIONS] [PACKAGES...]
```

### Options

| Option | Description | Example |
|--------|-------------|---------|
| `PACKAGES` | Space-separated package names | `requests boto3 netmiko` |
| `-r, --requirements FILE` | Install from requirements file | `-r requirements.txt` |
| `-n, --namespace NAME` | Custom Kubernetes namespace | `--namespace my-awx` |
| `-t, --target TYPE` | Target pods: `web`, `task`, or `all` | `--target web` |
| `-u, --upgrade` | Upgrade existing packages | `--upgrade` |
| `-l, --list` | List installed packages | `--list` |
| `-v, --verbose` | Enable verbose output | `--verbose` |
| `-h, --help` | Show help message | `--help` |

### Examples

#### Install Multiple Packages

```bash
python3 install_awx_packages.py requests boto3 ansible-pylibssh
```

#### Install from Requirements File

Create `requirements.txt`:
```
boto3>=1.26.0
azure-mgmt-compute>=30.0.0
netmiko>=4.2.0
```

Install:
```bash
python3 install_awx_packages.py -r requirements.txt
```

#### Install Only in Web Pods

```bash
python3 install_awx_packages.py --target web requests
```

**Use Case**: Web UI extensions that don't need to run in task pods.

#### Install Only in Task Pods

```bash
python3 install_awx_packages.py --target task boto3 pywinrm
```

**Use Case**: Packages required only for playbook execution, not web UI.

#### Upgrade Existing Package

```bash
python3 install_awx_packages.py --upgrade ansible-pylibssh
```

#### Custom Namespace

```bash
python3 install_awx_packages.py --namespace production-awx requests
```

#### Verbose Output (for debugging)

```bash
python3 install_awx_packages.py -v requests
```

Shows kubectl commands being executed.

---

## Common Use Cases

### AWS Automation (boto3)

Install AWS SDK for EC2/S3/RDS automation:

```bash
python3 install_awx_packages.py boto3 botocore
```

**Playbook Example**:
```yaml
---
- name: Manage AWS EC2 Instances
  hosts: localhost
  tasks:
    - name: Launch EC2 instance
      amazon.aws.ec2_instance:
        key_name: mykey
        instance_type: t2.micro
        image_id: ami-123456
        wait: yes
```

### Azure Automation

Install Azure SDK for cloud resource management:

```bash
python3 install_awx_packages.py azure-mgmt-compute azure-mgmt-network azure-mgmt-resource
```

### Network Device Automation (Netmiko/NAPALM)

Install network automation libraries:

```bash
python3 install_awx_packages.py netmiko napalm paramiko
```

**Use Case**: Cisco/Juniper/Arista device configuration management.

### VMware Automation (pyvmomi)

Install VMware vSphere SDK:

```bash
python3 install_awx_packages.py pyvmomi
```

### Windows Management (pywinrm)

Install WinRM library for Windows automation:

```bash
python3 install_awx_packages.py pywinrm requests-ntlm
```

### Database Drivers

Install PostgreSQL/MySQL/MongoDB drivers:

```bash
python3 install_awx_packages.py psycopg2-binary pymongo mysql-connector-python
```

### Monitoring Integration

Install monitoring/APM packages:

```bash
python3 install_awx_packages.py datadog prometheus-client newrelic
```

---

## Best Practices

### 1. Use Requirements Files for Reproducibility

**Create** `requirements.txt`:
```
# AWS Automation Stack
boto3==1.28.85
botocore==1.31.85

# Network Automation
netmiko==4.3.0
napalm==4.1.0

# Utilities
jmespath==1.0.1
```

**Install**:
```bash
python3 install_awx_packages.py -r requirements.txt
```

**Benefits**:
- Version control your dependencies
- Consistent installations across environments
- Easy to share with team members

### 2. Pin Package Versions

❌ **Avoid**:
```bash
python3 install_awx_packages.py requests
```

✅ **Prefer**:
```
# requirements.txt
requests==2.31.0
```

**Why**: Ensures consistent behavior; prevents breaking changes from auto-upgrades.

### 3. Test in Non-Production First

```bash
# Development namespace
python3 install_awx_packages.py --namespace awx-dev boto3

# Run test playbooks
# Verify functionality

# Then deploy to production
python3 install_awx_packages.py --namespace awx-prod boto3
```

### 4. Document Package Requirements

Add to your AWX project's README:
```markdown
## Required Python Packages

This project requires the following packages to be installed in AWX:

```bash
python3 install_awx_packages.py -r requirements.txt
```

See `requirements.txt` for version details.
```

### 5. Monitor Package Installation in Playbooks

Add verification task to playbooks:

```yaml
---
- name: Verify boto3 is installed
  hosts: localhost
  tasks:
    - name: Check boto3 availability
      command: python3 -c "import boto3; print(boto3.__version__)"
      register: boto3_check
      failed_when: boto3_check.rc != 0
      
    - name: Display boto3 version
      debug:
        msg: "Using boto3 version {{ boto3_check.stdout }}"
```

### 6. Keep a Package Installation Log

Create a tracking file:
```bash
# package-log.txt
2026-03-30: Installed boto3==1.28.85 for AWS EC2 automation
2026-03-30: Installed netmiko==4.3.0 for network device management
```

---

## Troubleshooting

### Issue: "kubectl not found or not configured"

**Symptoms**:
```
✗ kubectl not found or not configured
```

**Solution**:
```bash
# Verify kubectl installation
which kubectl

# If not installed (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y kubectl

# Verify cluster access
kubectl cluster-info

# If access fails, ensure kubeconfig is set
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### Issue: "Namespace 'awx' not found"

**Symptoms**:
```
✗ Namespace 'awx' not found
```

**Solutions**:

**Option 1**: Verify AWX namespace name
```bash
kubectl get namespaces
```

**Option 2**: Use correct namespace
```bash
python3 install_awx_packages.py --namespace <actual-namespace> requests
```

### Issue: "No running AWX pods found"

**Symptoms**:
```
✗ No running AWX pods found in namespace 'awx'
```

**Diagnosis**:
```bash
# Check pod status
kubectl get pods -n awx

# Check AWX deployment
kubectl get awx -n awx
```

**Solution**: Ensure AWX is fully deployed and pods are Running:
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=awx -n awx --timeout=600s
```

### Issue: "Failed to install in pod"

**Symptoms**:
```
✗ Failed to install in 'awx-web-7d8f9c5b4-xyz12'
ERROR: Could not find a version that satisfies the requirement...
```

**Common Causes**:

1. **Package name typo**:
   ```bash
   # Wrong
   python3 install_awx_packages.py reqeusts
   
   # Correct
   python3 install_awx_packages.py requests
   ```

2. **Package not available on PyPI**:
   - Verify package exists: https://pypi.org/
   - Check spelling and capitalization

3. **Version conflict**:
   ```bash
   # Use verbose mode to see error details
   python3 install_awx_packages.py -v problematic-package
   ```

4. **Network/proxy issues**:
   ```bash
   # Test pip inside pod manually
   kubectl exec -n awx awx-web-xxxxx -- pip3 install requests
   ```

### Issue: "Permission denied"

**Symptoms**:
```
Error from server (Forbidden): pods "awx-web-xxxxx" is forbidden: 
User "youruser" cannot create resource "pods/exec" in API group ""
```

**Solution**: Grant kubectl exec permissions
```bash
# Check current permissions
kubectl auth can-i create pods/exec -n awx

# Contact cluster admin to grant permissions, or use admin kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

### Issue: Command Timeout

**Symptoms**:
```
Command timed out after 5 minutes
```

**Causes**:
- Large package with many dependencies
- Slow network connection
- Pip downloading large binary wheels

**Solution**: Install packages individually or check network:
```bash
# Test network from pod
kubectl exec -n awx awx-web-xxxxx -- ping -c 3 pypi.org

# Install one at a time
python3 install_awx_packages.py package1
python3 install_awx_packages.py package2
```

### Issue: Packages Disappear After Installation

**Symptoms**: Packages work initially but fail after some time.

**Cause**: Pods restarted (AWX upgrade, node maintenance, crash).

**Diagnosis**:
```bash
# Check pod age
kubectl get pods -n awx -o wide

# Check pod restart count
kubectl get pods -n awx -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'
```

**Solution**: Re-run installation script after pod restarts, or use [permanent installation methods](#permanent-installation-methods).

---

## Permanent Installation Methods

For production use, consider these permanent alternatives:

### Method 1: Custom AWX Container Image (Recommended)

**Overview**: Build custom AWX images with pre-installed packages.

**Steps**:

1. **Create Dockerfile**:
   ```dockerfile
   # Dockerfile.awx-custom
   FROM quay.io/ansible/awx-ee:latest
   
   USER root
   
   # Install Python packages
   RUN pip3 install --no-cache-dir \
       boto3==1.28.85 \
       netmiko==4.3.0 \
       napalm==4.1.0 \
       pywinrm==0.4.3
   
   USER 1000
   ```

2. **Build Image**:
   ```bash
   docker build -f Dockerfile.awx-custom -t my-registry/awx-ee:custom .
   docker push my-registry/awx-ee:custom
   ```

3. **Update AWX Configuration** (`awx.conf`):
   ```bash
   export AWX_EE_IMAGE="my-registry/awx-ee:custom"
   ```

4. **Apply to AWX Instance**:
   ```yaml
   # awx-instance.yaml
   spec:
     ee_images:
       - name: Custom Execution Environment
         image: my-registry/awx-ee:custom
   ```

**Benefits**:
- ✅ Packages persist across pod restarts
- ✅ Version controlled via Dockerfile
- ✅ Consistent across all pods
- ✅ Image can be tested before deployment

### Method 2: Custom Execution Environment

**Overview**: Create AWX Execution Environment with ansible-builder.

**Steps**:

1. **Create EE Definition** (`execution-environment.yml`):
   ```yaml
   ---
   version: 3
   
   images:
     base_image:
       name: quay.io/ansible/awx-ee:latest
   
   dependencies:
     python:
       - boto3==1.28.85
       - netmiko==4.3.0
       - azure-mgmt-compute>=30.0.0
     
     system:
       - git
       - rsync
   
   additional_build_steps:
     prepend_galaxy:
       - RUN pip3 install --upgrade pip setuptools
   ```

2. **Build with ansible-builder**:
   ```bash
   ansible-builder build \
     --tag my-registry/custom-ee:1.0.0 \
     --container-runtime docker
   
   docker push my-registry/custom-ee:1.0.0
   ```

3. **Add to AWX**: 
   - Go to AWX UI → Administration → Execution Environments
   - Add new EE with image `my-registry/custom-ee:1.0.0`
   - Assign to templates/projects

**Benefits**:
- ✅ Ansible-native approach
- ✅ Supports system packages + Python packages
- ✅ Integrates with AWX EE management
- ✅ Can include Ansible collections

### Method 3: Init Container (AWX Instance Customization)

**Overview**: Use init containers to install packages on pod startup.

**AWX Instance Spec**:
```yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  # ... other specs ...
  
  web_extra_volume_mounts: |
    - name: custom-packages
      mountPath: /custom-packages
  
  web_init_container_image: python:3.11-slim
  web_init_container_commands: |
    - sh
    - -c
    - |
      pip3 install --target=/custom-packages \
        boto3==1.28.85 \
        netmiko==4.3.0
  
  task_extra_env: |
    - name: PYTHONPATH
      value: /custom-packages:$PYTHONPATH
```

**Note**: Packages still lost on pod restart but automatically reinstalled.

### Comparison Table

| Method | Persistence | Complexity | Rebuild Time | Recommended For |
|--------|-------------|------------|--------------|-----------------|
| Script (`install_awx_packages.py`) | ❌ Ephemeral | Low | Instant | Dev/Testing |
| Custom Container Image | ✅ Permanent | Medium | 5-10 min | Production |
| Custom Execution Environment | ✅ Permanent | Medium | 10-15 min | Production (Ansible-native) |
| Init Container | ⚠️ Auto-reinstall | High | 2-5 min/restart | Special cases |

---

## Ansible Collections Installation

This section explains how to install and manage Ansible collections in AWX environments. Collections are different from Python packages and require different installation approaches.

### Table of Contents

- [Collections vs Python Packages](#collections-vs-python-packages)
- [Collection Installation Methods](#collection-installation-methods)
- [Method 1: Custom Execution Environment (Recommended)](#method-1-custom-execution-environment-recommended)
- [Method 2: Project Requirements File](#method-2-project-requirements-file)
- [Method 3: Transient Installation](#method-3-transient-installation)
- [Common Collections Examples](#common-collections-examples)
- [Best Practices for Collections](#best-practices-for-collections)

---

### Collections vs Python Packages

Understanding the difference between collections and Python packages is critical for AWX:

| Aspect | Python Packages | Ansible Collections |
|--------|----------------|---------------------|
| **Where Installed** | AWX Web/Task pods | Execution Environment (EE) pods |
| **Installation Tool** | `pip3 install` | `ansible-galaxy collection install` |
| **Pod Lifecycle** | Web/Task pods persist | EE pods created per job |
| **Primary Use** | AWX operations (API, UI) | Playbook execution |
| **Persistence** | Until pod restart | Depends on EE image |
| **Recommended Approach** | Transient OK for dev | Pre-build into EE image |

**Key Insight**: Python packages run AWX itself (web interface, API, task scheduler). Collections run **inside your playbooks** during job execution. They must be present in the container image used to execute jobs.

---

### Collection Installation Methods

Three primary methods for installing collections in AWX:

| Method | Persistence | When to Use | Complexity | Rebuild Time |
|--------|-------------|-------------|-----------|-------------|
| **Custom EE** | ✅ Permanent | Production | Medium | 10-15 min |
| **Project requirements.yml** | ⚠️ Runtime download | Shared collections | Low | Per job |
| **Transient (script)** | ❌ Ephemeral | Dev/Testing only | Low | Instant |

---

### Method 1: Custom Execution Environment (Recommended)

**Overview**: Build a custom container image with collections pre-installed using `ansible-builder`.

**When to Use**:
- ✅ Production deployments
- ✅ Consistent collection versions across all jobs
- ✅ Collections with system dependencies
- ✅ Offline/air-gapped environments

#### Step 1: Create Execution Environment Definition

Create `execution-environment.yml`:

```yaml
---
version: 3

images:
  base_image:
    name: quay.io/ansible/awx-ee:latest

dependencies:
  # Python packages needed by playbooks
  python:
    - boto3==1.28.85
    - psycopg2-binary==2.9.9
    - netmiko==4.3.0
  
  # Ansible collections
  galaxy: |
    collections:
      - name: community.postgresql
        version: "3.4.0"
      - name: awx.awx
        version: "23.3.1"
      - name: community.general
        version: ">=8.0.0"
      - name: ansible.posix
        version: "1.5.4"
  
  # System packages (installed via package manager)
  system:
    - git
    - rsync
    - postgresql-client

additional_build_steps:
  prepend_galaxy:
    - RUN pip3 install --upgrade pip setuptools
  
  append_final:
    - RUN ansible-galaxy collection list
```

**Key Sections**:
- `base_image`: Start from AWX's default EE or another base
- `python`: Python packages available to playbooks
- `galaxy`: Collections to include (supports version pinning)
- `system`: OS packages (yum/apt packages)

#### Step 2: Build the Execution Environment

```bash
# Install ansible-builder (if not already installed)
pip3 install ansible-builder

# Build the custom EE image
ansible-builder build \
  --tag my-registry.example.com/awx-ee-custom:1.0.0 \
  --container-runtime docker \
  --verbosity 3

# Verify collections are included
docker run --rm my-registry.example.com/awx-ee-custom:1.0.0 \
  ansible-galaxy collection list
```

**Expected Output**:
```
# /usr/share/ansible/collections/ansible_collections
Collection             Version
---------------------- -------
ansible.posix          1.5.4
awx.awx                23.3.1
community.general      8.6.0
community.postgresql   3.4.0
```

#### Step 3: Push to Container Registry

```bash
# Login to your container registry
docker login my-registry.example.com

# Push the image
docker push my-registry.example.com/awx-ee-custom:1.0.0

# Tag as latest (optional)
docker tag my-registry.example.com/awx-ee-custom:1.0.0 \
           my-registry.example.com/awx-ee-custom:latest
docker push my-registry.example.com/awx-ee-custom:latest
```

**Registry Options**:
- Docker Hub: `docker.io/username/awx-ee-custom:1.0.0`
- Quay.io: `quay.io/username/awx-ee-custom:1.0.0`
- Private registry: `registry.company.com/awx-ee-custom:1.0.0`
- Local K3s registry: Use `--load` flag instead of push

#### Step 4: Register in AWX

1. **Via Web UI**:
   - Go to **Administration** → **Execution Environments**
   - Click **Add**
   - Fill in:
     - **Name**: Custom EE (PostgreSQL + AWX)
     - **Image**: `my-registry.example.com/awx-ee-custom:1.0.0`
     - **Pull**: Always (or ifNotPresent for stable tags)
   - Click **Save**

2. **Via AWX API** (automation):
   ```bash
   curl -X POST https://awx.example.com/api/v2/execution_environments/ \
     -H "Authorization: Bearer $AWX_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "Custom EE (PostgreSQL + AWX)",
       "image": "my-registry.example.com/awx-ee-custom:1.0.0",
       "pull": "always"
     }'
   ```

#### Step 5: Assign to Job Templates

1. Edit your Job Template
2. Scroll to **Execution Environment** dropdown
3. Select **Custom EE (PostgreSQL + AWX)**
4. Save

All jobs using this template will now use your custom EE with pre-installed collections.

**Benefits**:
- ✅ Collections available immediately (no download time)
- ✅ Consistent versions across all job runs
- ✅ Works offline/air-gapped
- ✅ Can include system dependencies
- ✅ Version controlled via Dockerfile-equivalent
- ✅ Image can be tested before deployment

---

### Method 2: Project Requirements File

**Overview**: Define collections in `collections/requirements.yml` within your Ansible project Git repository.

**When to Use**:
- ✅ Collections specific to one project
- ✅ Rapid prototyping (no EE rebuild needed)
- ✅ Collections without system dependencies
- ⚠️ Acceptable to download collections at job runtime

#### Step 1: Create Requirements File in Project

In your Ansible project Git repository:

```bash
my-ansible-project/
├── playbooks/
│   └── site.yml
├── roles/
├── inventory/
└── collections/
    └── requirements.yml    # ← Create this file
```

**collections/requirements.yml**:
```yaml
---
collections:
  - name: community.postgresql
    version: ">=3.4.0,<4.0.0"  # Semantic version range
  
  - name: awx.awx
    version: "23.3.1"  # Exact version
  
  - name: community.general
    source: https://galaxy.ansible.com  # Explicit source
  
  # From private Automation Hub
  - name: company.custom_collection
    source: https://automation-hub.company.com/api/galaxy/content/published/
```

#### Step 2: Configure AWX to Install Collections

AWX automatically detects `collections/requirements.yml` and installs collections before running jobs.

**Job Template Settings**:
1. Edit Job Template
2. Enable **Update Revision on Launch** in Project settings (ensures latest requirements.yml)
3. Optionally increase **Job Timeout** to account for collection download time

#### Step 3: Test Collection Installation

Run a simple playbook that uses the collection:

```yaml
# playbooks/test-collections.yml
---
- name: Test Collection Installation
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Verify community.postgresql collection
      ansible.builtin.debug:
        msg: "Collection available"
      check_mode: false
    
    - name: List installed collections
      ansible.builtin.command:
        cmd: ansible-galaxy collection list
      register: collections_list
    
    - name: Display collections
      ansible.builtin.debug:
        var: collections_list.stdout_lines
```

**Limitations**:
- ⚠️ Collections downloaded every job run (adds 5-30 seconds)
- ⚠️ Requires internet access (or private Automation Hub)
- ⚠️ No caching between jobs
- ⚠️ Potential version conflicts if EE has different versions
- ⚠️ Can cause job failures if Galaxy is unreachable

**Best Practice**: Use for project-specific collections. Put commonly used collections in custom EE (Method 1).

---

### Method 3: Transient Installation

**Overview**: Install collections temporarily using `install_awx_collections.py` script (similar to Python package script).

**When to Use**:
- ✅ Development and testing
- ✅ Quick proof-of-concept
- ✅ Testing collection before adding to EE
- ❌ **Never for production** (collections lost after EE pod restart)

#### Installation

```bash
# Install single collection
python3 install_awx_collections.py community.postgresql

# Install multiple collections
python3 install_awx_collections.py community.postgresql awx.awx ansible.posix

# Install from requirements file
python3 install_awx_collections.py -r collections-requirements.yml

# Install in custom namespace
python3 install_awx_collections.py -n production-awx community.postgresql

# List installed collections
python3 install_awx_collections.py --list

# Show help
python3 install_awx_collections.py --help
```

#### How It Works

1. Script discovers the active execution environment image
2. Creates a temporary EE pod for collection installation
3. Executes `ansible-galaxy collection install` inside pod
4. Configures `ANSIBLE_COLLECTIONS_PATH` for visibility

**Critical Limitation**: Collections persist only until:
- Execution environment pod restarts
- AWX upgrade/rollout
- Job completes and EE pod is destroyed

**Use Case Example**:
```bash
# Test new collection version before building custom EE
python3 install_awx_collections.py community.postgresql==3.5.0

# Run test playbook in AWX UI
# If successful, add to execution-environment.yml
# Build permanent EE image
```

**Warning**: Do not rely on this for scheduled jobs or production workloads. Always transition to Method 1 (Custom EE) for production use.

---

### Common Collections Examples

#### Example 1: PostgreSQL Database Management

**Use Case**: Automate PostgreSQL database provisioning, user management, backups.

**Collection**: `community.postgresql`

**execution-environment.yml**:
```yaml
version: 3
images:
  base_image:
    name: quay.io/ansible/awx-ee:latest

dependencies:
  python:
    - psycopg2-binary==2.9.9  # Required by community.postgresql
  
  galaxy: |
    collections:
      - name: community.postgresql
        version: "3.4.0"
  
  system:
    - postgresql-client  # CLI tools for testing
```

**Sample Playbook**:
```yaml
---
- name: Manage PostgreSQL Database
  hosts: db_servers
  become: true
  tasks:
    - name: Create application database
      community.postgresql.postgresql_db:
        name: myapp_production
        encoding: UTF-8
        lc_collate: en_US.UTF-8
        lc_ctype: en_US.UTF-8
        template: template0
      become_user: postgres
    
    - name: Create database user
      community.postgresql.postgresql_user:
        name: myapp_user
        password: "{{ db_password }}"  # From AWX credential
        priv: "myapp_production:ALL"
        role_attr_flags: NOSUPERUSER,NOCREATEDB
      become_user: postgres
    
    - name: Grant privileges
      community.postgresql.postgresql_privs:
        database: myapp_production
        roles: myapp_user
        objs: ALL_IN_SCHEMA
        privs: SELECT,INSERT,UPDATE,DELETE
      become_user: postgres
```

**Additional Modules in Collection**:
- `postgresql_db` - Database management
- `postgresql_user` - User/role management
- `postgresql_query` - Execute SQL queries
- `postgresql_privs` - Privilege management
- `postgresql_ext` - Extension management (PostGIS, uuid-ossp, etc.)
- `postgresql_slot` - Replication slot management

---

#### Example 2: AWX Self-Management

**Use Case**: Configure AWX itself via playbooks (infrastructure-as-code for AWX configuration).

**Collection**: `awx.awx`

**execution-environment.yml**:
```yaml
version: 3
images:
  base_image:
    name: quay.io/ansible/awx-ee:latest

dependencies:
  python:
    - awxkit  # AWX Python SDK (may already be in base image)
  
  galaxy: |
    collections:
      - name: awx.awx
        version: "23.3.1"  # Match your AWX version
```

**Sample Playbook** (AWX Configuration as Code):
```yaml
---
- name: Configure AWX via Automation
  hosts: localhost
  connection: local
  gather_facts: false
  
  vars:
    awx_host: "https://awx.example.com"
    awx_username: admin
    # Use AWX credential for password
  
  tasks:
    - name: Create organization
      awx.awx.organization:
        name: "Engineering Team"
        description: "Production automation for engineering"
        state: present
        controller_host: "{{ awx_host }}"
        controller_username: "{{ awx_username }}"
        controller_password: "{{ awx_password }}"
    
    - name: Create inventory
      awx.awx.inventory:
        name: "Production Servers"
        organization: "Engineering Team"
        state: present
        controller_host: "{{ awx_host }}"
        controller_username: "{{ awx_username }}"
        controller_password: "{{ awx_password }}"
    
    - name: Add inventory host
      awx.awx.host:
        name: "web-server-01"
        inventory: "Production Servers"
        variables:
          ansible_host: 192.168.1.100
          ansible_user: ubuntu
        state: present
        controller_host: "{{ awx_host }}"
        controller_username: "{{ awx_username }}"
        controller_password: "{{ awx_password }}"
    
    - name: Create job template
      awx.awx.job_template:
        name: "Deploy Application"
        job_type: run
        inventory: "Production Servers"
        project: "App Deployment"
        playbook: "deploy.yml"
        credentials:
          - "SSH Key - Production"
        state: present
        controller_host: "{{ awx_host }}"
        controller_username: "{{ awx_username }}"
        controller_password: "{{ awx_password }}"
```

**Authentication Options**:

1. **Via Credential** (Recommended):
   ```yaml
   - name: Configure AWX
     awx.awx.organization:
       # ... fields ...
       controller_host: "{{ lookup('env', 'CONTROLLER_HOST') }}"
       controller_username: "{{ lookup('env', 'CONTROLLER_USERNAME') }}"
       controller_password: "{{ lookup('env', 'CONTROLLER_PASSWORD') }}"
   ```
   Create "Red Hat Ansible Automation Platform" credential type in AWX.

2. **Via OAuth Token**:
   ```yaml
   controller_oauthtoken: "{{ awx_oauth_token }}"
   ```

**Use Cases**:
- Bootstrap new AWX instance with standard configuration
- Disaster recovery (restore AWX configuration from code)
- Sync AWX configuration across dev/staging/prod
- Automated team onboarding (create org/team/users/projects)

**Available Modules in awx.awx Collection**:
- `organization`, `team`, `user` - Identity management
- `project`, `inventory`, `host`, `group` - Asset management
- `credential`, `credential_type` - Credential management
- `job_template`, `workflow_job_template` - Automation definitions
- `job_launch`, `workflow_launch` - Job execution
- `settings` - AWX system settings

---

### Best Practices for Collections

#### 1. Version Pinning Strategy

**Exact Versions (Recommended for Production)**:
```yaml
collections:
  - name: community.postgresql
    version: "3.4.0"  # Exact version
```

**Semantic Ranges (For Compatibility)**:
```yaml
collections:
  - name: community.general
    version: ">=8.0.0,<9.0.0"  # Allow minor updates
```

**When to Use Each**:
- **Exact**: Production, compliance, reproducible builds
- **Range**: Development, accepting bugfix updates
- **Latest**: Never recommend (unpredictable)

#### 2. Organize Collections by Purpose

**Multiple Execution Environments**:
```
my-registry.com/
├── awx-ee-base:1.0.0           # Minimal (ansible.builtin only)
├── awx-ee-cloud:1.0.0          # AWS, Azure, GCP collections
├── awx-ee-network:1.0.0        # Cisco, Juniper, Arista
├── awx-ee-database:1.0.0       # PostgreSQL, MySQL, MongoDB
└── awx-ee-all:1.0.0            # Everything (large image)
```

**Benefits**:
- Smaller images (faster pulls)
- Isolated dependency conflicts
- Clear purpose per EE

#### 3. Test Before Production

**Testing Workflow**:
```bash
# 1. Test locally with ansible-navigator
ansible-navigator run playbook.yml \
  --execution-environment-image my-registry.com/awx-ee-custom:1.0.0

# 2. Test in AWX dev environment
# - Create new EE in AWX (dev namespace)
# - Run test jobs

# 3. Staging deployment
# - Push :staging tag
# - Test against production-like data

# 4. Production rollout
# - Tag as :1.0.0 and :latest
# - Update job templates incrementally
```

#### 4. Document Collection Dependencies

Create `README.md` in your execution environment repo:

```markdown
# Custom Execution Environment - Database Automation

## Collections Included

| Collection | Version | Purpose |
|------------|---------|----------|
| community.postgresql | 3.4.0 | PostgreSQL automation |
| community.mysql | 3.8.0 | MySQL automation |
| community.mongodb | 1.6.1 | MongoDB automation |

## Python Dependencies

- psycopg2-binary==2.9.9 (PostgreSQL driver)
- pymongo==4.6.0 (MongoDB driver)
- PyMySQL==1.1.0 (MySQL driver)

## Build Instructions

```bash
ansible-builder build -t my-registry.com/awx-ee-database:1.0.0
```

## Last Updated

2026-03-30 - Updated community.postgresql from 3.3.0 to 3.4.0
```

#### 5. Keep Collections Updated

**Quarterly Review Process**:
1. Check for collection updates: `ansible-galaxy collection list --format json`
2. Review changelogs for breaking changes
3. Test in non-production first
4. Update execution-environment.yml
5. Rebuild and redeploy EE

**Monitoring for CVEs**:
```bash
# Use ansible-lint to scan for deprecated modules
ansible-lint playbooks/

# Check collection security advisories
# Subscribe to: https://github.com/ansible-collections/<collection>/security
```

#### 6. Offline/Air-Gapped Environments

**Pre-download Collections**:
```bash
# Download collection tarballs
ansible-galaxy collection download community.postgresql -p ./offline-collections/

# In air-gapped environment, install from tarball
ansible-galaxy collection install ./offline-collections/community-postgresql-3.4.0.tar.gz
```

**Include in EE Build**:
```yaml
# execution-environment.yml
additional_build_files:
  - src: collections/
    dest: configs/

additional_build_steps:
  append_final:
    - COPY _build/configs/collections/*.tar.gz /tmp/
    - RUN ansible-galaxy collection install /tmp/*.tar.gz
```

---

## Additional Resources

- **AWX Documentation**: https://ansible.readthedocs.io/projects/awx/
- **Execution Environments Guide**: https://docs.ansible.com/automation-controller/latest/html/userguide/execution_environments.html
- **ansible-builder**: https://ansible-builder.readthedocs.io/
- **PyPI Package Index**: https://pypi.org/

---

## Quick Reference Card

```bash
# Install single package
python3 install_awx_packages.py <package>

# Install multiple packages
python3 install_awx_packages.py <pkg1> <pkg2> <pkg3>

# Install from requirements file
python3 install_awx_packages.py -r requirements.txt

# Target specific pods
python3 install_awx_packages.py --target web <package>
python3 install_awx_packages.py --target task <package>

# Upgrade packages
python3 install_awx_packages.py --upgrade <package>

# List installed packages
python3 install_awx_packages.py --list

# Custom namespace
python3 install_awx_packages.py -n <namespace> <package>

# Help
python3 install_awx_packages.py --help
```

---

**Last Updated**: March 30, 2026  
**Script Version**: 1.0.0  
**Compatible with**: AWX 2.19.1+, K3s 1.28+
