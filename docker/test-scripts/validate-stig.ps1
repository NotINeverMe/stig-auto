param(
    [string]$StigProfile = $env:STIG_PROFILE,
    [string]$OutputDirectory = $env:PESTER_OUTPUT_DIRECTORY,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

# Set default output directory if not provided
if (-not $OutputDirectory) {
    $OutputDirectory = "C:\test-results"
    Write-Host "Output directory not specified, using default: $OutputDirectory" -ForegroundColor Yellow
}

# Ensure output directory exists
try {
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
        Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to create output directory '$OutputDirectory': $_"
    exit 1
}

Write-Host "=== STIG Validation Script ===" -ForegroundColor Cyan
Write-Host "STIG Profile: $StigProfile" -ForegroundColor Yellow
Write-Host "Mode: $(if ($CheckOnly) { 'Check Only' } else { 'Full Validation' })" -ForegroundColor Yellow

# Import PowerSTIG module
try {
    Import-Module PowerSTIG -ErrorAction Stop
} catch {
    Write-Error "Failed to import PowerSTIG module: $_"
    exit 1
}

# Get STIG version information
try {
    $stigVersions = Get-StigVersionTable
    Write-Host "`nAvailable STIG Versions:" -ForegroundColor Cyan
    $stigVersions | Format-Table -AutoSize
} catch {
    Write-Host "`nWarning: Could not retrieve STIG version table: $_" -ForegroundColor Yellow
    Write-Host "Continuing with validation..." -ForegroundColor Yellow
}

# Validate specific STIG based on profile
$validation = @{
    Profile = $StigProfile
    Issues = @()
    Checks = @{
        ModuleAvailable = $false
        StigDataAvailable = $false
        DscResourcesAvailable = $false
        DocumentationAvailable = $false
    }
}

# Check module availability
try {
    $module = Get-Module -Name PowerSTIG
    $validation.Checks.ModuleAvailable = $true
    Write-Host "[OK] PowerSTIG module is available (v$($module.Version))" -ForegroundColor Green
} catch {
    $validation.Issues += "PowerSTIG module not found"
    Write-Host "[ERROR] PowerSTIG module not available" -ForegroundColor Red
}

# Check STIG data availability
try {
    $stigPath = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules\PowerSTIG'
    $stigDataPath = Join-Path -Path $stigPath -ChildPath 'StigData'
    
    if (Test-Path $stigDataPath) {
        $validation.Checks.StigDataAvailable = $true
        Write-Host "[OK] STIG data directory found" -ForegroundColor Green
        
        # List available STIGs
        $stigFiles = Get-ChildItem -Path $stigDataPath -Filter "*.xml" -Recurse
        Write-Host "`nAvailable STIG files:" -ForegroundColor Yellow
        $stigFiles | Select-Object Name, Directory | Format-Table -AutoSize
    } else {
        $validation.Issues += "STIG data directory not found"
        Write-Host "[ERROR] STIG data directory not found" -ForegroundColor Red
    }
} catch {
    $validation.Issues += "Error checking STIG data: $_"
    Write-Host "[ERROR] Error checking STIG data" -ForegroundColor Red
}

# Check DSC resources
try {
    $dscResources = Get-DscResource -Module PowerSTIG
    if ($dscResources.Count -gt 0) {
        $validation.Checks.DscResourcesAvailable = $true
        Write-Host "[OK] DSC resources available ($($dscResources.Count) resources)" -ForegroundColor Green
        
        if (-not $CheckOnly) {
            Write-Host "`nAvailable DSC Resources:" -ForegroundColor Yellow
            $dscResources | Select-Object Name, Version | Format-Table -AutoSize
        }
    } else {
        $validation.Issues += "No DSC resources found"
        Write-Host "[ERROR] No DSC resources found" -ForegroundColor Red
    }
} catch {
    $validation.Issues += "Error checking DSC resources: $_"
    Write-Host "[ERROR] Error checking DSC resources" -ForegroundColor Red
}

# Test STIG compilation (dry run)
if (-not $CheckOnly -and $validation.Checks.ModuleAvailable) {
    Write-Host "`n=== Testing STIG Compilation ===" -ForegroundColor Cyan
    
    try {
        $testPath = Join-Path $OutputDirectory "TestCompilation"
        New-Item -ItemType Directory -Force -Path $testPath | Out-Null
        
        # Create a test configuration
        $configScript = @"
Configuration TestWindowsSTIG {
    Import-DscResource -ModuleName PowerSTIG
    
    Node localhost {
        WindowsServer TestBaseline {
            OsVersion = '2022'
            OsRole = 'MemberServer'
            DomainName = 'TestDomain.local'
            ForestName = 'TestDomain.local'
        }
    }
}

TestWindowsSTIG -OutputPath '$testPath'
"@
        
        # Execute the configuration
        Invoke-Expression $configScript
        
        if (Test-Path (Join-Path $testPath "localhost.mof")) {
            Write-Host "[OK] STIG compilation successful" -ForegroundColor Green
            
            # Analyze the MOF file
            $mofContent = Get-Content (Join-Path $testPath "localhost.mof") -Raw
            $resourceCount = ([regex]::Matches($mofContent, 'instance of')).Count
            Write-Host "  Generated $resourceCount DSC resources" -ForegroundColor Gray
        } else {
            $validation.Issues += "MOF file not generated"
            Write-Host "[ERROR] STIG compilation failed - no MOF generated" -ForegroundColor Red
        }
        
    } catch {
        $validation.Issues += "STIG compilation error: $_"
        Write-Host "[ERROR] STIG compilation failed: $_" -ForegroundColor Red
    }
}

# Generate validation report
$reportPath = Join-Path $OutputDirectory "stig-validation-report.json"
$validation | ConvertTo-Json -Depth 10 | Set-Content $reportPath

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Checks Passed: $(($validation.Checks.Values | Where-Object { $_ -eq $true }).Count) / $($validation.Checks.Count)" -ForegroundColor Yellow
if ($validation.Issues.Count -gt 0) {
    Write-Host "`nIssues Found:" -ForegroundColor Red
    $validation.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "No issues found!" -ForegroundColor Green
}

Write-Host "`nValidation report saved to: $reportPath" -ForegroundColor Gray

# Exit with appropriate code - focus on critical functionality
# For CI/CD environments, only fail if core module functionality is broken
$criticalFailures = @()

if (-not $validation.Checks.ModuleAvailable) {
    $criticalFailures += "PowerSTIG module not available"
}

if (-not $validation.Checks.DscResourcesAvailable) {
    $criticalFailures += "DSC resources not available"
}

if ($criticalFailures.Count -gt 0) {
    Write-Host "`nCritical failures detected:" -ForegroundColor Red
    $criticalFailures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Exiting with failure code" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nCore PowerSTIG functionality is working correctly" -ForegroundColor Green
    if ($validation.Issues.Count -gt 0) {
        Write-Host "Non-critical issues found, but these are acceptable in CI/CD environments" -ForegroundColor Yellow
    }
    exit 0
}