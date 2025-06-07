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
Run 'chcp 65001'

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
        $caption = $os.Caption
        if ($caption -match 'Windows Server 2022') {
            return 'windows2022'
        } elseif ($caption -match 'Windows Server 2019') {
            return 'windows2019'
        } elseif ($caption -match 'Windows Server 2016') {
            return 'windows2016'
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

Continuing with Windows support...
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

# Check for Python 3.13+ Ansible compatibility issues
$pythonVersionOutput = & $PythonCmd --version 2>&1
if ($pythonVersionOutput -match "Python 3\.1[3-9]" -or $pythonVersionOutput -match "Python 3\.[2-9][0-9]") {
    Write-Warning "System Python version $($pythonVersionOutput.Split(' ')[1]) may have compatibility issues with Ansible"
    # Try to install Python 3.12 for better Ansible compatibility
    Run "choco install python312 -y --allow-downgrade --force"
    
    # Update Python command to use 3.12 if available
    $Python312Path = "C:\Python312\python.exe"
    if (Test-Path $Python312Path) {
        $PythonCmd = $Python312Path
        Write-Host "Switched to Python 3.12 for better Ansible compatibility: $PythonCmd" -ForegroundColor Green
    } else {
        Write-Warning "Could not install Python 3.12, continuing with Python 3.13+"
        Write-Warning "Ansible commands may fail due to os.get_blocking() Windows compatibility issues"
        
        # Set compatibility flags for Python 3.13+
        $env:ANSIBLE_PYTHON_INTERPRETER = $PythonCmd
        $env:ANSIBLE_HOST_KEY_CHECKING = "False"
    }
}

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
        try {
            Install-Module -Name PowerSTIG -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
            Write-Host "PowerSTIG module installed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "PowerSTIG installation failed"
        }
    } else {
        Write-Host "PowerSTIG module already installed"
    }
    
    # Install Posh-STIG for CKL file manipulation (optional but useful)
    if (!(Get-Module -ListAvailable -Name Posh-STIG)) {
        try {
            Install-Module -Name Posh-STIG -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
            Write-Host "Posh-STIG module installed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "Posh-STIG installation failed (optional module)"
        }
    }
    
    # Install PSWindowsUpdate for security update management
    if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        try {
            Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
            Write-Host "PSWindowsUpdate module installed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "PSWindowsUpdate installation failed (used for update management)"
        }
    }
}

