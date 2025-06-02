# STIG Pipe - Automated STIG Compliance Pipeline

Automated STIG remediation pipeline using OpenSCAP and Ansible.

This project is not an official STIG tool. It automates portions of the
scanning and remediation process, but you must manually review the results
for accuracy. Some scripts pull resources from the internet, which may not be
appropriate for all environments, particularly those without online access.

## Quick Start

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.sh | sudo bash
```

### Windows

```powershell
iex (irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1)
```

The Windows bootstrap script installs **Python 3.11** and uses `pip` to fetch
Ansible, avoiding issues with the older Chocolatey package. The pipeline
requires Python 3.11; using Python 3.13 may result in an `OSError` when running
Ansible.

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
