#Requires -RunAsAdministrator
#Requires -Module PowerSTIG

<#
.SYNOPSIS
    Apply PowerSTIG DSC configuration and verify compliance
.DESCRIPTION
    This script applies the PowerSTIG DSC configuration and runs compliance tests
.PARAMETER Apply
    Apply the DSC configuration to the system
.PARAMETER Test
    Test the current DSC configuration compliance
.EXAMPLE
    .\apply-powerstig.ps1 -Apply
.EXAMPLE
    .\apply-powerstig.ps1 -Test
#>

param(
    [switch]$Apply,
    [switch]$Test
)

if (-not $Apply -and -not $Test) {
    Write-Host "Usage: .\apply-powerstig.ps1 [-Apply|-Test]"
    Write-Host "  -Apply: Apply DSC configuration to system"
    Write-Host "  -Test:  Test current compliance status"
    exit 1
}

$ErrorActionPreference = 'Stop'

# Import PowerSTIG
try {
    Import-Module PowerSTIG -ErrorAction Stop
} catch {
    Write-Error "PowerSTIG module not found. Please install it first: Install-Module PowerSTIG"
    exit 1
}

# Check for cached STIG selection
$stigCacheFile = "reports\.stig-cache.json"
if (-not (Test-Path $stigCacheFile)) {
    Write-Error "No cached STIG found. Run scan first: .\scripts\scan.ps1 -Baseline"
    exit 1
}

try {
    $cachedStig = Get-Content $stigCacheFile | ConvertFrom-Json
    Write-Host "Using cached STIG: $($cachedStig.Technology) $($cachedStig.Version) v$($cachedStig.StigVersion)" -ForegroundColor Cyan
} catch {
    Write-Error "Failed to read cached STIG configuration"
    exit 1
}

# Get the STIG object
try {
    $stig = Get-Stig -Technology $cachedStig.Technology -TechnologyVersion $cachedStig.Version
    Write-Host "Retrieved STIG configuration successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to retrieve STIG configuration: $_"
    exit 1
}

if ($Apply) {
    Write-Host "Applying PowerSTIG DSC configuration..." -ForegroundColor Yellow
    
    # Create DSC configuration directory
    $dscPath = "C:\StigDSC"
    New-Item -ItemType Directory -Path $dscPath -Force | Out-Null
    
    try {
        # Generate DSC configuration
        Write-Host "Generating DSC configuration..."
        New-StigConfiguration -StigData $stig -Path $dscPath -Verbose
        
        # Apply DSC configuration
        Write-Host "Applying DSC configuration (this may take several minutes)..."
        Start-DscConfiguration -Path $dscPath -Force -Wait -Verbose
        
        Write-Host "DSC configuration applied successfully" -ForegroundColor Green
        
        # Verify LCM status
        $lcmStatus = Get-DscLocalConfigurationManager
        Write-Host "LCM Status: $($lcmStatus.LCMState)" -ForegroundColor Cyan
        
    } catch {
        Write-Error "Failed to apply DSC configuration: $_"
        exit 1
    }
}

if ($Test) {
    Write-Host "Testing DSC configuration compliance..." -ForegroundColor Yellow
    
    try {
        # Test DSC configuration
        $testResults = Test-DscConfiguration -Detailed -ErrorAction SilentlyContinue
        
        if ($testResults) {
            $inDesiredState = $testResults.InDesiredState
            $totalResources = $testResults.ResourcesInDesiredState.Count + $testResults.ResourcesNotInDesiredState.Count
            
            Write-Host ""
            Write-Host "=== DSC Compliance Test Results ===" -ForegroundColor Yellow
            Write-Host "Overall Compliance: $inDesiredState" -ForegroundColor $(if ($inDesiredState) { 'Green' } else { 'Red' })
            Write-Host "Total Resources Tested: $totalResources"
            Write-Host "Resources in Desired State: $($testResults.ResourcesInDesiredState.Count)" -ForegroundColor Green
            Write-Host "Resources NOT in Desired State: $($testResults.ResourcesNotInDesiredState.Count)" -ForegroundColor Red
            
            # Show failed resources
            if ($testResults.ResourcesNotInDesiredState.Count -gt 0) {
                Write-Host ""
                Write-Host "Failed Resources:" -ForegroundColor Red
                foreach ($resource in $testResults.ResourcesNotInDesiredState) {
                    Write-Host "  - $($resource.ResourceId): $($resource.StateChanged)" -ForegroundColor Red
                }
            }
            
            # Generate compliance report
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $reportPath = "reports\dsc-compliance-$timestamp.json"
            $testResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
            Write-Host ""
            Write-Host "Detailed compliance report saved to: $reportPath" -ForegroundColor Cyan
            
        } else {
            Write-Warning "No DSC configuration found to test. Run with -Apply first."
        }
        
    } catch {
        Write-Error "Failed to test DSC configuration: $_"
        exit 1
    }
}

Write-Host "PowerSTIG DSC operation completed successfully" -ForegroundColor Green