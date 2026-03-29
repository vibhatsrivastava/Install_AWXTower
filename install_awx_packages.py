#!/usr/bin/env python3
"""
AWX Package Installer
=====================
Install Python packages inside AWX web and task containers.

This script executes pip install commands inside running AWX pods
using kubectl exec. Packages persist until pods are restarted.

Usage:
    # Install single package in all AWX pods
    python3 install_awx_packages.py requests

    # Install multiple packages
    python3 install_awx_packages.py requests boto3 ansible-pylibssh

    # Install from requirements file
    python3 install_awx_packages.py -r requirements.txt

    # Install only in web pods
    python3 install_awx_packages.py --target web requests

    # Install only in task pods
    python3 install_awx_packages.py --target task boto3

    # Use custom namespace
    python3 install_awx_packages.py --namespace my-awx requests

    # Upgrade existing packages
    python3 install_awx_packages.py --upgrade requests

    # Show installed packages
    python3 install_awx_packages.py --list

Requirements:
    - kubectl configured and accessible
    - Running AWX instance in K3s/Kubernetes cluster
    - Appropriate permissions to exec into pods
"""

import subprocess
import sys
import argparse
import json
from typing import List, Dict, Tuple
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


class AWXPackageInstaller:
    """Manages Python package installation in AWX containers"""

    def __init__(self, namespace: str = "awx", verbose: bool = False):
        """
        Initialize the installer.

        Args:
            namespace: Kubernetes namespace where AWX is installed
            verbose: Enable verbose output
        """
        self.namespace = namespace
        self.verbose = verbose

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

    def run_command(self, cmd: List[str], capture_output: bool = True) -> Tuple[int, str, str]:
        """
        Execute shell command.

        Args:
            cmd: Command and arguments as list
            capture_output: Whether to capture stdout/stderr

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
                timeout=300  # 5 minute timeout
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return 1, "", "Command timed out after 5 minutes"
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

    def get_awx_pods(self, pod_type: str = "all") -> List[Dict[str, str]]:
        """
        Get list of AWX pods.

        Args:
            pod_type: Type of pods to retrieve ('web', 'task', or 'all')

        Returns:
            List of pod dictionaries with 'name' and 'type' keys
        """
        pods = []

        # Get pods based on type
        if pod_type in ("web", "all"):
            returncode, stdout, stderr = self.run_command([
                "kubectl", "get", "pods",
                "-n", self.namespace,
                "-l", "app.kubernetes.io/component=awx",
                "-l", "app.kubernetes.io/name=awx-web",
                "-o", "json"
            ])

            if returncode == 0:
                try:
                    data = json.loads(stdout)
                    for item in data.get("items", []):
                        name = item["metadata"]["name"]
                        status = item["status"]["phase"]
                        if status == "Running":
                            pods.append({"name": name, "type": "web"})
                except json.JSONDecodeError:
                    pass

        if pod_type in ("task", "all"):
            returncode, stdout, stderr = self.run_command([
                "kubectl", "get", "pods",
                "-n", self.namespace,
                "-l", "app.kubernetes.io/component=awx",
                "-l", "app.kubernetes.io/name=awx-task",
                "-o", "json"
            ])

            if returncode == 0:
                try:
                    data = json.loads(stdout)
                    for item in data.get("items", []):
                        name = item["metadata"]["name"]
                        status = item["status"]["phase"]
                        if status == "Running":
                            pods.append({"name": name, "type": "task"})
                except json.JSONDecodeError:
                    pass

        return pods

    def install_packages_in_pod(self, pod_name: str, packages: List[str], 
                                upgrade: bool = False) -> bool:
        """
        Install Python packages in a specific pod.

        Args:
            pod_name: Name of the pod
            packages: List of package names
            upgrade: Whether to upgrade existing packages

        Returns:
            True if successful, False otherwise
        """
        # Build pip install command using python3 -m pip (more reliable in containers)
        pip_cmd = ["python3", "-m", "pip", "install"]
        
        if upgrade:
            pip_cmd.append("--upgrade")
        
        pip_cmd.extend(packages)

        # Execute in pod
        kubectl_cmd = [
            "kubectl", "exec",
            "-n", self.namespace,
            pod_name,
            "--",
            *pip_cmd
        ]

        self.print_info(f"Installing in pod '{pod_name}'...")
        returncode, stdout, stderr = self.run_command(kubectl_cmd)

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

    def list_packages_in_pod(self, pod_name: str):
        """
        List installed packages in a pod.

        Args:
            pod_name: Name of the pod
        """
        kubectl_cmd = [
            "kubectl", "exec",
            "-n", self.namespace,
            pod_name,
            "--",
            "python3", "-m", "pip", "list", "--format", "columns"
        ]

        returncode, stdout, stderr = self.run_command(kubectl_cmd)

        if returncode == 0:
            print(f"\n{Colors.BOLD}Packages in '{pod_name}':{Colors.ENDC}")
            print(stdout)
        else:
            self.print_error(f"Failed to list packages in '{pod_name}'")
            if stderr:
                print(stderr, file=sys.stderr)

    def install_packages(self, packages: List[str], target: str = "all",
                        upgrade: bool = False) -> bool:
        """
        Install packages in AWX pods.

        Args:
            packages: List of package names or paths to requirements files
            target: Target pods ('web', 'task', or 'all')
            upgrade: Whether to upgrade existing packages

        Returns:
            True if all installations succeeded, False otherwise
        """
        self.print_header("AWX Package Installation")

        # Pre-flight checks
        if not self.check_kubectl():
            return False

        if not self.check_namespace():
            return False

        # Get target pods
        self.print_info(f"Finding AWX pods (target: {target})...")
        pods = self.get_awx_pods(target)

        if not pods:
            self.print_error(f"No running AWX pods found in namespace '{self.namespace}'")
            self.print_info("Ensure AWX is deployed and pods are in Running state")
            return False

        self.print_success(f"Found {len(pods)} AWX pod(s)")
        for pod in pods:
            print(f"  • {pod['name']} ({pod['type']})")

        # Install packages in each pod
        print()
        all_successful = True

        for pod in pods:
            success = self.install_packages_in_pod(pod["name"], packages, upgrade)
            if not success:
                all_successful = False

        # Summary
        print()
        if all_successful:
            self.print_success("All package installations completed successfully!")
            self.print_warning("Note: Packages will be lost if pods restart")
            self.print_info("Consider building custom AWX images for persistent packages")
        else:
            self.print_error("Some package installations failed")
            return False

        return True

    def list_packages(self, target: str = "all"):
        """
        List installed packages in AWX pods.

        Args:
            target: Target pods ('web', 'task', or 'all')
        """
        self.print_header("AWX Installed Packages")

        # Pre-flight checks
        if not self.check_kubectl():
            return

        if not self.check_namespace():
            return

        # Get target pods
        pods = self.get_awx_pods(target)

        if not pods:
            self.print_error(f"No running AWX pods found in namespace '{self.namespace}'")
            return

        # List packages in each pod
        for pod in pods:
            self.list_packages_in_pod(pod["name"])


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Install Python packages in AWX containers",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s requests boto3
  %(prog)s -r requirements.txt
  %(prog)s --target web requests
  %(prog)s --namespace my-awx --upgrade ansible
  %(prog)s --list
        """
    )

    parser.add_argument(
        "packages",
        nargs="*",
        help="Python package names to install"
    )

    parser.add_argument(
        "-r", "--requirements",
        metavar="FILE",
        help="Install from requirements file"
    )

    parser.add_argument(
        "-n", "--namespace",
        default="awx",
        help="Kubernetes namespace (default: awx)"
    )

    parser.add_argument(
        "-t", "--target",
        choices=["web", "task", "all"],
        default="all",
        help="Target pods (default: all)"
    )

    parser.add_argument(
        "-u", "--upgrade",
        action="store_true",
        help="Upgrade packages to latest versions"
    )

    parser.add_argument(
        "-l", "--list",
        action="store_true",
        help="List installed packages"
    )

    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose output"
    )

    return parser.parse_args()


def main():
    """Main entry point"""
    args = parse_args()

    # Initialize installer
    installer = AWXPackageInstaller(
        namespace=args.namespace,
        verbose=args.verbose
    )

    # Handle list command
    if args.list:
        installer.list_packages(target=args.target)
        return 0

    # Get packages to install
    packages = []

    if args.requirements:
        req_file = Path(args.requirements)
        if not req_file.exists():
            installer.print_error(f"Requirements file not found: {args.requirements}")
            return 1

        # Read requirements file
        packages.append(f"-r")
        packages.append(str(req_file.absolute()))
        installer.print_info(f"Installing from requirements file: {args.requirements}")
    else:
        packages = args.packages

    if not packages:
        installer.print_error("No packages specified")
        installer.print_info("Use: install_awx_packages.py <package_name> [<package_name> ...]")
        installer.print_info("Or:  install_awx_packages.py -r requirements.txt")
        installer.print_info("Or:  install_awx_packages.py --list")
        return 1

    # Install packages
    success = installer.install_packages(
        packages=packages,
        target=args.target,
        upgrade=args.upgrade
    )

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
