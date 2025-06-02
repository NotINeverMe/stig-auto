# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

STIG Pipe is an automated Security Technical Implementation Guide (STIG) compliance pipeline that:
- Downloads SCAP content from DoD sources or SCAP Security Guide
- Performs baseline OpenSCAP scans 
- Applies Ansible-based remediation focusing on CAT I/II findings
- Verifies remediation with post-scan validation

## Common Commands

### Testing and Validation
```bash
# Dry run bootstrap (Linux)
sudo bash bootstrap.sh --dry-run

# Test individual components
./scripts/get_scap_content.sh --os rhel-8
./scripts/scan.sh --baseline
ansible-playbook ansible/remediate.yml --check
./scripts/verify.sh
```

```powershell
# Dry run bootstrap (Windows)
.\bootstrap.ps1 -DryRun

# Test individual components
.\scripts\get_scap_content.ps1 -OS windows2022
.\scripts\scan.ps1 -Baseline
.\scripts\verify.ps1
```

### Ansible Operations
```bash
# Install/update roles
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/

# Run remediation with specific tags
ansible-playbook ansible/remediate.yml -t CAT_I
ansible-playbook ansible/remediate.yml -t CAT_II

# Check mode (dry run)
ansible-playbook ansible/remediate.yml --check
```

### Development and CI/CD
```bash
# Run linting
shellcheck $(git ls-files '*.sh')

# Validate Ansible syntax
ansible-playbook ansible/remediate.yml --syntax-check

# Test full pipeline
sudo bash bootstrap.sh --dry-run
```

### Git Operations
```bash
# Tag new releases
git tag v0.x.x
git push origin v0.x.x
```

### Environment Variables
```bash
# Override default STIG profile
export STIG_PROFILE_ID="xccdf_org.ssgproject.content_profile_ospp"
export STIG_PROFILE="ubuntu22"  # For Ansible playbook targeting
```

### Troubleshooting
```bash
# Verify OpenSCAP installation
oscap --version

# Validate SCAP content files
oscap info scap_content/*.xml

# List available profiles in SCAP content
oscap info --profiles scap_content/*.xml

# View recent scan reports
ls -la reports/
find reports -name "*.html" -mtime -1
```

## Architecture

### Bootstrap Flow
1. **bootstrap.sh/ps1**: Entry points that orchestrate the full pipeline
2. **get_scap_content**: Downloads current SCAP content from DoD or GitHub
3. **scan.sh/ps1**: Runs OpenSCAP evaluations with baseline/after modes
4. **ansible/remediate.yml**: Applies role-based STIG remediation 
5. **verify.sh/ps1**: Post-remediation validation and reporting

### Key Directories
- `scripts/`: Cross-platform automation scripts (Linux/Windows)
- `ansible/`: Playbooks and role requirements for remediation
- `roles/`: Ansible Galaxy roles (populated at runtime)
- `reports/`: OpenSCAP scan output (ARF and HTML formats)
- `scap_content/`: Downloaded SCAP XML content files

### Supported STIG Profiles
- RHEL 8 (rhel8-stig role)
- Ubuntu 22.04 (ubuntu22-stig role)  
- Windows Server 2022 (windows2022-stig role)

## Development Notes

- All shell scripts use `set -euo pipefail` for strict error handling
- PowerShell scripts include proper error handling with try/catch
- SCAP content naming follows `<os>-<version>-<yyyy-mm>.xml` pattern
- Reports use timestamp format `yyyymmdd-HHmmss` for uniqueness
- Focus on CAT I/II findings only to balance security and operational stability
