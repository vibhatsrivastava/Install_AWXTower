#!/usr/bin/env python3
"""
AWX Collections Installer
==========================
Install Ansible collections inside AWX execution environment containers.

This script executes ansible-galaxy collection install commands inside
execution environment pods using kubectl exec. Collections persist until
pods are restarted.

IMPORTANT: This is for DEVELOPMENT/TESTING only. Collections installed
with this script are EPHEMERAL and will be lost when EE pods restart.
For production, build custom execution environments with collections pre-installed.

Usage:
    # Install single collection
    python3 install_awx_collections.py community.postgresql

    # Install multiple collections
    python3 install_awx_collections.py community.postgresql awx.awx ansible.posix

    # Install from requirements file
    python3 install_awx_collections.py -r collections-requirements.yml

    # Use custom namespace
    python3 install_awx_collections.py --namespace my-awx community.postgresql

    # Upgrade existing collection
    python3 install_awx_collections.py --upgrade community.postgresql

    # List installed collections
    python3 install_awx_collections.py --list

    # Specify execution environment image
    python3 install_awx_collections.py --ee-image quay.io/ansible/awx-ee:latest community.postgresql

Requirements:
    - kubectl configured and accessible
    - Running AWX instance in K3s/Kubernetes cluster
    - Appropriate permissions to exec into pods
"""

import subprocess
import sys
import argparse
import json
import time
import yaml
from typing import List, Tuple, Optional
from pathlib import Path


class Colors:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


