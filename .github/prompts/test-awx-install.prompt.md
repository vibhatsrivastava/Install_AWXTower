---
description: "Generate comprehensive test plan for AWX installation including verification commands and expected outputs"
argument-hint: "test scenario (fresh-install, upgrade, uninstall, or custom)"
---

Generate a comprehensive test plan for AWX installation based on the specified scenario.

## Test Scenario

Scenario: {scenario or "fresh-install"}

## Requirements

Generate a test plan that includes:

### 1. Pre-Test Verification
- System requirements check (CPU, RAM, disk, OS version)
- Network connectivity validation
- Port availability check
- Dependencies verification

### 2. Installation Testing
- Execute installation with monitoring
- Log collection points
- Expected console output at each phase
- Timeout expectations (use 600s for pod readiness)

### 3. Post-Installation Validation

Include commands to verify:

**K3s Cluster:**
```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

**AWX Deployment:**
```bash
kubectl get pods -n awx
kubectl get svc -n awx
kubectl describe awx awx -n awx
kubectl logs deployment/awx-operator-controller-manager -n awx --tail=50
```

**Service Accessibility:**
```bash
# From local host
curl -I http://localhost:30080

# From network (replace IP)
curl -I http://SERVER_IP:30080
```

**Credential Retrieval:**
```bash
kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d
cat /root/awx-credentials.txt
```

**Storage:**
```bash
kubectl get pvc -n awx
kubectl get pv
```

### 4. Functional Testing

Include verification steps from [QUICKSTART.md](../../QUICKSTART.md):
1. Web UI login test
2. Organization creation
3. Credential setup (SSH key or password)
4. Inventory creation with test host
5. Simple playbook execution

### 5. Rollback/Cleanup Testing

For uninstall scenario:
```bash
sudo ./install_awx.sh --uninstall
# Verify removal of:
# - K3s service
# - AWX namespace
# - Network configuration
# - Firewall rules
```

### 6. Known Issues to Check

Reference [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md) for common issues:
- Projects PVC stuck in Pending (storage access mode issue)
- PostgreSQL pod not ready (timing/race condition)
- Service not accessible externally (firewall rules)
- Nginx proxy certificate issues

## Output Format

Provide:
1. **Test checklist** with pass/fail criteria
2. **Command sequence** for manual testing
3. **Expected outputs** for each verification step
4. **Failure scenarios** with diagnostic commands
5. **Cleanup steps** after testing

## Additional Context

- Installation logs: `/var/log/awx-install.log`
- Use belt-and-suspenders approach: manual loops + kubectl wait
- Projects persistence disabled by default (ephemeral storage)
- Timeout: 600s for pod readiness, 300s for operator reconciliation
