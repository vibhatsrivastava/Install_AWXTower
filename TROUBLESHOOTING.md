# AWX Tower Troubleshooting Guide

This guide covers common issues and their solutions when installing and running AWX on Ubuntu 24.04.

## Table of Contents
- [Installation Issues](#installation-issues)
- [K3s Issues](#k3s-issues)
- [AWX Deployment Issues](#awx-deployment-issues)
- [Access Issues](#access-issues)
- [Storage Issues](#storage-issues)
- [Performance Issues](#performance-issues)
- [Database Issues](#database-issues)
- [Network Issues](#network-issues)
- [Upgrade Issues](#upgrade-issues)

---

## Installation Issues

### Script fails with "Permission denied"

**Problem**: Script cannot be executed
```
bash: ./install_awx.sh: Permission denied
```

**Solution**:
```bash
# Make script executable
chmod +x install_awx.sh

# Run with sudo
sudo ./install_awx.sh
```

---

### Prerequisites check fails

**Problem**: System doesn't meet minimum requirements

**Solution**:
```bash
# Check CPU cores
nproc

# Check memory (GB)
free -g

# Check disk space
df -h /

# Ensure you have:
# - 2+ CPU cores (4+ recommended)
# - 4+ GB RAM (8+ recommended)
# - 20+ GB free disk (40+ recommended)
```

---

### Internet connectivity issues

**Problem**: Cannot download packages or images

**Solution**:
```bash
# Test connectivity
ping -c 3 8.8.8.8
ping -c 3 google.com

# Check DNS resolution
nslookup google.com

# If behind proxy, set environment variables
export HTTP_PROXY="http://proxy.example.com:8080"
export HTTPS_PROXY="http://proxy.example.com:8080"
export NO_PROXY="localhost,127.0.0.1"
```

---

## K3s Issues

### K3s installation fails

**Problem**: K3s installer script fails

**Solution**:
```bash
# Check system logs
journalctl -xe

# Try manual installation
curl -sfL https://get.k3s.io | sh -

# Check K3s service status
systemctl status k3s

# View K3s logs
journalctl -u k3s -f

# If needed, uninstall and retry
/usr/local/bin/k3s-uninstall.sh
sudo ./install_awx.sh
```

---

### K3s fails to start

**Problem**: K3s service won't start or crashes

**Solution**:
```bash
# Check if swap is disabled (required for Kubernetes)
swapon --show
# If swap is enabled:
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Check system resources
free -h
df -h

# Restart K3s
sudo systemctl restart k3s
sudo systemctl status k3s

# Check for port conflicts
sudo netstat -tuln | grep 6443
```

---

### Cannot access kubectl

**Problem**: kubectl command not found or no access

**Solution**:
```bash
# Set KUBECONFIG environment variable
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Add to bashrc for persistence
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc

# Use k3s kubectl directly
sudo k3s kubectl get nodes

# Or create kubectl symlink
sudo ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
```

---

### K3s pods stuck in Pending state

**Problem**: CoreDNS or other system pods won't start

**Solution**:
```bash
# Check pod status
kubectl get pods -A

# Describe pending pod
kubectl describe pod POD_NAME -n kube-system

# Check node status
kubectl get nodes

# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# Restart K3s
sudo systemctl restart k3s
```

---

## AWX Deployment Issues

### AWX Operator fails to deploy

**Problem**: Operator pod won't start or crashes

**Solution**:
```bash
# Check operator pod status
kubectl get pods -n awx

# View operator logs
kubectl logs deployment/awx-operator-controller-manager -n awx -f

# Describe operator pod
kubectl describe pod -l control-plane=controller-manager -n awx

# Check if CRDs are installed
kubectl get crd | grep awx

# Reinstall operator
kubectl delete -k https://github.com/ansible/awx-operator/config/default?ref=2.19.1 -n awx
kubectl apply -k https://github.com/ansible/awx-operator/config/default?ref=2.19.1 -n awx
```

---

### AWX pods stuck in Pending or ContainerCreating

**Problem**: AWX pods won't start

**Solution**:
```bash
# Check all pods
kubectl get pods -n awx

# Describe stuck pod
kubectl describe pod POD_NAME -n awx

# Common issues to check:

# 1. Persistent Volume Claims
kubectl get pvc -n awx
# If PVC stuck in Pending, check storage class:
kubectl get storageclass

# 2. Image pull issues
kubectl describe pod POD_NAME -n awx | grep -A 5 "Events:"
# If ImagePullBackOff, check internet connectivity

# 3. Resource constraints
kubectl top nodes
kubectl describe node

# 4. Check operator logs
kubectl logs deployment/awx-operator-controller-manager -n awx --tail=100
```

---

### AWX pods in CrashLoopBackOff

**Problem**: AWX containers keep restarting

**Solution**:
```bash
# Check pod logs
kubectl logs POD_NAME -n awx --previous

# Common causes:

# 1. Database connection issues
kubectl logs awx-postgres-13-0 -n awx

# 2. Resource limits too low
kubectl describe pod POD_NAME -n awx | grep -A 10 "Limits:"

# 3. Configuration errors
kubectl get awx awx -n awx -o yaml

# Fix by editing AWX resource
kubectl edit awx awx -n awx

# Or delete and recreate
kubectl delete awx awx -n awx
kubectl apply -f /tmp/awx-instance.yaml
```

---

### Database migration fails

**Problem**: AWX task pod shows database migration errors

**Solution**:
```bash
# Check AWX task logs
kubectl logs deployment/awx-task -n awx | grep -i migrate

# Check PostgreSQL status
kubectl get pod awx-postgres-13-0 -n awx
kubectl logs awx-postgres-13-0 -n awx

# Access PostgreSQL
kubectl exec -it awx-postgres-13-0 -n awx -- psql -U awx

# In psql, check database:
\l
\c awx
\dt

# If needed, delete AWX instance and recreate
kubectl delete awx awx -n awx
# Wait for cleanup
kubectl apply -f /tmp/awx-instance.yaml
```

---

## Access Issues

### AWX service not created

**Problem**: Installation completes but AWX service doesn't exist. Only operator metrics service is visible.

**Symptoms**:
```bash
kubectl get svc -n awx
# Shows only: awx-operator-controller-manager-metrics-service
# Missing: awx-service
```

**Diagnosis**:
```bash
# 1. Check AWX custom resource status
kubectl describe awx awx -n awx

# 2. Look for status conditions
kubectl get awx awx -n awx -o jsonpath='{.status.conditions}' | jq

# 3. Check operator logs for errors
kubectl logs deployment/awx-operator-controller-manager -n awx --tail=100

# 4. Check if operator is running
kubectl get pods -n awx -l control-plane=controller-manager

# 5. View all events in namespace
kubectl get events -n awx --sort-by='.lastTimestamp'
```

**Common Causes & Solutions**:

1. **Operator still reconciling** - Wait 5-10 more minutes:
```bash
# Watch operator logs
kubectl logs deployment/awx-operator-controller-manager -n awx -f
```

2. **Storage issues** - Check if persistent volume can be created:
```bash
# Check storage class
kubectl get storageclass

# Check persistent volume claims
kubectl get pvc -n awx

# If PVC stuck in Pending, check events
kubectl describe pvc -n awx
```

3. **Resource constraints** - Operator may fail due to insufficient resources:
```bash
# Check node resources
kubectl top node
kubectl describe node

# Check operator pod status
kubectl describe pod -n awx -l control-plane=controller-manager
```

4. **RBAC issues** - Operator may lack permissions:
```bash
# Check operator service account
kubectl get serviceaccount -n awx

# Check role bindings
kubectl get rolebindings -n awx
```

5. **Invalid AWX resource spec**:
```bash
# View AWX resource
kubectl get awx awx -n awx -o yaml

# Delete and recreate if needed
kubectl delete awx awx -n awx
kubectl apply -f /tmp/awx-instance.yaml
```

**Fix**: After resolving the underlying issue, the operator should automatically create the service within 1-2 minutes. Monitor with:
```bash
watch kubectl get svc -n awx
```

---

### Cannot access AWX web interface

**Problem**: Web interface unreachable from localhost

**Solution**:
```bash
# 1. Check service status
kubectl get svc -n awx

# 2. Verify NodePort
kubectl get svc awx-service -n awx -o jsonpath='{.spec.ports[0].nodePort}'

# 3. Check if pods are running
kubectl get pods -n awx

# 4. Test from server
curl -I http://localhost:30080

# 5. Check firewall
sudo ufw status
sudo ufw allow 30080/tcp

# 6. Check if port is listening
sudo netstat -tuln | grep 30080

# 7. Get node IP
hostname -I

# 8. Access from browser
# http://NODE_IP:30080
```

---

### Cannot access AWX from other machines on network (LAN)

**Problem**: AWX works on localhost but cannot be accessed from other machines on the same network

**Symptoms**:
- `http://localhost:30080` works on the Ubuntu host
- `http://<HOST_IP>:30080` times out or connection refused from other machines
- Browser shows "Unable to connect" or "Connection timed out"

**Diagnosis**:
```bash
# 1. Verify firewall allows NodePort
sudo ufw status | grep 30080
# Should show: 30080/tcp ALLOW Anywhere

# 2. Check if K3s is listening on all interfaces
sudo netstat -tuln | grep 30080
# Should show: 0.0.0.0:30080 or :::30080

# 3. Verify service has NodePort configured
kubectl get svc awx-service -n awx -o yaml | grep -A 5 ports

# 4. Test connectivity from host to itself using external IP
curl -I http://$(hostname -I | awk '{print $1}'):30080

# 5. Check for additional firewall rules (iptables)
sudo iptables -L -n | grep 30080
```

**Solutions**:

1. **Firewall not configured** - Open AWX port:
```bash
# Allow port 30080
sudo ufw allow 30080/tcp comment 'AWX NodePort'

# Reload firewall
sudo ufw reload

# Verify
sudo ufw status | grep 30080
```

2. **Wrong IP address** - Get correct network IP:
```bash
# List all IP addresses
hostname -I

# Or use ip command
ip addr show | grep "inet " | grep -v 127.0.0.1

# Test access with each IP
# The LAN IP is usually the first one (not 127.0.0.1)
```

3. **Router/network firewall blocking** - Check network equipment:
```bash
# From another LAN machine, test if host is reachable
ping <HOST_IP>

# Test if SSH port is accessible
telnet <HOST_IP> 22

# Test if AWX port is accessible
telnet <HOST_IP> 30080

# If SSH works but 30080 doesn't, it's a firewall issue
```

4. **K3s not binding to external interface** - Verify K3s configuration:
```bash
# Check K3s configuration
sudo cat /etc/systemd/system/k3s.service | grep ExecStart

# K3s should NOT have --bind-address=127.0.0.1
# If it does, reinstall with correct binding
```

5. **Cloud/virtual environment** - Configure security groups:
- AWS: Add inbound rule for port 30080 to security group
- Azure: Add inbound port rule to network security group
- GCP: Add firewall rule allowing tcp:30080
- VMware/VirtualBox: Ensure network adapter is in bridged mode

**Verification**:
```bash
# From another machine on the same network
curl -I http://<UBUNTU_HOST_IP>:30080

# Should return HTTP 200 or redirect to login page

# Or test in browser
http://<UBUNTU_HOST_IP>:30080
```

**Additional Checks**:
```bash
# Check if service has endpoints
kubectl get endpoints awx-service -n awx

# Verify pods are running and ready
kubectl get pods -n awx -o wide

# Check K3s service proxy
sudo systemctl status k3s | grep -i proxy
```

---

### Login fails with correct credentials

**Problem**: Cannot login with admin credentials

**Solution**:
```bash
# Retrieve admin password from secret
kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d
echo

# Reset admin password
kubectl exec -it deployment/awx-task -n awx -- awx-manage changepassword admin

# Or create new superuser
kubectl exec -it deployment/awx-task -n awx -- awx-manage createsuperuser
```

---

### 502 Bad Gateway error

**Problem**: Web interface shows 502 error

**Solution**:
```bash
# Check AWX web pod
kubectl get pods -n awx | grep web
kubectl logs deployment/awx-web -n awx

# Check AWX task pod
kubectl logs deployment/awx-task -n awx

# Restart deployments
kubectl rollout restart deployment/awx-web -n awx
kubectl rollout restart deployment/awx-task -n awx

# Wait for rollout
kubectl rollout status deployment/awx-web -n awx
```

---

## Storage Issues

### Projects PVC stuck in Pending - ReadWriteMany not supported

**Problem**: AWX pods stuck in Pending state with projects PVC failing to provision

**Symptoms**:
```bash
kubectl get pvc -n awx
# Shows: awx-projects-claim   Pending

kubectl get pods -n awx
# Shows: awx-web and awx-task pods stuck in Pending

kubectl logs -n kube-system -l app=local-path-provisioner
# Error: "NodePath only supports ReadWriteOnce and ReadWriteOncePod (1.22+) access modes"
```

**Root Cause**: AWX requires **ReadWriteMany (RWX)** storage for projects so both `awx-web` and `awx-task` pods can mount the volume. K3s's `local-path` provisioner only supports **ReadWriteOnce (RWO)**.

**Solution 1: Disable Projects Persistence (Quick Fix)**

```bash
# Delete AWX instance
kubectl delete awx awx -n awx

# Wait for cleanup
sleep 30

# Edit AWX instance manifest
vim /tmp/awx-instance.yaml

# Change:
#   projects_persistence: true
# To:
#   projects_persistence: false

# Reapply
kubectl apply -f /tmp/awx-instance.yaml

# Watch pods come up (2-3 minutes)
watch kubectl get pods -n awx
```

**Impact**: Projects will use ephemeral storage (emptyDir). Git repositories are re-cloned on pod restart. Suitable for most use cases.

**Solution 2: Set Up NFS Storage (For Persistent Projects)**

See [Setting Up NFS for AWX Projects](#setting-up-nfs-for-awx-projects) below.

---

### Setting Up NFS for AWX Projects

**Prerequisites**: Persistent projects storage with ReadWriteMany access

#### Step 1: Install NFS Server

**On NFS Server Machine (can be the same Ubuntu host):**

```bash
# Install NFS server
sudo apt update
sudo apt install -y nfs-kernel-server

# Create shared directory
sudo mkdir -p /srv/nfs/awx-projects
sudo chown nobody:nogroup /srv/nfs/awx-projects
sudo chmod 777 /srv/nfs/awx-projects

# Configure NFS exports
sudo bash -c 'cat >> /etc/exports <<EOF
/srv/nfs/awx-projects *(rw,sync,no_subtree_check,no_root_squash)
EOF'

# Apply exports
sudo exportfs -ra

# Start NFS server
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server

# Check exports
sudo exportfs -v

# Allow NFS through firewall
sudo ufw allow from 192.168.0.0/16 to any port nfs
```

#### Step 2: Install NFS Client Provisioner in K3s

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Install Helm (if not already installed)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add NFS provisioner Helm repo
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# Set NFS server IP (use actual IP or hostname)
export NFS_SERVER="192.168.1.100"  # Change to your NFS server IP
export NFS_PATH="/srv/nfs/awx-projects"

# Install NFS provisioner
helm install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace kube-system \
  --set nfs.server=$NFS_SERVER \
  --set nfs.path=$NFS_PATH \
  --set storageClass.name=nfs-client \
  --set storageClass.accessModes=ReadWriteMany

# Verify provisioner is running
kubectl get pods -n kube-system | grep nfs

# Check storage class
kubectl get storageclass
# Should show: nfs-client with VOLUMEBINDINGMODE: Immediate
```

#### Step 3: Configure AWX to Use NFS

**Option A: Fresh Installation**

Edit `awx.conf` before running install script:
```bash
export PROJECTS_PERSISTENCE="true"
export PROJECTS_STORAGE_CLASS="nfs-client"
export PROJECTS_STORAGE_SIZE="8Gi"

# Run installation
source awx.conf && sudo -E ./install_awx.sh
```

**Option B: Update Existing AWX Instance**

```bash
# Delete existing AWX instance
kubectl delete awx awx -n awx

# Wait for cleanup (check PVCs are deleted)
kubectl get pvc -n awx

# Edit AWX manifest
vim /tmp/awx-instance.yaml

# Update spec:
spec:
  projects_persistence: true
  projects_storage_class: nfs-client
  projects_storage_size: 8Gi

# Apply updated manifest
kubectl apply -f /tmp/awx-instance.yaml

# Watch deployment
watch kubectl get pods -n awx
```

#### Step 4: Verify NFS Storage

```bash
# Check PVC is bound
kubectl get pvc -n awx
# awx-projects-claim should show: Bound

# Check PV details
kubectl get pv
# Should show NFS server and path

# Verify pods are running
kubectl get pods -n awx
# All pods should be Running

# Test NFS mount
kubectl exec -it deployment/awx-task -n awx -- df -h | grep projects
# Should show NFS mount

# Create test file from pod
kubectl exec -it deployment/awx-task -n awx -- touch /var/lib/awx/projects/test.txt

# Verify on NFS server
ls -la /srv/nfs/awx-projects/
# Should see test.txt
```

#### Troubleshooting NFS

**PVC stuck in Pending:**
```bash
# Check provisioner logs
kubectl logs -n kube-system -l app=nfs-subdir-external-provisioner

# Test NFS mount from K3s node
sudo apt install -y nfs-common
sudo mkdir -p /mnt/test
sudo mount -t nfs $NFS_SERVER:$NFS_PATH /mnt/test
ls -la /mnt/test
sudo umount /mnt/test
```

**Permission denied errors:**
```bash
# On NFS server, set permissive permissions
sudo chmod 777 /srv/nfs/awx-projects
sudo chown nobody:nogroup /srv/nfs/awx-projects

# Update exports with no_root_squash
sudo vim /etc/exports
# Add: no_root_squash to the export line

sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

**Firewall blocking NFS:**
```bash
# On NFS server
sudo ufw status
sudo ufw allow from <K3S_NODE_IP> to any port nfs
sudo ufw allow from <K3S_NODE_IP> to any port 111  # rpcbind
sudo ufw allow from <K3S_NODE_IP> to any port 2049  # nfs
```

---

### Disk space issues

**Problem**: Installation fails or AWX stops working due to full disk

**Solution**:
```bash
# Check disk space
df -h

# Check K3s storage usage
sudo du -sh /var/lib/rancher/k3s/storage/*

# Clean up unused images
sudo k3s crictl images
sudo k3s crictl rmi <unused-image-id>

# Clean up unused containers
sudo k3s crictl ps -a
sudo k3s crictl rm <stopped-container-id>

# Check PV usage
kubectl exec -it deployment/awx-task -n awx -- df -h

# Clean old container logs
sudo journalctl --vacuum-time=3d
```

---

## Performance Issues

### AWX is slow or unresponsive

**Problem**: Poor performance, timeouts

**Solution**:
```bash
# Check resource usage
kubectl top pods -n awx
kubectl top nodes

# Check if pods are being throttled
kubectl describe pod -n awx | grep -A 5 "Resource Limits"

# Increase resource limits
kubectl edit awx awx -n awx
# Increase CPU and memory limits

# Check database performance
kubectl exec -it awx-postgres-13-0 -n awx -- psql -U awx -c "
SELECT pid, usename, application_name, client_addr, state, query 
FROM pg_stat_activity 
WHERE state != 'idle';"

# Check disk I/O
sudo iotop
```

---

### Jobs are queuing but not running

**Problem**: Jobs stuck in pending status

**Solution**:
```bash
# Check AWX task pods
kubectl get pods -n awx | grep task

# Check task pod logs
kubectl logs deployment/awx-task -n awx --tail=100

# Access AWX container and check capacity
kubectl exec -it deployment/awx-task -n awx -- awx-manage list_instances

# Check job queues in AWX UI:
# Administration → Instance Groups → default

# Scale task pods (if needed)
kubectl scale deployment awx-task -n awx --replicas=2
```

---

## Database Issues

### PostgreSQL pod won't start

**Problem**: Database container fails

**Solution**:
```bash
# Check PostgreSQL pod
kubectl get pod awx-postgres-13-0 -n awx
kubectl describe pod awx-postgres-13-0 -n awx

# Check logs
kubectl logs awx-postgres-13-0 -n awx

# Check PVC
kubectl get pvc -n awx | grep postgres

# Check PV
kubectl get pv

# If corrupted, delete and recreate AWX instance
kubectl delete awx awx -n awx
# Wait for cleanup, then recreate
```

---

### Database connection errors

**Problem**: AWX cannot connect to database

**Solution**:
```bash
# Check PostgreSQL service
kubectl get svc -n awx | grep postgres

# Test connection from AWX pod
kubectl exec -it deployment/awx-task -n awx -- bash
# Inside container:
psql -h awx-postgres-13 -U awx -d awx

# Check database credentials secret
kubectl get secret awx-postgres-configuration -n awx -o yaml

# Restart AWX deployments
kubectl rollout restart deployment/awx-web -n awx
kubectl rollout restart deployment/awx-task -n awx
```

---

## Network Issues

### DNS resolution fails

**Problem**: Cannot resolve hostnames in jobs

**Solution**:
```bash
# Check CoreDNS
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system deployment/coredns

# Test DNS from AWX pod
kubectl exec -it deployment/awx-task -n awx -- nslookup google.com

# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# Check K3s DNS settings
cat /etc/rancher/k3s/k3s.yaml | grep dns
```

---

### Cannot reach external hosts

**Problem**: AWX jobs cannot connect to managed hosts

**Solution**:
```bash
# Check from AWX task pod
kubectl exec -it deployment/awx-task -n awx -- bash
# Inside container:
ping TARGET_HOST
telnet TARGET_HOST 22

# Check network policies
kubectl get networkpolicies -n awx

# Check egress firewall rules
sudo iptables -L OUTPUT -n -v

# Verify credentials in AWX UI
# Resources → Credentials
```

---

## Upgrade Issues

### Upgrade fails or pods crash after upgrade

**Problem**: AWX not working after upgrade

**Solution**:
```bash
# Check operator version
kubectl get deployment awx-operator-controller-manager -n awx -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check AWX instance version
kubectl get awx awx -n awx -o jsonpath='{.spec.version}'

# Rollback operator if needed
kubectl apply -k "https://github.com/ansible/awx-operator/config/default?ref=PREVIOUS_VERSION" -n awx

# Check migration status
kubectl logs deployment/awx-task -n awx | grep migrate

# If database migration failed, restore from backup
```

---

## General Debugging Tips

### Collect diagnostic information

```bash
# Create diagnostic report
cat > /tmp/awx-diagnostics.sh <<'EOF'
#!/bin/bash
echo "=== Nodes ==="
kubectl get nodes -o wide

echo -e "\n=== Pods ==="
kubectl get pods -n awx -o wide

echo -e "\n=== Services ==="
kubectl get svc -n awx

echo -e "\n=== PVCs ==="
kubectl get pvc -n awx

echo -e "\n=== Events ==="
kubectl get events -n awx --sort-by='.lastTimestamp' | tail -20

echo -e "\n=== AWX Resource ==="
kubectl get awx awx -n awx -o yaml

echo -e "\n=== Operator Logs ==="
kubectl logs deployment/awx-operator-controller-manager -n awx --tail=50

echo -e "\n=== Web Logs ==="
kubectl logs deployment/awx-web -n awx --tail=50

echo -e "\n=== Task Logs ==="
kubectl logs deployment/awx-task -n awx --tail=50

echo -e "\n=== System Info ==="
free -h
df -h
nproc
EOF

chmod +x /tmp/awx-diagnostics.sh
/tmp/awx-diagnostics.sh > /tmp/awx-diagnostics.txt 2>&1
```

---

### Enable verbose logging

```bash
# Edit AWX instance for debug logging
kubectl edit awx awx -n awx

# Add under spec:
spec:
  web_extra_env: |
    - name: DJANGO_LOGGING_LEVEL
      value: DEBUG
    - name: ANSIBLE_VERBOSITY
      value: "3"
```

---

### Complete reinstall

If all else fails:

```bash
# Uninstall AWX
sudo ./install_awx.sh --uninstall

# Clean up any remaining resources
kubectl delete namespace awx --force --grace-period=0

# Uninstall K3s
/usr/local/bin/k3s-uninstall.sh

# Clean up
sudo rm -rf /var/lib/rancher
sudo rm -rf /etc/rancher

# Reinstall
sudo ./install_awx.sh
```

---

## Getting Help

If you're still experiencing issues:

1. **Check logs**: `/var/log/awx-install.log`
2. **Review documentation**: [AWX Documentation](https://ansible.readthedocs.io/projects/awx/)
3. **Search issues**: [AWX GitHub Issues](https://github.com/ansible/awx/issues)
4. **Community forums**: [Ansible Forum](https://forum.ansible.com/)
5. **Mailing list**: [AWX Project](https://groups.google.com/g/awx-project)

When reporting issues, include:
- Ubuntu version: `lsb_release -a`
- K3s version: `k3s --version`
- AWX Operator version
- Error messages and logs
- Output from diagnostic script above
