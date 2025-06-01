# STIG Pipe - Automated STIG Compliance Pipeline

Automated STIG remediation pipeline using OpenSCAP and Ansible.

## Quick Start

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.sh | sudo bash
```

### Windows

```powershell
iex (irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1)
```

## Overview

1. Download SCAP content
2. Run baseline scan
3. Apply CAT I/II remediation
4. Verify results

## Manual Steps

Clone the repo, install roles, fetch SCAP content, then run:

```bash
./scripts/scan.sh --baseline
ansible-playbook ansible/remediate.yml -t CAT_I,CAT_II
./scripts/verify.sh
```

## Updates

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
Reports appear under `reports/` with before and after HTML summaries.

## Exit Codes

OpenSCAP returns exit code `2` when one or more rules fail. The `scan.sh` and
`scan.ps1` scripts capture this status and continue running, only exiting if the
code is something other than `0` or `2`.

## License

See [LICENSE](LICENSE) for the proprietary license terms. Usage requires explicit permission from the repository owner.
