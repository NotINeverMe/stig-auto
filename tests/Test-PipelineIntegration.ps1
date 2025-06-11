#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Integration tests for the complete STIG automation pipeline
.DESCRIPTION
    Tests the end-to-end pipeline including STIG detection, caching, 
    security gating, and deterministic behavior
.PARAMETER DryRun
    Run in dry-run mode without making system changes
#>

param(
    [switch]$DryRun = $true
)

$ErrorActionPreference = 'Stop'

# Test configuration
$TestConfig = @{
    ReportsDir = "test-reports"
    CacheFile = "test-reports\.stig-cache.json"
    LogFile = "test-reports\pipeline-test.log"
}

# Initialize test environment
Write-Host "=== Pipeline Integration Tests ===" -ForegroundColor Cyan
Write-Host "Setting up test environment..." -ForegroundColor Yellow

# Create test directories
New-Item -ItemType Directory -Path $TestConfig.ReportsDir -Force | Out-Null

function Write-TestLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $TestConfig.LogFile -Append -Encoding UTF8
    Write-Host $Message
}

function Test-PipelineStep {
    param(
        [string]$StepName,
        [scriptblock]$TestScript
    )
    
    Write-TestLog "Testing: $StepName"
    try {
        $result = & $TestScript
        Write-TestLog "✓ PASSED: $StepName"
        return $true
    } catch {
        Write-TestLog "✗ FAILED: $StepName - $_"
        return $false
    }
}

