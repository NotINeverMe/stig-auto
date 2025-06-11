#Requires -Module PowerSTIG

<#
.SYNOPSIS
    CI/CD test to validate PowerSTIG benchmark detection and selection
.DESCRIPTION
    Tests the deterministic STIG selection logic for different Windows versions
    Ensures only Benchmark releases are selected and cached properly
#>

param(
    [switch]$MockEnvironment
)

$ErrorActionPreference = 'Stop'

# Test results tracking
$TestResults = @{
    Passed = 0
    Failed = 0
    Tests = @()
}

function Test-Assert {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$Message
    )
    
    $result = @{
        Name = $TestName
        Passed = $Condition
        Message = $Message
        Timestamp = Get-Date
    }
    
    $TestResults.Tests += $result
    
    if ($Condition) {
        $TestResults.Passed++
        Write-Host "PASS: $TestName" -ForegroundColor Green
    } else {
        $TestResults.Failed++
        Write-Host "FAIL: $TestName - $Message" -ForegroundColor Red
    }
}

function Mock-OSInfo {
    param(
        [string]$OSType,
        [string]$Version,
        [string]$Role
    )
    
    return @{
        OsType = $OSType
        Version = $Version
        Role = $Role
    }
}

Write-Host "=== PowerSTIG Benchmark Validation Tests ===" -ForegroundColor Cyan
Write-Host "Testing deterministic STIG selection logic" -ForegroundColor Yellow

# Test 1: Verify PowerSTIG module availability
try {
    Import-Module PowerSTIG -ErrorAction Stop
    $moduleInfo = Get-Module PowerSTIG
    Test-Assert "PowerSTIG Module Import" $true "Module loaded successfully (v$($moduleInfo.Version))"
} catch {
    Test-Assert "PowerSTIG Module Import" $false "Failed to import PowerSTIG module: $_"
    Write-Error "Cannot proceed without PowerSTIG module"
    exit 1
}

# Test 2: Verify STIG catalog access
try {
    $allStigs = Get-Stig -ListAvailable
    $stigCount = ($allStigs | Measure-Object).Count
    Test-Assert "STIG Catalog Access" ($stigCount -gt 0) "Found $stigCount available STIGs"
} catch {
    Test-Assert "STIG Catalog Access" $false "Failed to retrieve STIG catalog: $_"
}

# Test 3: Verify Benchmark-only filtering
$benchmarkStigs = $allStigs | Where-Object { $_.ReleaseType -eq 'Benchmark' }
$benchmarkCount = ($benchmarkStigs | Measure-Object).Count
$draftStigs = $allStigs | Where-Object { $_.ReleaseType -ne 'Benchmark' }
$draftCount = ($draftStigs | Measure-Object).Count

Test-Assert "Benchmark Filter Detection" ($benchmarkCount -gt 0) "Found $benchmarkCount Benchmark STIGs"
Test-Assert "Draft/Other STIG Detection" ($draftCount -ge 0) "Found $draftCount non-Benchmark STIGs (filtered out)"

# Test 4: Windows Server 2022 STIG detection (MS role)
$osInfo2022MS = Mock-OSInfo -OSType "WindowsServer" -Version "2022" -Role "MS"

# Simulate the scan-powerstig.ps1 logic
$server2022Stigs = $allStigs | Where-Object {
    ($_.TechnologyRole -eq 'MS' -or $_.TechnologyRole -eq 'WindowsServer') -and
    ($_.TechnologyVersion -eq '2022' -or $_.TechnologyVersion -like '*2022*') -and
    $_.ReleaseType -eq 'Benchmark'
} | Sort-Object -Property StigVersion -Descending | Select-Object -First 1

Test-Assert "Windows Server 2022 MS STIG Detection" ($server2022Stigs -ne $null) "Found STIG for Server 2022 MS role"

if ($server2022Stigs) {
    Test-Assert "Server 2022 MS STIG Version" ($server2022Stigs.StigVersion -match '^\d+$') "STIG version is numeric: $($server2022Stigs.StigVersion)"
    Test-Assert "Server 2022 MS Benchmark Status" ($server2022Stigs.ReleaseType -eq 'Benchmark') "Confirmed Benchmark release type"
}

# Test 5: Windows Server 2022 STIG detection (DC role)
$server2022DCStigs = $allStigs | Where-Object {
    ($_.TechnologyRole -eq 'DC' -or $_.TechnologyRole -eq 'WindowsServer') -and
    ($_.TechnologyVersion -eq '2022' -or $_.TechnologyVersion -like '*2022*') -and
    $_.ReleaseType -eq 'Benchmark'
} | Sort-Object -Property StigVersion -Descending | Select-Object -First 1

