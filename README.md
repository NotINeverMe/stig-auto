# STIG Pipe - Automated STIG Compliance Pipeline

Automated STIG remediation pipeline using OpenSCAP/Ansible (Linux) and PowerSTIG (Windows).

This project is not an official STIG tool. It automates portions of the
scanning and remediation process, but you must manually review the results
for accuracy. Some scripts pull resources from the internet, which may not be
appropriate for all environments, particularly those without online access.

## Platform Support

**Supported Control Nodes:**
- Ubuntu 22.04 / Debian 12 / AlmaLinux 9 (Python 3.10-3.12) ✅ **Recommended**
- Windows 10/11 with WSL2 (Ubuntu 22.04) ✅ **Recommended**
- Native Windows 10/11 ✅ **Full PowerSTIG Support**

**Architecture:**
- **Linux**: OpenSCAP scanning + Ansible remediation
- **Windows**: PowerSTIG (PowerShell DSC) for native STIG compliance

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

### Native Windows (PowerShell as Administrator)

```powershell
# Basic STIG remediation
iex "& { $(irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1) }"

# With additional NIST 800-171 hardening
iex "& { $(irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1) } -WindowsHardening"

# Full hardening mode (includes all security controls)
iex "& { $(irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1) } -WindowsHardening -HardeningMode Full"

# Dry run to preview changes
iex "& { $(irm https://raw.githubusercontent.com/NotINeverMe/stig-auto/main/bootstrap.ps1) } -DryRun"
```

**Installation Locations:**
- **Linux**: `/opt/stig-pipe/` (requires sudo)
- **Windows**: `C:\stig-pipe\` (requires Administrator)

**Windows Features:**
- Uses **PowerSTIG** for native Windows STIG compliance
- No OpenSCAP dependency - pure PowerShell DSC
- Automatic STIG content management
- Native CKL file generation for STIG Viewer
- **NIST 800-171 rev2** compliance hardening modules

## Manual Installation

### Linux

```bash
# Clone repository
sudo git clone https://github.com/NotINeverMe/stig-auto.git /opt/stig-pipe
sudo chown -R $(whoami):$(whoami) /opt/stig-pipe
cd /opt/stig-pipe

# Install dependencies
sudo apt install -y ansible openscap-scanner  # Ubuntu/Debian
# OR
sudo dnf install -y ansible openscap-scanner  # RHEL/CentOS/Rocky

# Install Ansible roles
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/
```

### Windows

```powershell
# Clone repository (PowerShell as Administrator)
git clone https://github.com/NotINeverMe/stig-auto.git C:\stig-pipe
cd C:\stig-pipe

# Install PowerSTIG module
Install-Module -Name PowerSTIG -Scope AllUsers -Force

# Install Ansible (optional, for mixed environments)
python -m pip install 'ansible-core>=2.17,<2.18'
ansible-galaxy install -r ansible\requirements.yml --roles-path roles\
```

## Manual Execution

### Linux

```bash
cd /opt/stig-pipe

# Download SCAP content
./scripts/get_scap_content.sh --os rhel8     # or ubuntu22

# Run baseline scan
./scripts/scan.sh --baseline

# Apply remediation
ansible-playbook ansible/remediate.yml -t CAT_I,CAT_II

# Verify results
./scripts/verify.sh
```

### Windows

```powershell
cd C:\stig-pipe

# Download SCAP content (optional - PowerSTIG handles STIG content automatically)
.\scripts\get_scap_content.ps1 -OS windows2022

# Run baseline scan (uses PowerSTIG)
.\scripts\scan.ps1 -Baseline

# Apply remediation
ansible-playbook ansible\remediate.yml -t CAT_I,CAT_II

# Verify results
.\scripts\verify.ps1
```

## Environment Variables

### Linux (OpenSCAP)
Use `STIG_PROFILE_ID` to override the default OpenSCAP profile:

```bash
STIG_PROFILE_ID=xccdf_org.ssgproject.content_profile_ospp ./scripts/scan.sh --baseline
```

### Windows (PowerSTIG)
Use `STIG_PROFILE` for Ansible integration (automatically detected):

```powershell
# Automatically detected: windows2022, windows2019, windows2016
$env:STIG_PROFILE = 'windows2022'
.\scripts\scan.ps1 -Baseline
```

## Updates

### Linux
```bash
cd /opt/stig-pipe
git pull
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/ --force
```

### Windows
```powershell
cd C:\stig-pipe
git pull
ansible-galaxy install -r ansible\requirements.yml --roles-path roles\ --force
```

## Offline Preparation

### Linux
Stage content on a machine with internet access:

```bash
# Fetch Ansible roles
ansible-galaxy install -r ansible/requirements.yml --roles-path roles/