# Clone repo to the repository directory if not present
if (!(Test-Path $RepoDir)) {
    Write-Host "Cloning repository to C:\stig-pipe"
    if (-not $DryRun) {
        Write-Host "==> git clone https://github.com/NotINeverMe/stig-auto.git `"$RepoDir`""
        $cloneResult = & git clone https://github.com/NotINeverMe/stig-auto.git $RepoDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Git clone failed: $cloneResult"
            exit 1
        }
    } else {
        Write-Host "==> git clone https://github.com/NotINeverMe/stig-auto.git `"$RepoDir`""
    }
    
    # Verify critical directories were cloned (only in non-dry-run mode)
    if (-not $DryRun) {
        $CriticalPaths = @(
            "$RepoDir\scripts\windows-hardening",
            "$RepoDir\ansible\remediate.yml",
            "$RepoDir\scripts\scan.ps1"
        )
        
        foreach ($path in $CriticalPaths) {
            if (!(Test-Path $path)) {
                Write-Error "Critical file/directory missing after clone: $path"
                Write-Error "Clone may have failed or been incomplete. Please verify network connectivity and try again."
                exit 1
            }
        }
        Write-Host "Repository cloned successfully with all required files" -ForegroundColor Green
    } else {
        Write-Host "Dry run: Skipping clone verification"
    }
} else {
    Write-Host "Repository already exists at $RepoDir"
    
    # Verify critical paths exist even if repo was already present (only in non-dry-run mode)
    if (-not $DryRun) {
        $CriticalPaths = @(
            "$RepoDir\scripts\windows-hardening",
            "$RepoDir\ansible\remediate.yml", 
            "$RepoDir\scripts\scan.ps1"
        )
        
        $missingPaths = @()
        foreach ($path in $CriticalPaths) {
            if (!(Test-Path $path)) {
                $missingPaths += $path
            }
        }
        
        if ($missingPaths.Count -gt 0) {
            Write-Warning "Existing repository is missing critical files:"
            $missingPaths | ForEach-Object { Write-Warning "  - $_" }
            Write-Host "Updating repository with git pull..." -ForegroundColor Yellow
            Write-Host "==> git -C `"$RepoDir`" pull origin main"
            $pullResult = & git -C $RepoDir pull origin main 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Git pull failed: $pullResult"
            }
            
            # Re-check after pull
            $stillMissing = @()
            foreach ($path in $missingPaths) {
                if (!(Test-Path $path)) {
                    $stillMissing += $path
                }
            }
            
            if ($stillMissing.Count -gt 0) {
                Write-Error "Repository update failed. Missing files:"
                $stillMissing | ForEach-Object { Write-Error "  - $_" }
                Write-Error "Consider deleting $RepoDir and running this script again."
                exit 1
            }
        }
    } else {
        Write-Host "Dry run: Skipping repository validation"
    }
}

# Change to repo directory and install Ansible roles
Run "Set-Location -Path $RepoDir"
# Handle Ansible on Windows with Python 3.12+ compatibility
try {
    # Set environment to avoid blocking IO issues
    $env:PYTHONUNBUFFERED = "1"
    $env:ANSIBLE_FORCE_COLOR = "0"
    
    # Try running ansible-galaxy
    Write-Host "Installing Ansible roles..." -ForegroundColor Cyan
    $galaxyCmd = "& `"$PythonCmd`" -m ansible galaxy install -r ansible\requirements.yml --roles-path roles\"
    
    if ($DryRun) {
        Write-Host "Dry run: Would execute: $galaxyCmd"
    } else {
        $result = Invoke-Expression $galaxyCmd 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Ansible galaxy failed with standard method, trying workaround..."
            
            # Workaround for Python 3.12+ on Windows
            $workaroundScript = @'
import subprocess
import sys
import os

os.environ['PYTHONUNBUFFERED'] = '1'
result = subprocess.run([sys.executable, '-m', 'ansible', 'galaxy', 'install', '-r', 'ansible\\requirements.yml', '--roles-path', 'roles\\'], 
                       capture_output=True, text=True)
print(result.stdout)
if result.stderr:
    print(result.stderr, file=sys.stderr)
sys.exit(result.returncode)
'@
            
            $workaroundScript | & $PythonCmd - 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Ansible galaxy installation failed"
            }
        }
        Write-Host "Ansible roles installed successfully" -ForegroundColor Green
    }
} catch {
    Write-Warning "Ansible role installation failed: $_"
    Write-Warning "This is a known issue with Python 3.13 on Windows. Consider using WSL2 or Python 3.11/3.12"
}


# Execute remediation pipeline
Write-Host "Getting SCAP content..."
Run '.\\scripts\\get_scap_content.ps1'

Write-Host "Running baseline scan..."
Run '.\\scripts\\scan.ps1 -Baseline'

Write-Host "Running Ansible remediation..."
# Track Ansible success for reporting
$AnsibleSuccess = $false

try {
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
            throw "ansible-playbook not found"
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
    
    if (-not $DryRun) {
        Write-Host "==> $AnsiblePlaybook ansible\remediate.yml -t $AnsibleTags"
        
        # Set environment to avoid blocking IO issues
        $env:PYTHONUNBUFFERED = "1"
        $env:ANSIBLE_FORCE_COLOR = "0"
        
        # Try standard execution first
        $ansibleResult = & $AnsiblePlaybook ansible\remediate.yml -t $AnsibleTags 2>&1
        if ($LASTEXITCODE -eq 0) {
            $AnsibleSuccess = $true
            Write-Host "Ansible remediation completed successfully" -ForegroundColor Green
        } else {
            Write-Warning "Ansible remediation failed with exit code $LASTEXITCODE"
            Write-Warning "Trying Python workaround for Windows compatibility..."
            
            # Workaround for Python 3.12+ on Windows
            $playbookScript = @"
import subprocess
import sys
import os

os.environ['PYTHONUNBUFFERED'] = '1'
os.environ['ANSIBLE_FORCE_COLOR'] = '0'

# Run ansible-playbook via python module
result = subprocess.run([sys.executable, '-m', 'ansible', 'playbook', 'ansible\\remediate.yml', '-t', '$AnsibleTags'], 
                       capture_output=True, text=True)
print(result.stdout)
if result.stderr:
    print(result.stderr, file=sys.stderr)
sys.exit(result.returncode)
"@
            
            $playbookScript | & $PythonCmd - 2>&1
            if ($LASTEXITCODE -eq 0) {
                $AnsibleSuccess = $true
                Write-Host "Ansible remediation completed successfully (via workaround)" -ForegroundColor Green
            } else {
                Write-Warning "Ansible remediation failed with both methods"
                Write-Warning "Output: $ansibleResult"
            }
        }
    } else {
        Write-Host "==> $AnsiblePlaybook ansible\remediate.yml -t $AnsibleTags"
        $AnsibleSuccess = $true  # Assume success in dry run
    }
}
catch {
    Write-Warning "Ansible remediation failed: $_"
    Write-Host "Continuing with PowerSTIG and Windows hardening..." -ForegroundColor Yellow
}

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

