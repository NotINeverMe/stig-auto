#!/usr/bin/env bash

set -euo pipefail

# Parse arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

run_cmd() {
    if $DRY_RUN; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# If running in dry-run mode, create a placeholder reports directory so
# subsequent scripts have an expected location to write to.
if $DRY_RUN; then
    mkdir -p reports
    echo "Placeholder for dry run" > reports/dry-run.txt
fi

# Determine STIG profile based on local OS
detect_stig_profile() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" && "${VERSION_ID%%.*}" == "22" ]]; then
            echo "ubuntu22"
            return
        fi
        if [[ "$ID" =~ ^(rhel|centos|rocky|almalinux) ]] && [[ "${VERSION_ID%%.*}" == "8" ]]; then
            echo "rhel8"
            return
        fi
    fi
    echo "rhel8"
}

# Export STIG profile for Ansible
STIG_PROFILE="$(detect_stig_profile)"
export STIG_PROFILE
echo "Detected STIG profile: $STIG_PROFILE"

# Detect package manager and install dependencies
if command -v apt &> /dev/null; then
    echo "Detected apt package manager"
    run_cmd sudo apt update
    run_cmd sudo apt install -y git curl ansible openscap-scanner
elif command -v dnf &> /dev/null; then
    echo "Detected dnf package manager"
    run_cmd sudo dnf install -y git curl ansible openscap-scanner
elif command -v yum &> /dev/null; then
    echo "Detected yum package manager"
    run_cmd sudo yum install -y git curl ansible openscap-scanner
else
    echo "Error: No supported package manager found (apt, dnf, or yum)"
    exit 1
fi

# Clone repo to /opt/stig-pipe if not already present
if [[ ! -d /opt/stig-pipe ]]; then
    echo "Cloning repository to /opt/stig-pipe"
    run_cmd sudo git clone https://github.com/NotINeverMe/stig-auto.git /opt/stig-pipe
    run_cmd sudo chown -R "$(whoami):$(whoami)" /opt/stig-pipe
    
    # Verify critical directories were cloned
    critical_paths=(
        "/opt/stig-pipe/scripts/windows-hardening"
        "/opt/stig-pipe/ansible/remediate.yml"
        "/opt/stig-pipe/scripts/scan.sh"
    )
    
    for path in "${critical_paths[@]}"; do
        if [[ ! -e "$path" ]]; then
            echo "ERROR: Critical file/directory missing after clone: $path" >&2
            echo "Clone may have failed or been incomplete. Please verify network connectivity and try again." >&2
            exit 1
        fi
    done
    echo "Repository cloned successfully with all required files"
else
    echo "Repository already exists at /opt/stig-pipe"
    
    # Verify critical paths exist even if repo was already present
    critical_paths=(
        "/opt/stig-pipe/scripts/windows-hardening"
        "/opt/stig-pipe/ansible/remediate.yml"
        "/opt/stig-pipe/scripts/scan.sh"
    )
    
    missing_paths=()
    for path in "${critical_paths[@]}"; do
        if [[ ! -e "$path" ]]; then
            missing_paths+=("$path")
        fi
    done
    
    if [[ ${#missing_paths[@]} -gt 0 ]]; then
        echo "WARNING: Existing repository is missing critical files:"
        printf '  - %s\n' "${missing_paths[@]}"
        echo "Updating repository with git pull..."
        run_cmd sudo git -C /opt/stig-pipe pull origin main
        
        # Re-check after pull
        still_missing=()
        for path in "${missing_paths[@]}"; do
            if [[ ! -e "$path" ]]; then
                still_missing+=("$path")
            fi
        done
        
        if [[ ${#still_missing[@]} -gt 0 ]]; then
            echo "ERROR: Repository update failed. Missing files:" >&2
            printf '  - %s\n' "${still_missing[@]}" >&2
            echo "Consider deleting /opt/stig-pipe and running this script again." >&2
            exit 1
        fi
    fi
fi

# Change to repo directory and install Ansible roles
run_cmd cd /opt/stig-pipe
run_cmd ansible-galaxy install -r ansible/requirements.yml --roles-path roles/

# Get SCAP content
echo "Getting SCAP content..."
run_cmd ./scripts/get_scap_content.sh

# Run baseline scan
echo "Running baseline scan..."
run_cmd ./scripts/scan.sh --baseline

# Run Ansible remediation
echo "Running Ansible remediation..."
run_cmd ansible-playbook ansible/remediate.yml -t CAT_I,CAT_II

# Verify remediation
echo "Verifying remediation..."
run_cmd ./scripts/verify.sh

echo "Remediation complete"
