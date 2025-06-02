#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$DryRun
)

function Run {
    param(
        [string]$Command
    )
    if ($DryRun) {
        Write-Host $Command
    } else {
        Invoke-Expression $Command
    }
}

# Determine STIG profile based on Windows version
function Get-StigProfile {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        if ($os.Caption -match 'Windows Server 2022') {
            return 'windows2022'
        }
    } catch {
        # Default to windows2022 if detection fails
    }
    return 'windows2022'
}

$env:STIG_PROFILE = Get-StigProfile
Write-Host "Detected STIG profile: $env:STIG_PROFILE"

if ($DryRun) {
    Write-Host "Dry run mode - commands will be printed only" -ForegroundColor Yellow
}

# Enable WinRM
Run 'Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true'
Run 'Enable-PSRemoting -Force'

# Install Chocolatey if not present
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..."
    Run 'Set-ExecutionPolicy Bypass -Scope Process -Force'
    Run "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072"
    Run 'iex ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))'
}

# Install required packages
Run 'choco install git python openscap-scanner -y'
Run 'refreshenv'
Run 'python -m pip install --upgrade pip'
Run 'python -m pip install ansible'

# Clone repo to C:\stig-pipe if not present
if (!(Test-Path "C:\stig-pipe")) {
    Write-Host "Cloning repository to C:\stig-pipe"
    Run 'git clone https://github.com/NotINeverMe/stig-auto.git "C:\stig-pipe"'
}

# Change to repo directory and install Ansible roles
Run 'Set-Location "C:\stig-pipe"'
Run 'ansible-galaxy install -r ansible\requirements.yml --roles-path roles\'

# Execute remediation pipeline
Write-Host "Getting SCAP content..."
Run '& scripts\get_scap_content.ps1'

Write-Host "Running baseline scan..."
Run '& scripts\scan.ps1 -Baseline'

Write-Host "Running Ansible remediation..."
Run 'ansible-playbook ansible\remediate.yml -t CAT_I,CAT_II'

Write-Host "Verifying remediation..."
Run '& scripts\verify.ps1'

Write-Host "Remediation complete" -ForegroundColor Green
