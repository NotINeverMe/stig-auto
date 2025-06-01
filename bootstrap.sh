#!/usr/bin/env bash

set -euo pipefail

# Detect package manager and install dependencies
if command -v apt &> /dev/null; then
    echo "Detected apt package manager"
    sudo apt update
    sudo apt install -y git curl ansible openscap-scanner
elif command -v dnf &> /dev/null; then
    echo "Detected dnf package manager"
    sudo dnf install -y git curl ansible openscap-scanner
elif command -v yum &> /dev/null; then
    echo "Detected yum package manager"
    sudo yum install -y git curl ansible openscap-scanner
else
    echo "Error: No supported package manager found (apt, dnf, or yum)"
    exit 1
fi

# Clone repo to /opt/stig-pipe if not already present
if [[ ! -d /opt/stig-pipe ]]; then
    echo "Cloning repository to /opt/stig-pipe"
    sudo git clone "$(pwd)" /opt/stig-pipe
    sudo chown -R "$(whoami):$(whoami)" /opt/stig-pipe
fi

# Change to repo directory and install Ansible roles
cd /opt/stig-pipe
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/

# Get SCAP content
echo "Getting SCAP content..."
./scripts/get_scap_content.sh

# Run baseline scan
echo "Running baseline scan..."
./scripts/scan.sh --baseline

# Run Ansible remediation
echo "Running Ansible remediation..."
ansible-playbook ansible/remediate.yml -t CAT_I,CAT_II

# Verify remediation
echo "Verifying remediation..."
./scripts/verify.sh

echo "Remediation complete"