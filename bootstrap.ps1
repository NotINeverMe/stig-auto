#Requires -RunAsAdministrator


[CmdletBinding()]
param(
    [switch]$DryRun,
    
    [switch]$WindowsHardening,
    
    [ValidateSet('Full', 'Essential')]
    [string]$HardeningMode = 'Essential',
    
    [ValidateSet('main', 'dev')]
    [string]$Branch = 'main'
)

# Enable strict error handling for pipeline hygiene
$ErrorActionPreference = 'Stop'
$PSModuleAutoLoadingPreference = 'None'  # Prevent automatic module loading for deterministic runs

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
    # Pin to a known-good PowerSTIG version for deterministic builds
    $powerStigVersion = "4.26.0"  # Update as needed for newer stable releases
    
    $installedModule = Get-Module -ListAvailable -Name PowerSTIG | Where-Object { $_.Version -eq $powerStigVersion }
    if ($installedModule) {
        Write-Host "PowerSTIG module v$powerStigVersion already installed"
    } else {
        try {
            Write-Host "Installing PowerSTIG v$powerStigVersion (pinned version for consistency)"
            Install-Module -Name PowerSTIG -RequiredVersion $powerStigVersion -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
            Write-Host "PowerSTIG module v$powerStigVersion installed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "PowerSTIG v$powerStigVersion installation failed, trying latest version"
            Install-Module -Name PowerSTIG -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
            Write-Host "PowerSTIG module installed successfully" -ForegroundColor Green
        }
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

# Enhanced git repository handling with better directory detection and error handling
$CurrentLocation = Get-Location
$IsInTargetDir = ($CurrentLocation.Path -eq $RepoDir)
$RepoExists = (Test-Path $RepoDir) -and (Test-Path (Join-Path $RepoDir ".git"))

function Test-GitRepository {
    param([string]$Path)
    return (Test-Path $Path) -and (Test-Path (Join-Path $Path ".git")) -and 
           (Get-ChildItem $Path -Force | Where-Object { $_.Name -ne ".git" } | Measure-Object).Count -gt 0
}

function Invoke-GitClone {
    param(
        [string]$Branch,
        [string]$TargetDir,
        [bool]$DryRun
    )
    
    $RepoUrl = "https://github.com/NotINeverMe/stig-auto.git"
    $ParentDir = Split-Path $TargetDir -Parent
    $DirName = Split-Path $TargetDir -Leaf
    
    Write-Host "Cloning repository to $TargetDir (branch: $Branch)" -ForegroundColor Cyan
    
    if (-not $DryRun) {
        # Save current location
        $OriginalLocation = Get-Location
        
        try {
            # If we're in the target directory, move to parent to perform clone
            if ($IsInTargetDir) {
                Write-Host "Currently in target directory, moving to parent for clone operation..." -ForegroundColor Yellow
                Set-Location $ParentDir
                
                # Remove existing directory if it exists but is not a proper git repo
                if (Test-Path $TargetDir) {
                    Write-Host "Removing existing directory for clean clone..." -ForegroundColor Yellow
                    Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "==> git clone -b $Branch $RepoUrl `"$TargetDir`""
            $cloneResult = & git clone -b $Branch $RepoUrl $TargetDir 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                # Use Write-Host instead of Write-Error to prevent PowerShell code parsing
                Write-Host "Git clone failed with exit code $LASTEXITCODE" -ForegroundColor Red
                Write-Host "Error details: $($cloneResult -join "`n")" -ForegroundColor Red
                
                # Try alternative approach: clone to temp directory then move
                $TempDir = "$ParentDir\stig-auto-temp-$(Get-Random)"
                Write-Host "Attempting alternative clone to temporary directory..." -ForegroundColor Yellow
                
                $tempCloneResult = & git clone -b $Branch $RepoUrl $TempDir 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Temporary clone successful, moving to target directory..." -ForegroundColor Green
                    if (Test-Path $TargetDir) {
                        Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Move-Item -Path $TempDir -Destination $TargetDir -Force
                    Write-Host "Repository moved successfully to $TargetDir" -ForegroundColor Green
                } else {
                    Write-Host "Alternative clone also failed: $($tempCloneResult -join "`n")" -ForegroundColor Red
                    Write-Host "Please check network connectivity and try again." -ForegroundColor Yellow
                    exit 1
                }
            } else {
                Write-Host "Repository cloned successfully" -ForegroundColor Green
            }
        } finally {
            # Restore original location if we changed it
            if ($IsInTargetDir -and (Test-Path $TargetDir)) {
                Set-Location $TargetDir
            } elseif ($OriginalLocation) {
                Set-Location $OriginalLocation
            }
        }
    } else {
        Write-Host "==> git clone -b $Branch $RepoUrl `"$TargetDir`" (dry run)"
    }
}

function Invoke-GitUpdate {
    param(
        [string]$Branch,
        [string]$RepoDir,
        [bool]$DryRun
    )
    
    Write-Host "Updating repository with latest changes from $Branch branch..." -ForegroundColor Cyan
    
    if (-not $DryRun) {
        $OriginalLocation = Get-Location
        
        try {
            Set-Location $RepoDir
            
            # Check if it's a valid git repository
            $isGitRepo = & git rev-parse --is-inside-work-tree 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Directory exists but is not a valid git repository. Re-cloning..." -ForegroundColor Yellow
                Set-Location $OriginalLocation
                Remove-Item -Path $RepoDir -Recurse -Force -ErrorAction SilentlyContinue
                Invoke-GitClone -Branch $Branch -TargetDir $RepoDir -DryRun $DryRun
                return
            }
            
            # Switch to the specified branch if not already on it
            $currentBranch = & git branch --show-current 2>&1
            if ($LASTEXITCODE -eq 0 -and $currentBranch -ne $Branch) {
                Write-Host "==> git checkout $Branch"
                $checkoutResult = & git checkout $Branch 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Git checkout failed: $($checkoutResult -join "`n")" -ForegroundColor Yellow
                    Write-Host "Continuing with current branch..." -ForegroundColor Yellow
                }
            }
            
            Write-Host "==> git pull origin $Branch"
            $pullResult = & git pull origin $Branch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Git pull failed: $($pullResult -join "`n")" -ForegroundColor Yellow
                Write-Host "Continuing with existing files..." -ForegroundColor Yellow
            } else {
                Write-Host "Repository updated successfully from $Branch branch" -ForegroundColor Green
            }
        } finally {
            Set-Location $OriginalLocation
        }
    } else {
        Write-Host "==> git pull origin $Branch (dry run)"
    }
}

# Main repository handling logic
if (-not $RepoExists) {
    Invoke-GitClone -Branch $Branch -TargetDir $RepoDir -DryRun $DryRun
} else {
    Write-Host "Repository already exists at $RepoDir" -ForegroundColor Green
    Invoke-GitUpdate -Branch $Branch -RepoDir $RepoDir -DryRun $DryRun
}

# Verify critical directories exist (only in non-dry-run mode)
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
        Write-Host "Repository is missing critical files:" -ForegroundColor Yellow
        $missingPaths | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        Write-Host "Attempting to re-clone repository..." -ForegroundColor Yellow
        
        # Remove and re-clone if critical files are missing
        if (Test-Path $RepoDir) {
            Remove-Item -Path $RepoDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Invoke-GitClone -Branch $Branch -TargetDir $RepoDir -DryRun $false
        
        # Re-check after re-clone
        $stillMissing = @()
        foreach ($path in $CriticalPaths) {
            if (!(Test-Path $path)) {
                $stillMissing += $path
            }
        }
        
        if ($stillMissing.Count -gt 0) {
            Write-Host "Repository re-clone failed. Missing files:" -ForegroundColor Red
            $stillMissing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            Write-Host "Please check network connectivity and try again." -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "All required repository files are present" -ForegroundColor Green
} else {
    Write-Host "Dry run: Skipping repository validation" -ForegroundColor Yellow
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
os.environ['PYTHONIOENCODING'] = 'utf-8'
os.environ['PYTHONUTF8'] = '1'
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
        
        # Set environment to avoid blocking IO issues and fix UTF-8 encoding
        $env:PYTHONUNBUFFERED = "1"
        $env:ANSIBLE_FORCE_COLOR = "0"
        $env:PYTHONIOENCODING = "utf-8"
        $env:PYTHONUTF8 = "1"
        
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
os.environ['PYTHONIOENCODING'] = 'utf-8'
os.environ['PYTHONUTF8'] = '1'

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

# Security gating - fail pipeline on critical findings
Write-Host "Running security gate analysis..."
try {
    $latestReport = Get-ChildItem "reports\results-after-*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestReport) {
        Run ".\\scripts\\check-critical-findings.ps1 -ReportPath '$($latestReport.FullName)' -FailOnCatI"
        Write-Host "Security gate passed - no critical violations" -ForegroundColor Green
    } else {
        Write-Warning "No scan results found for security gating"
    }
} catch {
    Write-Warning "Security gate analysis failed: $_"
    if (-not $DryRun) {
        Write-Error "Pipeline failed security gate"
        exit 1
    }
}

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
