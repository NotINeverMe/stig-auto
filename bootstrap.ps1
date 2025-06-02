#Requires -RunAsAdministrator


[CmdletBinding()]
param(
    [switch]$DryRun
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

Run 'refreshenv'

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
Run "$PythonCmd -m pip install --upgrade pip"
Run "$PythonCmd -m pip install ansible"

# Check for OpenSCAP installation
if (-not $DryRun) {
    if (!(Get-Command oscap.exe -ErrorAction SilentlyContinue)) {
        Write-Warning "oscap.exe not found in PATH. Please install OpenSCAP manually:"
        Write-Warning "1. Download from: https://github.com/OpenSCAP/openscap/releases"
        Write-Warning "2. Or use: winget install OpenSCAP.OpenSCAP"
        Write-Warning "3. Or try: choco install openscap --pre"
        Write-Warning "Continuing without OpenSCAP - scan operations will fail"
    } else {
        $oscPath = (Get-Command oscap.exe).Source
        Write-Host "Using oscap.exe from $oscPath"
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
Run "$AnsiblePlaybook ansible\remediate.yml -t CAT_I,CAT_II"

Write-Host "Verifying remediation..."
Run '.\\scripts\\verify.ps1'

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
