---
name: diagnose-awx
description: 'Diagnose AWX installation and deployment issues. Use when troubleshooting failed installations, stuck pods, storage problems, access issues, or deployment errors. Analyzes logs, pod status, and provides fixes from TROUBLESHOOTING.md.'
argument-hint: 'issue description or symptoms'
---

# AWX Troubleshooting Diagnostic

Comprehensive diagnostic workflow for AWX installation and deployment issues.

## When to Use

- Installation script fails or times out
- Pods stuck in Pending, CrashLoopBackOff, or ImagePullBackOff
- AWX web interface not accessible
- Storage (PVC) issues
- Database connectivity problems
- Nginx proxy or SSL certificate errors
- Post-upgrade issues

## Diagnostic Procedure

### 1. Gather Basic Information

**System Context:**
```bash
# OS and resources
cat /etc/os-release | grep VERSION_ID
nproc
free -g
df -h /

# Installation log
tail -100 /var/log/awx-install.log
```

**K3s Cluster Status:**
```bash
kubectl version --short
kubectl cluster-info
kubectl get nodes -o wide
```

**AWX Namespace Overview:**
```bash
kubectl get all -n awx
kubectl get pvc -n awx
kubectl get pv
```

### 2. Identify Problem Area

**Check AWX Operator:**
```bash
kubectl get pods -n awx -l control-plane=controller-manager
kubectl logs deployment/awx-operator-controller-manager -n awx --tail=100
```

**Check AWX Custom Resource:**
```bash
kubectl describe awx awx -n awx
# Look for Status.conditions and Recent Events
```

**Check AWX Pods:**
```bash
kubectl get pods -n awx
kubectl describe pod -l app.kubernetes.io/name=awx -n awx
```

### 3. Common Issues & Fixes

#### **Storage Issues (Most Common)**

**Symptom:** Projects PVC stuck in Pending
```bash
kubectl get pvc -n awx
# STATUS: Pending
```

**Root Cause:** K3s local-path only supports ReadWriteOnce (RWO), AWX projects need ReadWriteMany (RWX)

**Fix:** Use ephemeral storage (default since v1.2.0)
```bash
# In awx.conf
export PROJECTS_PERSISTENCE=false

# Or disable in existing AWX instance
kubectl edit awx awx -n awx
# Set projects_persistence: false
```

**Long-term solution:** Setup NFS storage
- See [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#storage-issues) "Setting Up NFS for Persistent Projects"

#### **PostgreSQL Pod Not Ready**

**Symptom:** PostgreSQL pod doesn't appear or stays not ready

**Check:**
```bash
kubectl get pods -l app.kubernetes.io/component=postgres -n awx
kubectl logs -l app.kubernetes.io/component=postgres -n awx
kubectl describe pod -l app.kubernetes.io/component=postgres -n awx
```

**Common causes:**
- PVC not bound (check storage class)
- Resource limits too low
- Operator reconciliation timing

**Fix:** Wait with proper pattern (checks existence first)
```bash
# Script pattern from install_awx.sh
for i in {1..60}; do
    if kubectl get pod -l app.kubernetes.io/component=postgres -n awx 2>/dev/null | grep -q postgres; then
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=postgres -n awx --timeout=600s
        break
    fi
    sleep 5
done
```

#### **Web/Task Pods CrashLoopBackOff**

**Check logs:**
```bash
kubectl logs -l app.kubernetes.io/component=awx-web -n awx --tail=100
kubectl logs -l app.kubernetes.io/component=awx-task -n awx --tail=100
```

**Common causes:**
- Database connection failure
- Missing secrets
- Resource constraints
- Configuration errors

**Verify secrets:**
```bash
kubectl get secrets -n awx | grep awx
kubectl describe secret awx-admin-password -n awx
```

#### **Access Issues**

**Service not accessible:**
```bash
kubectl get svc -n awx
# Check EXTERNAL-IP and PORT(s)

# Test local access
curl -I http://localhost:30080

# Check firewall
sudo ufw status
sudo ufw allow 30080/tcp comment 'AWX NodePort'
```

**Nginx proxy issues:**
```bash
# Test nginx config
sudo nginx -t

# Check nginx logs
sudo journalctl -u nginx -f

# Verify certificate
sudo openssl x509 -in /etc/nginx/ssl/awx.crt -text -noout
```

#### **Deployment Timeout**

**Symptom:** Installation script times out waiting for pods

**Extend timeouts in script:**
- Manual loops: `{1..60}` → `{1..120}` (10 minutes)
- kubectl wait: `--timeout=600s` → `--timeout=1200s`

**Check what's blocking:**
```bash
kubectl describe awx awx -n awx
kubectl get events -n awx --sort-by='.lastTimestamp'
```

### 4. Complete Diagnostic Report

Provide output from all diagnostic commands with analysis:

1. **Current State Summary**
   - What's running, what's failing
   - Pod status and restart counts
   - PVC binding status

2. **Root Cause Analysis**
   - Log excerpts showing the failure point
   - Configuration mismatches
   - Resource constraints

3. **Recommended Fixes**
   - Specific commands to resolve the issue
   - Configuration changes needed
   - Whether reinstall is required

4. **Prevention**
   - Configuration validation before next install
   - Monitoring recommendations
   - Link to relevant [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md) section

## Reference Resources

- [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md) - Comprehensive issue database with 9 major sections
- [install_awx.sh](../../install_awx.sh) - Wait patterns and validation logic
- [awx.conf](../../awx.conf) - Configuration variables and defaults
- [CHANGELOG.md](../../CHANGELOG.md) - Known issues by version

## Output Format

1. **Issue Summary** - What's failing and symptoms
2. **Diagnostic Results** - Output from commands above
3. **Root Cause** - Technical explanation
4. **Fix Steps** - Numbered commands to resolve
5. **Verification** - Commands to confirm fix worked
6. **Prevention** - Configuration changes to avoid recurrence
