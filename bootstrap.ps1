#Requires -RunAsAdministrator


[CmdletBinding()]
param(
    [switch]$DryRun,
    
    [switch]$WindowsHardening,
    
    [ValidateSet('Full', 'Essential')]
    [string]$HardeningMode = 'Essential'
)

# Directory for pipeline logs and summary report
$LogDir = "C:\stig"
$LogFile = Join-Path $LogDir "pipeline.log"
$EndReport = Join-Path $LogDir "end_report.txt"
# Repository directory used throughout the script
$RepoDir = "C:\stig-pipe"
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

function Run {
    param(
        [string]$Command
    )
    Write-Host "==> $Command"
    if (-not $DryRun) {
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

# Preflight check for Windows compatibility
if ($PSVersionTable.PSEdition -eq 'Desktop' -and -not $env:WSL_DISTRO_NAME) {
    Write-Warning @"
WARNING: You are running on native Windows PowerShell.
Ansible control nodes are officially supported on Linux/macOS only.
For best results, consider using WSL2 (Ubuntu 22.04):
  wsl --install -d Ubuntu-22.04
  
Continuing with experimental Windows support...
"@
}

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
Run 'choco install git -y'
# Note: OpenSCAP Chocolatey package currently has issues, will install manually if needed
Run 'choco install python -y --allow-downgrade'

Run 'Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1; Update-SessionEnvironment'

# Find Python installation dynamically, preferring Ansible-compatible versions
$PythonCmd = $null

# First try specific Python versions that are known to work well with Ansible
$PreferredPaths = @('C:\\Python312\\python.exe', 'C:\\Python311\\python.exe')
foreach ($Path in $PreferredPaths) {
    if (Test-Path $Path) {
        $PythonCmd = $Path
        Write-Host "Using preferred Python installation: $PythonCmd"
        break
    }
}

# If no preferred version found, try common commands
if (-not $PythonCmd) {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $PythonVersion = (python --version 2>&1) -replace 'Python ', ''
        if ($PythonVersion -like '3.11.*' -or $PythonVersion -like '3.12.*') {
            $PythonCmd = 'python'
            Write-Host "Using system Python (compatible version): $PythonVersion"
        } else {
            Write-Warning "System Python version $PythonVersion may have compatibility issues with Ansible"
            $PythonCmd = 'python'
        }
    } elseif (Get-Command py -ErrorAction SilentlyContinue) {
        $PythonCmd = 'py'
    } else {
        # Try any available Python installation as last resort
        $AllPaths = @('C:\\Python313\\python.exe', 'C:\\Python314\\python.exe')
        foreach ($Path in $AllPaths) {
            if (Test-Path $Path) {
                $PythonCmd = $Path
                Write-Warning "Using Python 3.13+ which may have Ansible compatibility issues: $PythonCmd"
                break
            }
        }
    }
}

if (-not $PythonCmd) {
    Write-Error "Python installation not found"
    exit 1
}

Write-Host "Using Python: $PythonCmd"

# Force UTF-8 encoding for Ansible compatibility on Windows
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
$env:LC_ALL = "C.UTF-8"
$env:LANG = "C.UTF-8"
$env:ANSIBLE_STDOUT_CALLBACK = "minimal"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Run "$PythonCmd -m pip install --upgrade pip"
Run "$PythonCmd -m pip install 'ansible-core>=2.17,<2.18'"

# Install PowerSTIG module for Windows STIG compliance
Write-Host "Installing PowerSTIG module for native Windows STIG compliance..." -ForegroundColor Cyan
if (-not $DryRun) {
    # Install PowerSTIG from PowerShell Gallery
    if (!(Get-Module -ListAvailable -Name PowerSTIG)) {
        Install-Module -Name PowerSTIG -Scope AllUsers -Force -AllowClobber
        Write-Host "PowerSTIG module installed successfully" -ForegroundColor Green
    } else {
        Write-Host "PowerSTIG module already installed"
    }
    
    # Install Posh-STIG for CKL file manipulation (optional but useful)
    if (!(Get-Module -ListAvailable -Name Posh-STIG)) {
        try {
            Install-Module -Name Posh-STIG -Scope AllUsers -Force -AllowClobber
            Write-Host "Posh-STIG module installed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "Posh-STIG installation failed (optional module)"
        }
    }
    
    # Install PSWindowsUpdate for security update management
    if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        try {
            Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force -AllowClobber
            Write-Host "PSWindowsUpdate module installed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "PSWindowsUpdate installation failed (used for update management)"
        }
    }
}

