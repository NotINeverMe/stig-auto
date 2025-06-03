<#
.SYNOPSIS
    Comprehensive Windows server hardening module for NIST 800-171 compliance
.DESCRIPTION
    This module implements Windows hardening functions mapped to NIST 800-171 rev2 controls
.PARAMETER Mode
    Specifies the hardening mode: Full, Essential, or Custom
.PARAMETER DryRun
    Performs a dry run without making changes
.EXAMPLE
    .\Invoke-WindowsHardening.ps1 -Mode Full -DryRun
#>

[CmdletBinding()]
param(
    [ValidateSet('Full', 'Essential', 'Custom')]
    [string]$Mode = 'Essential',
    
    [switch]$DryRun,
    
    [string]$LogPath = "C:\Windows\Temp\WindowsHardening.log",
    
    [string]$ReportPath = "C:\Windows\Temp\WindowsHardening_Report.html"
)

# Import required modules
$ErrorActionPreference = 'Stop'
$script:SuccessCount = 0
$script:FailureCount = 0
$script:DryRunMode = $DryRun

# Initialize logging
function Initialize-Logging {
    param([string]$LogFile)
    
    if (-not (Test-Path (Split-Path $LogFile))) {
        New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
    }
    
    $script:LogPath = $LogFile
    Write-HardeningLog "Windows Hardening Script Started - Mode: $Mode, DryRun: $DryRun"
}

function Write-HardeningLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',
        [string]$NistControl = ''
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level]"
    
    if ($NistControl) {
        $logEntry += " [NIST: $NistControl]"
    }
    
    $logEntry += " - $Message"
    
    Add-Content -Path $script:LogPath -Value $logEntry
    
    # Also write to console with color coding
    $color = switch ($Level) {
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
        'Success' { 'Green' }
        default { 'White' }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}

# Helper function for dry run mode
function Invoke-HardeningAction {
    param(
        [scriptblock]$Action,
        [string]$Description,
        [string]$NistControl
    )
    
    if ($script:DryRunMode) {
        Write-HardeningLog "DRY RUN: Would execute - $Description" -Level Info -NistControl $NistControl
        return $true
    }
    
    try {
        & $Action
        Write-HardeningLog "SUCCESS: $Description" -Level Success -NistControl $NistControl
        $script:SuccessCount++
        return $true
    }
    catch {
        Write-HardeningLog "FAILED: $Description - Error: $_" -Level Error -NistControl $NistControl
        $script:FailureCount++
        return $false
    }
}

# Initialize the hardening process
Initialize-Logging -LogFile $LogPath

# Source all hardening function modules
$modulePath = Join-Path $PSScriptRoot "*.psm1"
Get-ChildItem -Path $modulePath | ForEach-Object {
    Write-HardeningLog "Loading module: $($_.Name)"
    Import-Module $_.FullName -Force
}

# Define hardening tasks based on mode
$hardeningTasks = @{
    'Essential' = @(
        @{Function = 'Set-SecureExecutionPolicy'; NistControl = '3.4.2,3.4.6'},
        @{Function = 'Enable-WindowsFirewall'; NistControl = '3.13.1,3.13.5'},
        @{Function = 'Set-PasswordPolicy'; NistControl = '3.5.7,3.5.8'},
        @{Function = 'Disable-LegacyProtocols'; NistControl = '3.13.8,3.13.11'},
        @{Function = 'Enable-AuditLogging'; NistControl = '3.3.1,3.3.2'},
        @{Function = 'Set-FIPSMode'; NistControl = '3.13.11'},
        @{Function = 'Configure-WindowsDefender'; NistControl = '3.14.1,3.14.2'}
    )
    'Full' = @(
        # Include all Essential tasks plus additional ones
        @{Function = 'Install-SecurityUpdates'; NistControl = '3.14.1'},
        @{Function = 'Configure-RDPSecurity'; NistControl = '3.1.13,3.13.5'},
        @{Function = 'Disable-UnnecessaryServices'; NistControl = '3.4.6,3.4.7'},
        @{Function = 'Apply-STIGBaseline'; NistControl = '3.12.1,3.12.2'},
        @{Function = 'Configure-LAPS'; NistControl = '3.5.1,3.5.2'},
        @{Function = 'Enable-DeviceControl'; NistControl = '3.1.19,3.1.20'},
        @{Function = 'Configure-AppLocker'; NistControl = '3.4.8'}
    )
}

# Execute hardening tasks based on mode
if ($Mode -eq 'Essential') {
    $tasksToRun = $hardeningTasks['Essential']
}
elseif ($Mode -eq 'Full') {
    $tasksToRun = $hardeningTasks['Essential'] + $hardeningTasks['Full']
}
else {
    # Custom mode - prompt for specific tasks
    Write-HardeningLog "Custom mode selected. Please use -Functions parameter to specify tasks."
    exit 1
}

# Execute each hardening task
foreach ($task in $tasksToRun) {
    $functionName = $task.Function
    $nistControl = $task.NistControl
    
    Write-HardeningLog "Executing: $functionName" -NistControl $nistControl
    
    if (Get-Command $functionName -ErrorAction SilentlyContinue) {
        & $functionName -DryRun:$DryRun
    }
    else {
        Write-HardeningLog "Function not found: $functionName" -Level Warning
    }
}

# Generate compliance report
Write-HardeningLog "Generating compliance report..."
Export-ComplianceReport -ReportPath $ReportPath -SuccessCount $script:SuccessCount -FailureCount $script:FailureCount

# Summary
$summary = @"
Windows Hardening Completed
Mode: $Mode
Total Tasks: $($script:SuccessCount + $script:FailureCount)
Successful: $script:SuccessCount
Failed: $script:FailureCount
Log File: $LogPath
Report: $ReportPath
"@

Write-HardeningLog $summary
Write-Host $summary -ForegroundColor Cyan