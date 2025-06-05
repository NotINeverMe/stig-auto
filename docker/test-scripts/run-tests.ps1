param(
    [ValidateSet("all", "unit", "powerstig", "hardening", "integration")]
    [string]$TestType = "all",
    
    [string]$OutputDirectory = $env:PESTER_OUTPUT_DIRECTORY,
    
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Ensure output directory exists
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
}

# Set up logging
$logFile = Join-Path $OutputDirectory "test-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile

Write-Host "=== Windows STIG Docker Test Runner ===" -ForegroundColor Cyan
Write-Host "Test Type: $TestType" -ForegroundColor Yellow
Write-Host "Output Directory: $OutputDirectory" -ForegroundColor Yellow
Write-Host "STIG Profile: $env:STIG_PROFILE" -ForegroundColor Yellow

# Import required modules
try {
    Import-Module PowerSTIG -ErrorAction Stop
    Import-Module Pester -ErrorAction Stop
    Write-Host "Successfully imported required modules" -ForegroundColor Green
} catch {
    Write-Error "Failed to import required modules: $_"
    exit 1
}

# Define test functions
function Test-UnitTests {
    Write-Host "`n=== Running Unit Tests ===" -ForegroundColor Cyan
    
    $config = New-PesterConfiguration
    $config.Run.Path = @("C:\stig-auto\tests\windows")
    $config.Output.Verbosity = if ($Verbose) { "Detailed" } else { "Normal" }
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $OutputDirectory "pester-results.xml"
    $config.TestResult.OutputFormat = "NUnitXml"
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @("C:\stig-auto\scripts\windows-hardening\*.psm1")
    $config.CodeCoverage.OutputPath = Join-Path $OutputDirectory "coverage.xml"
    
    $result = Invoke-Pester -Configuration $config
    
    if ($result.FailedCount -gt 0) {
        Write-Warning "Unit tests failed: $($result.FailedCount) test(s) failed"
        return $false
    }
    
    Write-Host "All unit tests passed!" -ForegroundColor Green
    return $true
}

function Test-PowerSTIG {
    Write-Host "`n=== Running PowerSTIG Tests ===" -ForegroundColor Cyan
    
    try {
        # Test PowerSTIG module availability
        $stigData = Get-StigVersionTable
        Write-Host "PowerSTIG Version: $($stigData.PowerStigVersion)" -ForegroundColor Green
        
        # Test baseline scan in dry-run mode
        Write-Host "Testing PowerSTIG scan functionality..." -ForegroundColor Yellow
        & C:\stig-auto\scripts\scan-powerstig.ps1 -Baseline -WhatIf
        
        # Test DSC compilation
        Write-Host "Testing DSC compilation..." -ForegroundColor Yellow
        $testConfig = @{
            NodeName = 'TestNode'
            Role = 'MemberServer'
            DomainName = 'TestDomain'
            ForestName = 'TestForest'
        }
        
        # This will compile but not apply the configuration
        $null = & {
            Configuration TestSTIG {
                Import-DscResource -ModuleName PowerSTIG
                Node $testConfig.NodeName {
                    WindowsServer BaseLine {
                        OsVersion = '2022'
                        OsRole = $testConfig.Role
                        DomainName = $testConfig.DomainName
                        ForestName = $testConfig.ForestName
                    }
                }
            }
            TestSTIG -OutputPath (Join-Path $OutputDirectory "TestDSC")
        }
        
        Write-Host "PowerSTIG tests completed successfully" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Error "PowerSTIG test failed: $_"
        return $false
    }
}

function Test-HardeningModules {
    Write-Host "`n=== Testing Hardening Modules ===" -ForegroundColor Cyan
    
    $modules = @(
        'AccessControl',
        'AuditLogging',
        'SecurityBaseline',
        'SystemProtection',
        'ComplianceReporting'
    )
    
    $failed = $false
    
    foreach ($module in $modules) {
        try {
            Write-Host "Testing module: $module" -ForegroundColor Yellow
            $modulePath = "C:\stig-auto\scripts\windows-hardening\$module.psm1"
            
            # Import and validate module
            Import-Module $modulePath -Force -ErrorAction Stop
            $moduleInfo = Get-Module $module
            
            if ($moduleInfo) {
                Write-Host "  - Module loaded successfully" -ForegroundColor Green
                Write-Host "  - Exported functions: $($moduleInfo.ExportedFunctions.Count)" -ForegroundColor Gray
                
                # Run module in test mode if available
                if (Get-Command -Module $module -Name "*-Test*" -ErrorAction SilentlyContinue) {
                    Write-Host "  - Running module self-tests..." -ForegroundColor Yellow
                    & "$module\Test-$module" -WhatIf
                }
            }
            
        } catch {
            Write-Error "Failed to test module $module : $_"
            $failed = $true
        }
    }
    
    # Test the main hardening script in dry-run
    try {
        Write-Host "`nTesting main hardening script..." -ForegroundColor Yellow
        & C:\stig-auto\scripts\windows-hardening\Invoke-WindowsHardening.ps1 -WhatIf -Verbose:$Verbose
        Write-Host "Main hardening script test completed" -ForegroundColor Green
    } catch {
        Write-Error "Main hardening script test failed: $_"
        $failed = $true
    }
    
    return -not $failed
}

function Test-Integration {
    Write-Host "`n=== Running Integration Tests ===" -ForegroundColor Cyan
    
    try {
        # Test bootstrap process in dry-run
        Write-Host "Testing bootstrap process..." -ForegroundColor Yellow
        & C:\stig-auto\bootstrap.ps1 -DryRun
        
        # Test Ansible syntax (if Python is available)
        if (Get-Command python -ErrorAction SilentlyContinue) {
            Write-Host "Testing Ansible playbook syntax..." -ForegroundColor Yellow
            python -m ansible.playbook --syntax-check C:\stig-auto\ansible\remediate.yml
        }
        
        Write-Host "Integration tests completed" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Error "Integration test failed: $_"
        return $false
    }
}

# Main test execution
$results = @{
    StartTime = Get-Date
    TestType = $TestType
    Results = @{}
}

$success = $true

switch ($TestType) {
    "unit" {
        $results.Results.Unit = Test-UnitTests
        $success = $results.Results.Unit
    }
    
    "powerstig" {
        $results.Results.PowerSTIG = Test-PowerSTIG
        $success = $results.Results.PowerSTIG
    }
    
    "hardening" {
        $results.Results.Hardening = Test-HardeningModules
        $success = $results.Results.Hardening
    }
    
    "integration" {
        $results.Results.Integration = Test-Integration
        $success = $results.Results.Integration
    }
    
    "all" {
        $results.Results.Unit = Test-UnitTests
        $results.Results.PowerSTIG = Test-PowerSTIG
        $results.Results.Hardening = Test-HardeningModules
        $results.Results.Integration = Test-Integration
        
        $success = $results.Results.Values -notcontains $false
    }
}

# Save results summary
$results.EndTime = Get-Date
$results.Duration = $results.EndTime - $results.StartTime
$results.Success = $success

$resultsPath = Join-Path $OutputDirectory "test-summary.json"
$results | ConvertTo-Json -Depth 10 | Set-Content $resultsPath

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Duration: $($results.Duration.TotalSeconds) seconds" -ForegroundColor Yellow
Write-Host "Overall Result: $(if ($success) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($success) { 'Green' } else { 'Red' })

Stop-Transcript

# Exit with appropriate code
exit $(if ($success) { 0 } else { 1 })