class AWXCollectionsInstaller:
    """Manages Ansible collection installation in AWX execution environments"""

    COLLECTIONS_PATH = "/tmp/ansible-collections"
    TEMP_HOME = "/tmp/awx-home"
    ANSIBLE_TMP_DIR = f"{TEMP_HOME}/.ansible/tmp"
    ANSIBLE_CACHE_DIR = f"{TEMP_HOME}/.ansible/galaxy-cache"
    TEMP_DIR = f"{TEMP_HOME}/tmp"

    def __init__(self, namespace: str = "awx", ee_image: Optional[str] = None, verbose: bool = False):
        """
        Initialize the installer.

        Args:
            namespace: Kubernetes namespace where AWX is installed
            ee_image: Execution environment image to use (auto-detected if None)
            verbose: Enable verbose output
        """
        self.namespace = namespace
        self.ee_image = ee_image
        self.verbose = verbose
        self.temp_pod_name = "awx-collections-installer-temp"

    def build_temp_pod_command(self) -> List[str]:
        """Build the temporary pod startup command with writable Ansible paths."""
        return [
            "sh", "-c",
            (
                "mkdir -p "
                f"{self.COLLECTIONS_PATH} "
                f"{self.ANSIBLE_TMP_DIR} "
                f"{self.ANSIBLE_CACHE_DIR} "
                f"{self.TEMP_DIR} "
                "&& sleep 3600"
            )
        ]

    def print_header(self, message: str):
        """Print section header"""
        print(f"\n{Colors.CYAN}{Colors.BOLD}{'=' * 70}{Colors.ENDC}")
        print(f"{Colors.CYAN}{Colors.BOLD}{message}{Colors.ENDC}")
        print(f"{Colors.CYAN}{Colors.BOLD}{'=' * 70}{Colors.ENDC}\n")

    def print_success(self, message: str):
        """Print success message"""
        print(f"{Colors.GREEN}✓ {message}{Colors.ENDC}")

    def print_error(self, message: str):
        """Print error message"""
        print(f"{Colors.RED}✗ {message}{Colors.ENDC}", file=sys.stderr)

    def print_warning(self, message: str):
        """Print warning message"""
        print(f"{Colors.YELLOW}⚠ {message}{Colors.ENDC}")

    def print_info(self, message: str):
        """Print info message"""
        print(f"{Colors.BLUE}ℹ {message}{Colors.ENDC}")

    def run_command(self, cmd: List[str], capture_output: bool = True, timeout: int = 300) -> Tuple[int, str, str]:
        """
        Execute shell command.

        Args:
            cmd: Command and arguments as list
            capture_output: Whether to capture stdout/stderr
            timeout: Command timeout in seconds

        Returns:
            Tuple of (return_code, stdout, stderr)
        """
        if self.verbose:
            self.print_info(f"Executing: {' '.join(cmd)}")

        try:
            result = subprocess.run(
                cmd,
                capture_output=capture_output,
                text=True,
                timeout=timeout
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return 1, "", f"Command timed out after {timeout} seconds"
        except Exception as e:
            return 1, "", str(e)

    def check_kubectl(self) -> bool:
        """Verify kubectl is available"""
        self.print_info("Checking kubectl availability...")
        returncode, stdout, stderr = self.run_command(["kubectl", "version", "--client", "-o", "json"])

        if returncode != 0:
            self.print_error("kubectl not found or not configured")
            self.print_error("Please ensure kubectl is installed and configured")
            return False

        self.print_success("kubectl is available")
        return True

    def check_namespace(self) -> bool:
        """Verify namespace exists"""
        self.print_info(f"Checking namespace '{self.namespace}'...")
        returncode, stdout, stderr = self.run_command(
            ["kubectl", "get", "namespace", self.namespace]
        )

        if returncode != 0:
            self.print_error(f"Namespace '{self.namespace}' not found")
            return False

        self.print_success(f"Namespace '{self.namespace}' exists")
        return True

    def get_default_ee_image(self) -> Optional[str]:
        """
        Get the default execution environment image from AWX instance.

        Returns:
            Image name or None if not found
        """
        self.print_info("Detecting default execution environment image...")
        
        # Try to get the AWX instance spec
        returncode, stdout, stderr = self.run_command([
            "kubectl", "get", "awx",
            "-n", self.namespace,
            "-o", "json"
        ])

        if returncode == 0:
            try:
                data = json.loads(stdout)
                if data.get("items"):
                    # Get first AWX instance
                    spec = data["items"][0].get("spec", {})
                    ee_images = spec.get("ee_images", [])
                    if ee_images:
                        image = ee_images[0].get("image")
                        if image:
                            self.print_success(f"Found EE image: {image}")
                            return image
            except (json.JSONDecodeError, KeyError, IndexError):
                pass

        # Fallback to default AWX EE image
        default_image = "quay.io/ansible/awx-ee:latest"
        self.print_warning(f"Could not detect EE image, using default: {default_image}")
        return default_image

    def create_temp_pod(self) -> bool:
        """
        Create a temporary pod for collection installation.

        Returns:
            True if successful, False otherwise
        """
        # Check if image is specified
        if not self.ee_image:
            self.ee_image = self.get_default_ee_image()
            if not self.ee_image:
                self.print_error("Could not determine execution environment image")
                return False

        self.print_info(f"Creating temporary pod '{self.temp_pod_name}'...")

        # Delete existing pod if present
        self.run_command([
            "kubectl", "delete", "pod",
            "-n", self.namespace,
            self.temp_pod_name,
            "--ignore-not-found=true"
        ])

        # Wait a moment for cleanup
        time.sleep(2)

        # Create pod manifest
        pod_spec = {
            "apiVersion": "v1",
            "kind": "Pod",
            "metadata": {
                "name": self.temp_pod_name,
                "namespace": self.namespace,
                "labels": {
                    "app": "awx-collections-installer"
                }
            },
            "spec": {
                "containers": [{
                    "name": "installer",
                    "image": self.ee_image,
                    "command": self.build_temp_pod_command(),
                    "env": [
                        {
                            "name": "HOME",
                            "value": self.TEMP_HOME
                        },
                        {
                            "name": "TMPDIR",
                            "value": self.TEMP_DIR
                        },
                        {
                            "name": "ANSIBLE_LOCAL_TEMP",
                            "value": self.ANSIBLE_TMP_DIR
                        },
                        {
                            "name": "ANSIBLE_GALAXY_CACHE_DIR",
                            "value": self.ANSIBLE_CACHE_DIR
                        },
                        {
                            "name": "ANSIBLE_COLLECTIONS_PATH",
                            "value": f"{self.COLLECTIONS_PATH}:/usr/share/ansible/collections"
                        }
                    ]
                }],
                "restartPolicy": "Never"
            }
        }

        # Create pod using kubectl apply with manifest on stdin
        try:
            result = subprocess.run(
                ["kubectl", "apply", "-f", "-"],
                input=yaml.safe_dump(pod_spec, sort_keys=False),
                capture_output=True,
                text=True,
                timeout=30
            )
            returncode = result.returncode
            stdout = result.stdout
            stderr = result.stderr
        except Exception as e:
            self.print_error(f"Failed to create pod: {e}")
            return False

        if returncode != 0:
            self.print_error(f"Failed to create temporary pod")
            if stderr:
                print(stderr, file=sys.stderr)
            return False

        # Wait for pod to be running
        self.print_info("Waiting for pod to be ready...")
        for i in range(60):  # Wait up to 60 seconds
            returncode, stdout, stderr = self.run_command([
                "kubectl", "get", "pod",
                "-n", self.namespace,
                self.temp_pod_name,
                "-o", "jsonpath={.status.phase}"
            ])

            if returncode == 0 and stdout.strip() == "Running":
                self.print_success(f"Temporary pod '{self.temp_pod_name}' is ready")
                return True

            time.sleep(1)

        self.print_error(f"Temporary pod did not become ready in time")
        return False

    def delete_temp_pod(self):
        """Delete the temporary pod"""
        self.print_info(f"Cleaning up temporary pod '{self.temp_pod_name}'...")
        self.run_command([
            "kubectl", "delete", "pod",
            "-n", self.namespace,
            self.temp_pod_name,
            "--ignore-not-found=true"
        ])

    def install_collections_in_pod(self, pod_name: str, collections: List[str], 
                                   upgrade: bool = False) -> bool:
        """
        Install Ansible collections in a specific pod.

        Args:
            pod_name: Name of the pod
            collections: List of collection names
            upgrade: Whether to upgrade existing collections

        Returns:
            True if successful, False otherwise
        """
        self.print_info(f"Installing in pod '{pod_name}'...")

        # Build ansible-galaxy command
        galaxy_args = ["collection", "install"]
        if upgrade:
            galaxy_args.append("--upgrade")
        
        # Add force to allow reinstallation
        galaxy_args.append("--force")
        
        # Add collections path
        collections_path = self.COLLECTIONS_PATH
        galaxy_args.extend(["-p", collections_path])
        
        # Add collections
        galaxy_args.extend(collections)

        # Create collections directory
        mkdir_cmd = [
            "kubectl", "exec",
            "-n", self.namespace,
            pod_name,
            "--",
            "mkdir", "-p", collections_path
        ]
        returncode, stdout, stderr = self.run_command(mkdir_cmd)
        if returncode != 0:
            self.print_warning("Could not create collections directory, trying anyway...")

        # Execute ansible-galaxy install command
        kubectl_cmd = [
            "kubectl", "exec",
            "-n", self.namespace,
            pod_name,
            "--",
            "ansible-galaxy"
        ] + galaxy_args

        returncode, stdout, stderr = self.run_command(kubectl_cmd, timeout=600)  # 10 min timeout

        if returncode == 0:
            self.print_success(f"Successfully installed in '{pod_name}'")
            if self.verbose and stdout:
                print(stdout)
            return True
        else:
            self.print_error(f"Failed to install in '{pod_name}'")
            if stderr:
                print(stderr, file=sys.stderr)
            return False

    def install_from_requirements(self, pod_name: str, requirements_file: str, 
                                  upgrade: bool = False) -> bool:
        """
        Install collections from requirements file.

        Args:
            pod_name: Name of the pod
            requirements_file: Path to requirements.yml file
            upgrade: Whether to upgrade existing collections

        Returns:
            True if successful, False otherwise
        """
        # Read requirements file
        requirements_path = Path(requirements_file)
        if not requirements_path.exists():
            self.print_error(f"Requirements file not found: {requirements_file}")
            return False

        try:
            with open(requirements_path, 'r') as f:
                requirements_content = f.read()
        except Exception as e:
            self.print_error(f"Failed to read requirements file: {e}")
            return False

        self.print_info(f"Installing from requirements file '{requirements_file}'...")

        # Copy requirements file to pod
        copy_cmd_stdin = f"cat > /tmp/requirements.yml << 'EOF'\n{requirements_content}\nEOF"
        
        kubectl_cmd = [
            "kubectl", "exec",
            "-n", self.namespace,
            pod_name,
            "--",
            "sh", "-c",
            copy_cmd_stdin
        ]

        returncode, stdout, stderr = self.run_command(kubectl_cmd)
        if returncode != 0:
            self.print_error("Failed to copy requirements file to pod")
            return False

        # Build ansible-galaxy command
        collections_path = self.COLLECTIONS_PATH
        galaxy_args = ["collection", "install", "-r", "/tmp/requirements.yml", "-p", collections_path]
        if upgrade:
            galaxy_args.append("--upgrade")
        galaxy_args.append("--force")

        # Create collections directory
        mkdir_cmd = [
            "kubectl", "exec",
            "-n", self.namespace,
            pod_name,
            "--",
            "mkdir", "-p", collections_path
        ]
        self.run_command(mkdir_cmd)

        # Execute ansible-galaxy install command
        kubectl_cmd = [
            "kubectl", "exec",
            "-n", self.namespace,
            pod_name,
            "--",
            "ansible-galaxy"
        ] + galaxy_args

        returncode, stdout, stderr = self.run_command(kubectl_cmd, timeout=600)  # 10 min timeout

        if returncode == 0:
            self.print_success(f"Successfully installed from requirements file")
            if self.verbose and stdout:
                print(stdout)
            return True
        else:
            self.print_error(f"Failed to install from requirements file")
            if stderr:
                print(stderr, file=sys.stderr)
            return False

    def list_collections(self, pod_name: str):
        """
        List installed collections in a pod.

        Args:
            pod_name: Name of the pod
        """
        self.print_info(f"Listing collections in pod '{pod_name}'...")

        kubectl_cmd = [
            "kubectl", "exec",
            "-n", self.namespace,
            pod_name,
            "--",
            "ansible-galaxy", "collection", "list"
        ]

        returncode, stdout, stderr = self.run_command(kubectl_cmd, capture_output=False)

        if returncode != 0:
            self.print_error(f"Failed to list collections in '{pod_name}'")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Install Ansible collections in AWX execution environments",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Install single collection
  %(prog)s community.postgresql

  # Install multiple collections
  %(prog)s community.postgresql awx.awx ansible.posix

  # Install from requirements file
  %(prog)s -r collections-requirements.yml

  # List installed collections
  %(prog)s --list

  # Use custom namespace
  %(prog)s -n production-awx community.postgresql

WARNING: Collections installed with this script are EPHEMERAL and lost when
         execution environment pods restart. For production, build custom
         execution environments with ansible-builder.
        """
    )

    parser.add_argument(
        "collections",
        nargs="*",
        help="Collection names to install (e.g., community.postgresql awx.awx)"
    )

    parser.add_argument(
        "-r", "--requirements",
        metavar="FILE",
        help="Install from requirements file (collections-requirements.yml format)"
    )

    parser.add_argument(
        "-n", "--namespace",
        default="awx",
        help="AWX namespace (default: awx)"
    )

    parser.add_argument(
        "--ee-image",
        help="Execution environment image to use (auto-detected if not specified)"
    )

    parser.add_argument(
        "-u", "--upgrade",
        action="store_true",
        help="Upgrade collections to latest versions"
    )

    parser.add_argument(
        "-l", "--list",
        action="store_true",
        help="List installed collections"
    )

    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose output"
    )

    args = parser.parse_args()

    # Validate arguments
    if not args.list and not args.requirements and not args.collections:
        parser.error("Please specify collections to install, use -r for requirements file, or --list")

    # Initialize installer
    installer = AWXCollectionsInstaller(
        namespace=args.namespace,
        ee_image=args.ee_image,
        verbose=args.verbose
    )

    installer.print_header("AWX Collections Installation")

    # Pre-flight checks
    if not installer.check_kubectl():
        sys.exit(1)

    if not installer.check_namespace():
        sys.exit(1)

    # Create temporary pod
    if not installer.create_temp_pod():
        sys.exit(1)

    try:
        success = True

        if args.list:
            # List collections
            installer.list_collections(installer.temp_pod_name)
        elif args.requirements:
            # Install from requirements file
            success = installer.install_from_requirements(
                installer.temp_pod_name,
                args.requirements,
                upgrade=args.upgrade
            )
        else:
            # Install specified collections
            success = installer.install_collections_in_pod(
                installer.temp_pod_name,
                args.collections,
                upgrade=args.upgrade
            )

        if success:
            print()
            installer.print_success("Collection installation completed successfully!")
            installer.print_warning("Note: Collections will be lost when execution environment pods restart")
            installer.print_info("For production, build custom execution environments with ansible-builder")
            installer.print_info("See PACKAGE_INSTALLATION.md for detailed instructions")
        else:
            print()
            installer.print_error("Collection installation failed")
            sys.exit(1)

    finally:
        # Cleanup
        print()
        installer.delete_temp_pod()


if __name__ == "__main__":
    main()
