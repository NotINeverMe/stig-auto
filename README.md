# STIG Pipe - Automated STIG Compliance Pipeline

Automated STIG remediation pipeline using OpenSCAP and Ansible.

This project is not an official STIG tool. It automates portions of the
scanning and remediation process, but you must manually review the results
for accuracy. Some scripts pull resources from the internet, which may not be
appropriate for all environments, particularly those without online access.

## Platform Support

**Supported Control Nodes:**
- Ubuntu 22.04 / Debian 12 / AlmaLinux 9 (Python 3.10-3.12) ✅ **Recommended**
- Windows 10/11 with WSL2 (Ubuntu 22.04) ✅ **Recommended**
- Native Windows 10/11 ⚠️ **Experimental** (see limitations below)

**Important:** Ansible officially supports Linux/macOS control nodes only. Native Windows support is experimental and may have compatibility issues.

## Quick Start

### Linux/WSL2

```bash
curl -fsSL https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.sh | sudo bash
```

### WSL2 Setup (Recommended for Windows users)

```powershell
# In Windows PowerShell (as Administrator)
wsl --install -d Ubuntu-22.04

# Then in WSL2 Ubuntu
curl -fsSL https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.sh | sudo bash
```

### Native Windows (Experimental)

```powershell
# Basic STIG remediation
iex "& { $(irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1) }"

# With additional NIST 800-171 hardening
iex "& { $(irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1) } -WindowsHardening"

# Full hardening mode (includes all security controls)
iex "& { $(irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1) } -WindowsHardening -HardeningMode Full"
```

**Windows Features:**
- Uses **PowerSTIG** for native Windows STIG compliance
- No OpenSCAP dependency - pure PowerShell DSC
- Automatic STIG content management
- Native CKL file generation for STIG Viewer
- **NEW**: NIST 800-171 rev2 compliance hardening modules

After cloning the repository or running the bootstrap script, install the Ansible roles:

```bash
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/
```

This pulls the STIG roles from the Git repositories specified in `ansible/requirements.yml`.

## Overview

1. Download SCAP content (Linux) / PowerSTIG handles automatically (Windows)
2. Run baseline scan
3. Apply CAT I/II remediation
4. Verify results

### Windows Implementation

On Windows systems, this project uses **PowerSTIG** - Microsoft's official PowerShell DSC module for STIG compliance:

- **Automated STIG Downloads**: PowerSTIG automatically downloads the latest DISA STIGs
- **DSC-based Remediation**: Uses PowerShell Desired State Configuration for consistent enforcement
- **Native Integration**: No compatibility issues like OpenSCAP on Windows
- **CKL Generation**: Creates DISA-compliant checklist files for STIG Viewer

## Manual Steps

Clone the repo, install roles, fetch SCAP content, then run:

```bash
./scripts/get_scap_content.sh [--os rhel8]
./scripts/scan.sh --baseline
ansible-playbook ansible/remediate.yml -t CAT_I,CAT_II
./scripts/verify.sh
```
Use `--os` (Linux) or `-OS` (Windows) to override automatic OS detection when downloading SCAP content.

### Environment Variables

The scanning scripts read the `STIG_PROFILE_ID` environment variable to
determine which OpenSCAP profile to evaluate. When the variable is not set a
default profile for the detected operating system is used.

Example on Linux:

```bash
STIG_PROFILE_ID=xccdf_org.ssgproject.content_profile_ospp ./scripts/scan.sh --baseline
```

Example on Windows:

```powershell
$env:STIG_PROFILE_ID = 'xccdf_org.ssgproject.content_profile_ospp'
./scripts/scan.ps1 -Baseline
```

## Updates

```bash
git pull
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/ --force
```

## Offline Preparation

You can stage content on a machine with internet access and then copy it to an
offline target.

```bash
# Fetch Ansible roles
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/

# Download SCAP content for the desired OS
./scripts/get_scap_content.sh --os rhel8
```

Transfer the `roles/` and `scap_content/` directories to the offline system
before running the pipeline. The `--os` flag tells `get_scap_content.sh` exactly
which content to download.

## Supported Systems

- RHEL 8
- Ubuntu 22.04
- Windows Server 2022
- Windows Server 2019 (PowerSTIG + NIST hardening)

## Windows NIST 800-171 Hardening

The Windows hardening module provides comprehensive security controls mapped to NIST 800-171 rev2:

### Security Domains Covered

- **Access Control** (3.1.x): User rights, authentication, RDP security, LAPS
- **Audit & Accountability** (3.3.x): Comprehensive logging, event forwarding, log protection
- **Configuration Management** (3.4.x): Baseline security, least functionality, AppLocker
- **Identification & Authentication** (3.5.x): Password policies, MFA, account management
- **System & Communications Protection** (3.13.x): Encryption, FIPS mode, firewall, protocols
- **System & Information Integrity** (3.14.x): Anti-malware, updates, threat protection

### Usage

```powershell
# Run hardening directly
.\scripts\windows-hardening\Invoke-WindowsHardening.ps1 -Mode Essential

# Or through Ansible
ansible-playbook ansible\remediate.yml -t windows_hardening

# Dry run mode to preview changes
.\scripts\windows-hardening\Invoke-WindowsHardening.ps1 -Mode Essential -DryRun
```

### Hardening Modes

- **Essential**: Core security controls (password policy, firewall, Windows Defender, audit logging)
- **Full**: All controls including BitLocker, AppLocker, advanced threat protection

## Output

Reports are saved in the `reports/` directory:
- `report-baseline-*.html` - Pre-remediation compliance status
- `report-after-*.html` - Post-remediation verification
- `windows_hardening_report.html` - NIST 800-171 compliance status (when using -WindowsHardening)

## Exit Codes

OpenSCAP returns exit code `2` when one or more rules fail. The `scan.sh` and
`scan.ps1` scripts capture this status and continue running, only exiting if the
code is something other than `0` or `2`.

## License

See [LICENSE](LICENSE) for the proprietary license terms. Usage requires explicit permission from the repository owner.