# Download SCAP content for target OS
./scripts/get_scap_content.sh --os rhel8      # or ubuntu22
```

Transfer `roles/` and `scap_content/` directories to the offline system.

### Windows
```powershell
# Fetch Ansible roles
ansible-galaxy install -r ansible\requirements.yml --roles-path roles\

# Download SCAP content (optional - PowerSTIG downloads STIGs automatically)
.\scripts\get_scap_content.ps1 -OS windows2022

# Pre-download PowerSTIG module
Save-Module -Name PowerSTIG -Path .\offline-modules\
```

Transfer `roles/`, `scap_content/`, and `offline-modules/` directories to the offline system.

## Supported Systems

- RHEL 8
- Ubuntu 22.04
- Windows Server 2022 (`windows2022` profile)
- Windows Server 2019 (`windows2019` profile, PowerSTIG + NIST hardening)
- Windows Server 2016 (`windows2016` profile)

## Windows NIST 800-171 Hardening

Additional hardening module provides comprehensive security controls mapped to NIST 800-171 rev2:

### Security Domains Covered

- **Access Control** (3.1.x): User rights, authentication, RDP security, LAPS
- **Audit & Accountability** (3.3.x): Comprehensive logging, event forwarding, log protection
- **Configuration Management** (3.4.x): Baseline security, least functionality, AppLocker
- **Identification & Authentication** (3.5.x): Password policies, MFA, account management
- **System & Communications Protection** (3.13.x): Encryption, FIPS mode, firewall, protocols
- **System & Information Integrity** (3.14.x): Anti-malware, updates, threat protection

### Direct Usage

```powershell
cd C:\stig-pipe

# Run hardening directly
.\scripts\windows-hardening\Invoke-WindowsHardening.ps1 -Mode Essential

# Or through Ansible
ansible-playbook ansible\remediate.yml -t windows_hardening

# Dry run mode to preview changes
.\scripts\windows-hardening\Invoke-WindowsHardening.ps1 -Mode Essential -DryRun

# Full hardening with all controls
.\scripts\windows-hardening\Invoke-WindowsHardening.ps1 -Mode Full
```

### Hardening Modes

- **Essential**: Core security controls (password policy, firewall, Windows Defender, audit logging)
- **Full**: All controls including BitLocker, AppLocker, advanced threat protection

### Integration with Bootstrap

```powershell
# Automatically includes Windows hardening
.\bootstrap.ps1 -WindowsHardening -HardeningMode Essential

# Full hardening mode
.\bootstrap.ps1 -WindowsHardening -HardeningMode Full
```

## Output

### Linux Reports (`/opt/stig-pipe/reports/`)
- `report-baseline-*.html` - Pre-remediation OpenSCAP compliance status
- `report-after-*.html` - Post-remediation OpenSCAP verification
- `*.xml` - Raw OpenSCAP ARF results

### Windows Reports (`C:\stig-pipe\reports\`)
- `report-baseline-*.html` - Pre-remediation PowerSTIG compliance status  
- `report-after-*.html` - Post-remediation PowerSTIG verification
- `checklist-*.ckl` - DISA STIG Viewer compatible checklist files
- `results-*.json` - Machine-readable compliance results

### Windows Hardening Reports (`C:\stig\`)
- `windows_hardening_report.html` - NIST 800-171 compliance status
- `windows_hardening.log` - Detailed hardening execution log
- `pipeline.log` - Complete bootstrap execution log

## Exit Codes

OpenSCAP returns exit code `2` when one or more rules fail. The `scan.sh` and
`scan.ps1` scripts capture this status and continue running, only exiting if the
code is something other than `0` or `2`.

## License

See [LICENSE](LICENSE) for the proprietary license terms. Usage requires explicit permission from the repository owner.