# Clone repo to the repository directory if not present
if (!(Test-Path $RepoDir)) {
    Write-Host "Cloning repository to C:\stig-pipe"
    Run "git clone https://github.com/NotINeverMe/stig-auto.git \"$RepoDir\""
}

# Change to repo directory and install Ansible roles
Run "Set-Location -Path $RepoDir"
Run 'ansible-galaxy install -r ansible\requirements.yml --roles-path roles\'


# Execute remediation pipeline
Write-Host "Getting SCAP content..."
Run '.\\scripts\\get_scap_content.ps1'

Write-Host "Running baseline scan..."
Run '.\\scripts\\scan.ps1 -Baseline'

Write-Host "Running Ansible remediation..."
# Use dynamic Python path for ansible-playbook
$AnsiblePlaybook = $null
if (Get-Command ansible-playbook -ErrorAction SilentlyContinue) {
    $AnsiblePlaybook = 'ansible-playbook'
} else {
    # Try to find ansible-playbook in Python Scripts directory
    if ($PythonCmd -and ($PythonCmd -like "*\*" -or $PythonCmd -like "*:*")) {
        # Full path provided
        $PythonDir = Split-Path $PythonCmd -Parent
        $ScriptsDir = Join-Path $PythonDir "Scripts"
        $AnsiblePath = Join-Path $ScriptsDir "ansible-playbook.exe"
        if (Test-Path $AnsiblePath) {
            $AnsiblePlaybook = $AnsiblePath
        }
    } else {
        # Command name only, try to find the full path
        $PythonFullPath = (Get-Command $PythonCmd -ErrorAction SilentlyContinue).Source
        if ($PythonFullPath) {
            $PythonDir = Split-Path $PythonFullPath -Parent
            $ScriptsDir = Join-Path $PythonDir "Scripts"
            $AnsiblePath = Join-Path $ScriptsDir "ansible-playbook.exe"
            if (Test-Path $AnsiblePath) {
                $AnsiblePlaybook = $AnsiblePath
            }
        }
    }
    
    if (-not $AnsiblePlaybook -and -not $DryRun) {
        Write-Error "ansible-playbook not found"
        exit 1
    } elseif (-not $AnsiblePlaybook -and $DryRun) {
        $AnsiblePlaybook = "ansible-playbook"
        Write-Host "Note: ansible-playbook not found, using placeholder for dry run"
    }
}

# Add tags for Windows hardening if requested
$AnsibleTags = "CAT_I,CAT_II"
if ($WindowsHardening) {
    $AnsibleTags += ",windows_hardening,nist_compliance"
}
Run "$AnsiblePlaybook ansible\remediate.yml -t $AnsibleTags"

Write-Host "Verifying remediation..."
Run '.\\scripts\\verify.ps1'

# Optional: Run standalone Windows hardening
if ($WindowsHardening) {
    Write-Host "Running additional Windows hardening for NIST 800-171 compliance..." -ForegroundColor Cyan
    
    # Copy hardening modules to PowerShell modules directory
    $ModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules\WindowsHardening"
    if (-not (Test-Path $ModulePath)) {
        Run "New-Item -ItemType Directory -Path '$ModulePath' -Force"
    }
    Run "Copy-Item -Path '.\scripts\windows-hardening\*.psm1' -Destination '$ModulePath' -Force"
    
    # Execute hardening script
    $HardeningParams = @{
        Mode = $HardeningMode
        DryRun = $DryRun
        LogPath = Join-Path $LogDir "windows_hardening.log"
        ReportPath = Join-Path $LogDir "windows_hardening_report.html"
    }
    
    if (-not $DryRun) {
        & ".\scripts\windows-hardening\Invoke-WindowsHardening.ps1" @HardeningParams
    } else {
        Write-Host "Would execute: .\scripts\windows-hardening\Invoke-WindowsHardening.ps1 -Mode $HardeningMode -DryRun"
    }
}

Write-Host "Remediation complete" -ForegroundColor Green

# Stop logging and create summary report
Stop-Transcript | Out-Null
$ReportsDir = Join-Path $RepoDir "reports"
$BaselineReport = $null
$AfterReport = $null
if (Test-Path $ReportsDir) {
    $BaselineReport = Get-ChildItem -Path $ReportsDir -Filter "report-baseline-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $AfterReport = Get-ChildItem -Path $ReportsDir -Filter "report-after-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
"Remediation completed $(Get-Date)" | Out-File -FilePath $EndReport
if ($BaselineReport) { "Baseline report: $($BaselineReport.FullName)" | Out-File -FilePath $EndReport -Append }
if ($AfterReport) { "After remediation report: $($AfterReport.FullName)" | Out-File -FilePath $EndReport -Append }