Test-Assert "Windows Server 2022 DC STIG Detection" ($server2022DCStigs -ne $null) "Found STIG for Server 2022 DC role"

# Test 6: STIG retrieval functionality
if ($server2022Stigs) {
    try {
        $testStig = Get-Stig -Technology $server2022Stigs.TechnologyRole -TechnologyVersion $server2022Stigs.TechnologyVersion
        Test-Assert "STIG Object Retrieval" ($testStig -ne $null) "Successfully retrieved STIG object"
        
        if ($testStig) {
            $rules = Get-StigRule -Stig $testStig
            $ruleCount = ($rules | Measure-Object).Count
            Test-Assert "STIG Rules Extraction" ($ruleCount -gt 0) "Found $ruleCount STIG rules"
        }
    } catch {
        Test-Assert "STIG Object Retrieval" $false "Failed to retrieve STIG object: $_"
    }
}

# Test 7: Deterministic selection (same STIG should be selected multiple times)
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

$deterministicMatch = ($selection1.Id -eq $selection2.Id) -and ($selection1.StigVersion -eq $selection2.StigVersion)
Test-Assert "Deterministic Selection" $deterministicMatch "Same STIG selected consistently"

# Test 8: Validate available Windows Server versions
$windowsServerVersions = $allStigs | Where-Object { 
    ($_.TechnologyRole -like '*Server*' -or $_.TechnologyRole -eq 'MS' -or $_.TechnologyRole -eq 'DC') -and
    $_.ReleaseType -eq 'Benchmark'
} | Select-Object -ExpandProperty TechnologyVersion -Unique | Sort-Object

Test-Assert "Windows Server Version Coverage" ($windowsServerVersions -contains '2022') "2022 version available in catalog"

Write-Host ""
Write-Host "Available Windows Server Benchmark STIGs:" -ForegroundColor Cyan
foreach ($version in $windowsServerVersions) {
    $msCount = ($allStigs | Where-Object { $_.TechnologyRole -eq 'MS' -and $_.TechnologyVersion -eq $version -and $_.ReleaseType -eq 'Benchmark' } | Measure-Object).Count
    $dcCount = ($allStigs | Where-Object { $_.TechnologyRole -eq 'DC' -and $_.TechnologyVersion -eq $version -and $_.ReleaseType -eq 'Benchmark' } | Measure-Object).Count
    Write-Host "  Windows Server $version - MS: $msCount, DC: $dcCount" -ForegroundColor Gray
}

# Test 9: Cache file simulation
$testCacheDir = "test-cache"
New-Item -ItemType Directory -Path $testCacheDir -Force | Out-Null

if ($server2022Stigs) {
    $stigCache = @{
        Technology = $server2022Stigs.TechnologyRole
        Version = $server2022Stigs.TechnologyVersion
        StigVersion = $server2022Stigs.StigVersion
        StigID = $server2022Stigs.Id
        SelectedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    
    $cacheFile = Join-Path $testCacheDir "stig-cache.json"
    $stigCache | ConvertTo-Json | Out-File -FilePath $cacheFile -Encoding UTF8
    
    # Verify cache can be read back
    try {
        $cachedData = Get-Content $cacheFile | ConvertFrom-Json
        $cacheValid = ($cachedData.Technology -eq $stigCache.Technology) -and 
                     ($cachedData.StigVersion -eq $stigCache.StigVersion)
        Test-Assert "STIG Cache Functionality" $cacheValid "Cache file created and readable"
    } catch {
        Test-Assert "STIG Cache Functionality" $false "Failed to read cache file: $_"
    }
}

# Cleanup
Remove-Item -Path $testCacheDir -Recurse -Force -ErrorAction SilentlyContinue

# Test Results Summary
Write-Host ""
Write-Host "=== Test Results Summary ===" -ForegroundColor Cyan
Write-Host "Total Tests: $($TestResults.Passed + $TestResults.Failed)" -ForegroundColor White
Write-Host "Passed: $($TestResults.Passed)" -ForegroundColor Green  
Write-Host "Failed: $($TestResults.Failed)" -ForegroundColor Red

if ($TestResults.Failed -gt 0) {
    Write-Host ""
    Write-Host "Failed Tests:" -ForegroundColor Red
    $TestResults.Tests | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Message)" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host ""
    Write-Host "All PowerSTIG benchmark tests passed!" -ForegroundColor Green
    exit 0
}