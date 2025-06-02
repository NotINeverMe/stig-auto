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
iex (irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1)
```

**Windows Limitations:**
- Uses ansible-core 2.17.x for compatibility
- Requires aggressive UTF-8 encoding configuration
- May have locale encoding issues
- OpenSCAP installation often fails on Windows

After cloning the repository or running the bootstrap script, install the Ansible roles:

```bash
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/
```

This pulls the STIG roles from the Git repositories specified in `ansible/requirements.yml`.

## Overview

1. Download SCAP content
2. Run baseline scan
3. Apply CAT I/II remediation
4. Verify results

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

## Output

Reports are saved in the `reports/` directory:
- `report-baseline-*.html` - Pre-remediation compliance status
- `report-after-*.html` - Post-remediation verification

## Exit Codes

OpenSCAP returns exit code `2` when one or more rules fail. The `scan.sh` and
`scan.ps1` scripts capture this status and continue running, only exiting if the
code is something other than `0` or `2`.

## License

See [LICENSE](LICENSE) for the proprietary license terms. Usage requires explicit permission from the repository owner.
