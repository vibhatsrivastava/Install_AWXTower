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
