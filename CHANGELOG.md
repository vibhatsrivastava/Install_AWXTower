# Changelog

All notable changes to the AWX Tower installation script will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-18

### Added
- Initial release of AWX Tower installation script for Ubuntu 24.04
- K3s (lightweight Kubernetes) installation and configuration
- AWX Operator deployment automation
- AWX instance creation with configurable parameters
- Prerequisites validation (CPU, memory, disk space, OS version)
- System preparation (package installation, swap disable, firewall config)
- Deployment monitoring with timeout handling
- Credential retrieval and secure storage
- Color-coded console output for better UX
- Comprehensive logging to `/var/log/awx-install.log`
- Uninstall functionality for clean removal
- Command-line options:
  - `--awx-version`: Specify AWX Operator version
  - `--admin-password`: Set custom admin password
  - `--namespace`: Custom namespace
  - `--skip-k3s`: Skip K3s installation
  - `--uninstall`: Remove installation
  - `-v, --verbose`: Enable verbose output
- Resource requirements configuration
- NodePort service type for easy access
- Persistent storage for PostgreSQL and projects
- Error handling with cleanup on failure
- Post-installation access information display

### Documentation
- Comprehensive README.md with installation guide
- Quick Start guide for first-time users
- Troubleshooting guide with common issues and solutions
- Configuration file template (awx.conf)
- .gitignore for security and cleanliness

### Features
- Auto-generation of secure admin password
- Firewall configuration for required ports
- Support for Ubuntu 24.04 LTS
- Kubernetes cluster health verification
- Pod readiness waiting with timeout
- Credentials saved to secure file
- Installation progress tracking
- Detailed success/error messages

### System Requirements
- Ubuntu 24.04 LTS (64-bit)
- 2+ CPU cores (4+ recommended)
- 4+ GB RAM (8+ recommended)
- 20+ GB free disk space (40+ recommended)
- Internet connectivity
- Root or sudo privileges

### Default Configuration
- AWX Operator version: 2.19.1
- Namespace: awx
- Instance name: awx
- NodePort: 30080
- PostgreSQL storage: 8Gi
- Projects storage: 8Gi
- Web resources: 500m CPU, 2Gi RAM (requests)
- Task resources: 500m CPU, 2Gi RAM (requests)

## [Unreleased]

### Fixed
- Fixed `install_awx_collections.py` failing in non-root AWX execution environment images by configuring a writable temporary home and Ansible cache/tmp directories inside the installer pod.

### Planned Features
- [ ] External PostgreSQL database support
- [ ] TLS/SSL certificate configuration
- [ ] LDAP/Active Directory integration
- [ ] Backup and restore automation
- [ ] Custom resource requirements via CLI
- [ ] LoadBalancer service type option
- [ ] Multiple namespace support
- [ ] Helm chart deployment option

## [1.2.0] - 2026-02-18

### Fixed
- **Critical Storage Issue**: Projects PVC failing with ReadWriteMany error on K3s local-path storage
  - K3s local-path provisioner only supports ReadWriteOnce (RWO) access mode
  - AWX projects volume requires ReadWriteMany (RWX) for simultaneous web and task pod access
  - Caused installation to hang with pods stuck in Pending state indefinitely
- **PostgreSQL Pod Wait Error**: Script tried to wait for PostgreSQL pods before they were created
  - Added wait loop to verify pods exist before checking readiness
  - Prevents "error: no matching resources found" during installation
  - Improved operator reconciliation timing handling

### Changed
- **Projects Persistence Disabled by Default**: Changed from `projects_persistence: true` to `false`
  - Prevents PVC provisioning failures on standard K3s installations
  - Projects now use ephemeral storage (emptyDir) by default
  - Git repositories automatically re-cloned on pod restart (no data loss for Git-backed projects)
  - Suitable for most use cases where projects are version-controlled
- **Configurable Projects Persistence**: Added `PROJECTS_PERSISTENCE` variable to awx.conf
  - Users can enable persistent projects when using NFS or other RWX-capable storage
  - Conditional YAML generation adds storage configuration only when persistence is enabled
  - Clear warnings displayed when persistence is enabled without RWX storage
- **Enhanced Storage Configuration**: Added `PROJECTS_STORAGE_CLASS` variable
  - Allows specifying alternative storage classes (e.g., "nfs-client")
  - Separate from PostgreSQL storage configuration for flexibility

### Added
- **Storage Status Notifications**: Installation script now shows informational messages about storage
  - Indicates when projects persistence is disabled and why
  - Warns users when enabling persistence without verifying storage class capabilities
  - Provides guidance on using NFS for persistent projects
- **Comprehensive Storage Documentation**:
  - New "Storage Considerations" section in README.md explaining RWO vs RWX access modes
  - Storage classes comparison table (local-path, NFS, cloud providers)
  - Impact analysis of ephemeral vs persistent projects storage
  - Instructions for enabling persistent projects storage
