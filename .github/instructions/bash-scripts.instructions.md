---
description: "Use when writing, editing, or debugging bash scripts. Applies to shell scripts in this AWX installation project. Covers error handling, output functions, validation patterns, and manifest generation."
applyTo: "**/*.sh"
---

# Bash Script Standards for AWX Installation

## Mandatory Error Handling

Every script must include at the top:
```bash
set -e              # Exit on any command failure
set -o pipefail     # Exit on pipe failures
trap cleanup_on_error ERR  # Automatic cleanup on errors
```

Define cleanup function before any operations:
```bash
cleanup_on_error() {
    print_error "Installation failed. Check logs at $LOG_FILE"
    print_info "To clean up, run: $0 --uninstall"
    exit 1
}
```

## Output Functions

Use the six standardized color-coded functions (defined in both main scripts):

- `print_header()` - Cyan section headers for major phases
- `print_success()` - Green checkmarks for completed operations
- `print_error()` - Red X for failures (writes to stderr)
- `print_warning()` - Yellow alerts for non-fatal issues
- `print_info()` - Blue for informational messages
- `print_step()` - Magenta for progress indicators

**All output functions also call `log()` for timestamped file logging.**

Example:
```bash
print_step "Installing K3s..."
if install_k3s; then
    print_success "K3s installed successfully"
else
    print_error "K3s installation failed"
fi
```

## Wait Patterns (Belt-and-Suspenders)

Always combine manual loops with kubectl wait for reliability:

```bash
# Pattern 1: Wait for resource existence first
for i in {1..60}; do
    if kubectl get pod -l app=myapp -n "$NAMESPACE" 2>/dev/null | grep -q myapp; then
        break
    fi
    sleep 5
done

# Pattern 2: Then wait for readiness
kubectl wait --for=condition=ready pod -l app=myapp -n "$NAMESPACE" --timeout=600s
```

**Timeouts:**
- Use 600s (10 minutes) for pod/deployment readiness
- Use 300s (5 minutes) for operator reconciliation
- Manual loops: 60 iterations × 5s = 5 minutes max

## Validation Functions

Prerequisite checks must validate before any modifications:

```bash
check_prerequisites() {
    # Root/sudo check (exit immediately)
    if [[ $EUID -ne 0 ]]; then
        print_error "Must run as root"
        exit 1
    fi
    
    # OS version (validate Ubuntu 24.04)
    source /etc/os-release
    if [[ "$VERSION_ID" != "24.04" ]]; then
        print_warning "Tested on Ubuntu 24.04, current: $VERSION_ID"
    fi
    
    # Resources (exit if below minimum)
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        print_error "Need 2+ CPU cores, found: $cpu_cores"
        exit 1
    fi
    
    # Network connectivity (required)
    if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        print_error "No internet connectivity"
        exit 1
    fi
}
```

## YAML Manifest Generation

Use heredoc with variable substitution for K8s manifests:

```bash
cat > /tmp/resource.yaml <<EOF
apiVersion: example.com/v1
kind: Resource
metadata:
  name: ${RESOURCE_NAME}
  namespace: ${NAMESPACE}
spec:
  option: ${OPTION:-default_value}
EOF
```

**For conditional sections, append separately:**
```bash
if [[ "${ENABLE_FEATURE}" == "true" ]]; then
    cat >> /tmp/resource.yaml <<EOF
  feature:
    enabled: true
EOF
fi
```

**Always validate before applying:**
```bash
kubectl apply -f /tmp/resource.yaml -n "$NAMESPACE"
if [[ $? -eq 0 ]]; then
    print_success "Resource created"
fi
```

## Configuration Variables

Follow the awx.conf pattern:
- Export all variables
- Provide defaults with `${VAR:-default}`
- Add inline comments explaining implications
- Group by category (Core, Resources, Storage, Advanced)

```bash
# Feature flag with default
export ENABLE_FEATURE="${ENABLE_FEATURE:-false}"

# Usage in script with fallback
FEATURE_VALUE=${ENABLE_FEATURE:-false}
```

## Credential Handling

For K8s secrets with base64 encoding:

```bash
# Retrieve and decode
PASSWORD=$(kubectl get secret "${SECRET_NAME}" \
    -n "$NAMESPACE" \
    -o jsonpath='{.data.password}' | base64 -d)

# Save with restricted permissions
cat > "/root/credentials.txt" <<EOF
Username: ${USERNAME}
Password: ${PASSWORD}
EOF
chmod 600 "/root/credentials.txt"
```

## Common Pitfalls

**Storage access modes:**
- K3s local-path only supports RWO (ReadWriteOnce)
- Never enable `projects_persistence: true` without RWX storage
- Default to ephemeral storage for projects
- See [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#storage-issues)

**Wait ordering:**
- Check resource existence before waiting for readiness
- Prevents "no matching resources found" errors
- Operator needs time to create resources after applying CRD

**Service verification:**
- Always verify services exist before displaying access info
- Use `kubectl get svc` with quiet redirect before announcing success

**Nginx configuration:**
- Run `nginx -t` before `systemctl reload nginx`
- Auto-detect internal domains (`.local`, `.internal`, `.lan`) for self-signed certs
- Provide fallback from Let's Encrypt to self-signed
