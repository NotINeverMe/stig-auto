# STIG Pipe - Automated STIG Compliance Pipeline

Automated Security Technical Implementation Guide (STIG) remediation pipeline using OpenSCAP scanning and Ansible automation.

## Quick Start

### Run on Linux

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR-ORG/stig-pipe/main/bootstrap.sh | sudo bash
```

### Run on Windows

```powershell
iex (irm https://raw.githubusercontent.com/YOUR-ORG/stig-pipe/main/bootstrap.ps1)
```

## What This Does

1. **Downloads SCAP content** from DoD Cyber Exchange or SCAP Security Guide
2. **Runs baseline scan** using OpenSCAP to identify current compliance status
3. **Executes Ansible remediation** focusing on CAT I and CAT II findings
4. **Verifies remediation** with post-remediation scan

## CAT I/II Focus

This pipeline focuses on Category I (Critical) and Category II (High) findings for maximum security impact with minimal system disruption. Category III findings are excluded to prevent potential operational issues.

- **CAT I**: Critical vulnerabilities that could lead to immediate system compromise
- **CAT II**: High-severity vulnerabilities with significant security impact

## Manual Execution

```bash
# Clone repository
git clone https://github.com/YOUR-ORG/stig-pipe.git
cd stig-pipe

# Install Ansible roles
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/

# Get SCAP content
./scripts/get_scap_content.sh

# Run baseline scan
./scripts/scan.sh --baseline

# Apply remediation
ansible-playbook ansible/remediate.yml -t CAT_I,CAT_II

# Verify results
./scripts/verify.sh
```

## Quarterly Updates

Keep STIG content and remediation roles current:

```bash
git pull
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/ --force
```

## Supported Systems

- RHEL 8
- Ubuntu 22.04
- Windows Server 2022

## Output

Reports are saved in the `reports/` directory:
- `report-baseline-*.html` - Pre-remediation compliance status
- `report-after-*.html` - Post-remediation verification