- **NFS Setup Guide** in TROUBLESHOOTING.md:
  - Complete step-by-step NFS server installation and configuration
  - NFS client provisioner deployment via Helm in K3s
  - AWX configuration for NFS-backed projects storage
  - Verification steps and troubleshooting for NFS issues
  - Firewall and permission troubleshooting for NFS
- **Storage Troubleshooting Section**: New "Storage Issues" chapter in TROUBLESHOOTING.md
  - "Projects PVC stuck in Pending - ReadWriteMany not supported" diagnostics
  - Root cause analysis and multiple solution paths
  - Disk space troubleshooting and cleanup commands

### Improved
- **Installation Reliability**: AWX instances now deploy successfully on default K3s storage
- **User Experience**: Clear messaging about storage limitations and alternatives
- **Deployment Wait Logic**: Better handling of operator resource creation timing
- **Documentation Completeness**: Users can make informed decisions about storage options

### Technical Details
- Projects ephemeral storage uses Kubernetes emptyDir volumes
- PostgreSQL continues using persistent local-path storage (RWO is sufficient)
- NFS provisioner recommended: `nfs-subdir-external-provisioner` via Helm
- Storage class requirements clearly documented for each component

## [1.1.0] - 2026-02-18

### Added
- **External LAN Access Support**: AWX now accessible from other machines on the local network
  - Firewall automatically opens AWX NodePort (default: 30080) for external connections
  - UFW rule added with comment 'AWX NodePort' for easy identification
  - Works out-of-the-box on local networks without additional configuration
- **AWX Service Verification**: Installation now verifies AWX service creation before completion
  - Added wait loop (5 minutes timeout) for AWX service to be created by operator
  - Prevents script from claiming success when service doesn't exist
  - Displays operator logs and AWX resource status on timeout
  - Improved deployment reliability
- **Enhanced Error Handling**: Better diagnostics when AWX service is not created
  - Validates service exists before retrieving NodePort in display_access_info()
  - Shows available services and diagnostic commands on failure
  - Clear error messages guide users to resolution steps
- **Configuration Integration**: SERVICE_TYPE and NODEPORT variables from awx.conf now respected
  - Previously defined but unused variables are now applied during installation
  - Users can customize port and service type via configuration file
  - Supports future LoadBalancer or ClusterIP configurations
- **Documentation Enhancements**:
  - New "External Access" section in README.md explaining LAN access configuration
  - Verification steps for external connectivity
  - Security considerations for different access scenarios
  - Custom port configuration instructions
  - New troubleshooting entries in TROUBLESHOOTING.md:
    - "AWX service not created" - comprehensive diagnosis for missing service
    - "Cannot access AWX from other machines on network (LAN)" - detailed external access troubleshooting
  - Step-by-step diagnostic commands for network connectivity issues

### Fixed
- **Critical Bug**: Port 30080 was not opened in firewall, blocking all external access
  - UFW rules only opened ports 22, 80, 443, 6443
  - AWX NodePort was configured but unreachable from network
  - Now automatically opens configured NODEPORT in firewall
- **Service Creation Issue**: Installation script didn't verify AWX service was created
  - Script only waited for deployments (awx-web, awx-task) to be available
  - Did not confirm AWX Operator successfully created the service
  - Could exit showing success even when service didn't exist
  - Now waits for and validates service creation with proper timeout handling
- **Silent Failure**: display_access_info() assumed service existed without verification
  - Could fail silently when retrieving NodePort from non-existent service
  - Now validates service exists and shows helpful error message on failure

### Changed
- Firewall configuration message now shows all opened ports including AWX NodePort
- Installation verification process extended to include service creation check
- Access information display updated to mention both local and network access
- Deployment wait time potentially extended by up to 5 minutes for service creation

### Improved
- Installation reliability - won't show false success when AWX isn't accessible
- User experience - clear indication of external access capability
- Troubleshooting - comprehensive diagnostics for service and access issues
- Configuration flexibility - SERVICE_TYPE and NODEPORT settings now functional
- [ ] Air-gapped installation support
- [ ] High availability setup
- [ ] Monitoring integration (Prometheus/Grafana)
- [ ] Automated update mechanism
- [ ] Migration from Docker Compose installations
- [ ] Multi-node K3s cluster support
- [ ] Custom container registry support
- [ ] Pre-flight checks before installation
- [ ] Rollback capability
- [ ] Configuration validation
- [ ] Performance tuning wizard

### Future Enhancements
- [ ] Web-based installer UI
- [ ] Ansible role version
- [ ] Support for other Linux distributions
- [ ] Container image caching
- [ ] Offline installation bundle
- [ ] Integration with cloud providers
- [ ] Terraform module
- [ ] Docker Compose for development
- [ ] Automated scaling recommendations
- [ ] Resource usage predictions

## Version History

### Version 1.0.0 (2026-02-18)
Initial release with core functionality:
- Automated AWX installation on Ubuntu 24.04
- K3s integration
- Basic configuration options
- Comprehensive documentation

---

## Contributing

See something that could be improved? Contributions are welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Review [README.md](README.md)
- Search existing issues
- Create a new issue with details

## License

MIT License - See LICENSE file for details