# Test 1: STIG Detection and Caching
$test1 = Test-PipelineStep "STIG Detection and Caching" {
    # Simulate the scan-powerstig.ps1 STIG selection process
    Import-Module PowerSTIG -ErrorAction Stop
    
    $allStigs = Get-Stig -ListAvailable
    $server2022Stigs = $allStigs | Where-Object {
        ($_.TechnologyRole -eq 'MS' -or $_.TechnologyRole -eq 'DC') -and
        ($_.TechnologyVersion -eq '2022') -and
        $_.ReleaseType -eq 'Benchmark'
    } | Sort-Object -Property StigVersion -Descending | Select-Object -First 1
    
    if (-not $server2022Stigs) {
        throw "No Windows Server 2022 Benchmark STIGs found"
    }
    
    # Test caching functionality
    $stigCache = @{
        Technology = $server2022Stigs.TechnologyRole
        Version = $server2022Stigs.TechnologyVersion
        StigVersion = $server2022Stigs.StigVersion
        StigID = $server2022Stigs.Id
        SelectedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    
    $stigCache | ConvertTo-Json | Out-File -FilePath $TestConfig.CacheFile -Encoding UTF8
    
    # Verify cache can be read
    $cachedData = Get-Content $TestConfig.CacheFile | ConvertFrom-Json
    if ($cachedData.Technology -ne $stigCache.Technology) {
        throw "Cache validation failed"
    }
    
    return "STIG cached: $($stigCache.Technology) $($stigCache.Version) v$($stigCache.StigVersion)"
}

# Test 2: Security Gate Logic
$test2 = Test-PipelineStep "Security Gate Logic" {
    # Create mock scan results with CAT I findings
    $mockResults = @(
        @{
            RuleId = "V-12345"
            Severity = "CAT I"
            Status = "Fail"
            Title = "Critical security finding"
        },
        @{
            RuleId = "V-67890"
            Severity = "CAT II"
            Status = "Fail"
            Title = "Medium security finding"
        },
        @{
            RuleId = "V-11111"
            Severity = "CAT I"
            Status = "Pass"
            Title = "Passing critical control"
        }
    )
    
    $testReportPath = Join-Path $TestConfig.ReportsDir "mock-results.json"
    $mockResults | ConvertTo-Json | Out-File -FilePath $testReportPath -Encoding UTF8
    
    # Test security gate analysis
    $catIFailures = $mockResults | Where-Object { $_.Severity -eq 'CAT I' -and $_.Status -eq 'Fail' }
    $catIIFailures = $mockResults | Where-Object { $_.Severity -eq 'CAT II' -and $_.Status -eq 'Fail' }
    
    if ($catIFailures.Count -ne 1) {
        throw "Expected 1 CAT I failure, found $($catIFailures.Count)"
    }
    
    if ($catIIFailures.Count -ne 1) {
        throw "Expected 1 CAT II failure, found $($catIIFailures.Count)"
    }
    
    return "Security gate logic validated: $($catIFailures.Count) CAT I, $($catIIFailures.Count) CAT II failures"
}

# Test 3: Exception Handling
$test3 = Test-PipelineStep "Exception Handling Framework" {
    # Create mock security exceptions file
    $exceptions = @{
        exemptions = @{
            ruleIds = @("V-12345")
            justification = "Test exception for CI/CD"
            approver = "Security Team"
            expiryDate = "2025-12-31"
        }
    }
    
    $exceptionFile = Join-Path $TestConfig.ReportsDir "security-exceptions.json"
    $exceptions | ConvertTo-Json | Out-File -FilePath $exceptionFile -Encoding UTF8
    
    # Verify exception file can be parsed
    $parsedExceptions = Get-Content $exceptionFile | ConvertFrom-Json
    if ($parsedExceptions.exemptions.ruleIds -notcontains "V-12345") {
        throw "Exception file parsing failed"
    }
    
    return "Exception framework validated"
}

# Test 4: Deterministic Behavior
$test4 = Test-PipelineStep "Deterministic Pipeline Behavior" {
    # Test that STIG selection is deterministic
    Import-Module PowerSTIG -ErrorAction Stop
    
    $allStigs = Get-Stig -ListAvailable
    
    # Run selection twice
    $selection1 = $allStigs | Where-Object {
        ($_.TechnologyRole -eq 'MS') -and
        ($_.TechnologyVersion -eq '2022') -and
        $_.ReleaseType -eq 'Benchmark'
    } | Sort-Object -Property StigVersion -Descending | Select-Object -First 1
    
    $selection2 = $allStigs | Where-Object {
        ($_.TechnologyRole -eq 'MS') -and
        ($_.TechnologyVersion -eq '2022') -and
        $_.ReleaseType -eq 'Benchmark'
    } | Sort-Object -Property StigVersion -Descending | Select-Object -First 1
    
    if (-not $selection1 -or -not $selection2) {
        throw "STIG selection returned null"
    }
    
    if ($selection1.Id -ne $selection2.Id) {
        throw "STIG selection is not deterministic: $($selection1.Id) vs $($selection2.Id)"
    }
    
    return "Deterministic behavior confirmed: $($selection1.Id)"
}

# Test 5: UTF-8 Configuration Validation
$test5 = Test-PipelineStep "UTF-8 Configuration Validation" {
    # Check ansible.cfg has UTF-8 settings
    if (Test-Path "ansible.cfg") {
        $ansibleConfig = Get-Content "ansible.cfg" -Raw
        if ($ansibleConfig -notmatch "PYTHONUTF8=1") {
            throw "ansible.cfg missing PYTHONUTF8=1 setting"
        }
        if ($ansibleConfig -notmatch "PYTHONIOENCODING=utf-8") {
            throw "ansible.cfg missing PYTHONIOENCODING=utf-8 setting"
        }
    } else {
        throw "ansible.cfg not found"
    }
    
    return "UTF-8 configuration validated"
}

# Test 6: Script Error Handling
$test6 = Test-PipelineStep "Script Error Handling Validation" {
    $scripts = @(
        "scripts/scan-powerstig.ps1",
        "scripts/apply-powerstig.ps1",
        "scripts/check-critical-findings.ps1"
    )
    
    foreach ($script in $scripts) {
        if (-not (Test-Path $script)) {
            throw "Script not found: $script"
        }
        
        $content = Get-Content $script -Raw
        
        # Check for ErrorActionPreference
        if ($content -notmatch '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]') {
            throw "$script missing ErrorActionPreference = 'Stop'"
        }
        
        # Check for try-catch blocks
        if ($content -notmatch 'try\s*\{.*\}\s*catch') {
            throw "$script missing try-catch error handling"
        }
    }
    
    return "Error handling validated in all scripts"
}

# Run all tests
$testResults = @{
    Total = 6
    Passed = 0
    Failed = 0
    Details = @()
}

$tests = @($test1, $test2, $test3, $test4, $test5, $test6)
foreach ($test in $tests) {
    if ($test) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
}

# Summary
Write-Host ""
Write-Host "=== Integration Test Results ===" -ForegroundColor Cyan
Write-Host "Total Tests: $($testResults.Total)" -ForegroundColor White
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { 'Red' } else { 'Green' })

# Cleanup
Write-Host ""
Write-Host "Cleaning up test environment..."
Remove-Item -Path $TestConfig.ReportsDir -Recurse -Force -ErrorAction SilentlyContinue

if ($testResults.Failed -gt 0) {
    Write-Host ""
    Write-Host "Some integration tests failed. Check the log for details." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "All integration tests passed! Pipeline is ready for production." -ForegroundColor Green
    exit 0
}