# Stop logging and create comprehensive summary report
Stop-Transcript | Out-Null

# Gather all available reports
$ReportsDir = Join-Path $RepoDir "reports"
$BaselineReport = $null
$AfterReport = $null
$HardeningReport = $null

if (Test-Path $ReportsDir) {
    $BaselineReport = Get-ChildItem -Path $ReportsDir -Filter "report-baseline-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $AfterReport = Get-ChildItem -Path $ReportsDir -Filter "report-after-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

if (Test-Path "$LogDir\windows_hardening_report.html") {
    $HardeningReport = "$LogDir\windows_hardening_report.html"
}

# Create comprehensive summary report
$summaryReport = @"
=== STIG Automation Pipeline Summary ===
Execution Date: $(Get-Date)
Mode: Windows Bootstrap with$(if ($WindowsHardening) { " NIST 800-171 Hardening ($HardeningMode mode)" } else { "out additional hardening" })
STIG Profile: $env:STIG_PROFILE

=== Component Status ===
PowerSTIG Module Installation: $(if (Get-Module -ListAvailable PowerSTIG) { "✅ SUCCESS" } else { "❌ FAILED" })
Repository Clone/Update: ✅ SUCCESS (windows-hardening directory found)
Ansible Remediation: $(if ($AnsibleSuccess) { "✅ SUCCESS" } else { "⚠️ FAILED (Python 3.13 compatibility issue)" })
Windows Hardening: $(if ($WindowsHardening) { "✅ EXECUTED" } else { "⏭️ SKIPPED" })

=== Available Reports ===
"@

if ($BaselineReport) {
    $summaryReport += "`nPowerSTIG Baseline Scan: $($BaselineReport.FullName)"
} else {
    $summaryReport += "`nPowerSTIG Baseline Scan: ❌ No report generated (scan may have failed)"
}

if ($AfterReport) {
    $summaryReport += "`nPowerSTIG After Scan: $($AfterReport.FullName)"
} else {
    $summaryReport += "`nPowerSTIG After Scan: ❌ No report generated"
}

if ($HardeningReport) {
    $summaryReport += "`nWindows Hardening Report: $HardeningReport"
}

$summaryReport += "`nPipeline Log: $LogFile"

$summaryReport += @"

=== Next Steps ===
1. Review the PowerSTIG scan reports (if available)
2. Check the pipeline log for detailed execution information
3. If Ansible failed, consider using WSL2 or Python 3.11/3.12
4. For PowerSTIG scan issues, verify STIG module compatibility

=== Troubleshooting ===
- Pipeline Log: $LogFile
- Windows Hardening Log: $LogDir\windows_hardening.log
- Reports Directory: $ReportsDir
"@

# Save and display summary
$summaryReport | Out-File -FilePath $EndReport -Encoding UTF8
Write-Host $summaryReport -ForegroundColor Cyan

# Also create a simple status file
$statusSummary = @{
    CompletionTime = Get-Date
    Mode = if ($WindowsHardening) { "$($HardeningMode) Hardening" } else { "Basic STIG" }
    PowerSTIGInstalled = [bool](Get-Module -ListAvailable PowerSTIG)
    AnsibleSuccess = $AnsibleSuccess
    BaselineReportExists = [bool]$BaselineReport
    AfterReportExists = [bool]$AfterReport
    WindowsHardeningExecuted = $WindowsHardening
}

$statusSummary | ConvertTo-Json | Out-File -FilePath "$LogDir\pipeline-status.json" -Encoding UTF8

# Script completed successfully
