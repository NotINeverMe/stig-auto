#Requires -RunAsAdministrator
#Requires -Module PowerSTIG

param(
    [switch]$Baseline,
    [switch]$After
)

if (-not $Baseline -and -not $After) {
    Write-Host "Usage: .\scan-powerstig.ps1 [-Baseline|-After]"
    Write-Host "  -Baseline: Run baseline scan before remediation"
    Write-Host "  -After:    Run scan after remediation"
    exit 1
}

$Mode = if ($Baseline) { "baseline" } else { "after" }

# Import PowerSTIG
try {
    Import-Module PowerSTIG -ErrorAction Stop
} catch {
    Write-Error "PowerSTIG module not found. Please install it first: Install-Module PowerSTIG"
    exit 1
}

# Determine OS and STIG version with role detection
function Get-OSInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $caption = $os.Caption
    
    # Detect server role (DC vs MS)
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $isDomainController = ($env:COMPUTERNAME -like '*DC*') -or ($computerSystem.DomainRole -ge 4)
    $role = if ($isDomainController) { 'DC' } else { 'MS' }
    
    if ($caption -match 'Windows 10') {
        return @{ OsType = 'WindowsClient'; Version = '10.0'; Role = $null }
    } elseif ($caption -match 'Windows 11') {
        return @{ OsType = 'WindowsClient'; Version = '11.0'; Role = $null }
    } elseif ($caption -match 'Windows Server 2022') {
        return @{ OsType = 'WindowsServer'; Version = '2022'; Role = $role }
    } elseif ($caption -match 'Windows Server 2019') {
        return @{ OsType = 'WindowsServer'; Version = '2019'; Role = $role }
    } elseif ($caption -match 'Windows Server 2016') {
        return @{ OsType = 'WindowsServer'; Version = '2016'; Role = $role }
    } else {
        throw "Unsupported OS: $caption"
    }
}

$osInfo = Get-OSInfo
Write-Host "Detected OS: $($osInfo.OsType) $($osInfo.Version) Role: $($osInfo.Role)"

# Check for cached STIG selection
$stigCacheFile = "reports\.stig-cache.json"
$cachedStig = $null
if (Test-Path $stigCacheFile) {
    try {
        $cachedStig = Get-Content $stigCacheFile | ConvertFrom-Json
        Write-Host "Found cached STIG selection: $($cachedStig.Technology) $($cachedStig.Version) v$($cachedStig.StigVersion)" -ForegroundColor Cyan
    } catch {
        Write-Host "Cached STIG file corrupted, will re-select" -ForegroundColor Yellow
    }
}

# Create reports directory
New-Item -ItemType Directory -Force -Path "reports" | Out-Null

# Generate timestamp for unique filenames
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "Running $Mode scan using PowerSTIG..."

try {
    # Debug: List all available STIGs
    Write-Host "Available PowerSTIG modules:" -ForegroundColor Yellow
    $allStigs = Get-Stig -ListAvailable
    $allStigs | ForEach-Object { 
        Write-Host "  - $($_.TechnologyRole) $($_.TechnologyVersion) (STIG v$($_.StigVersion))" -ForegroundColor Gray
    }
    
    # Get available STIG with flexible matching
    # First try exact match - filter for Benchmark releases only
    $availableStigs = $allStigs | Where-Object {
        $_.TechnologyRole -eq $osInfo.OsType -and 
        ($_.TechnologyVersion -eq $osInfo.Version -or 
         $_.TechnologyVersion -eq $osInfo.Version.ToString() -or
         $_.TechnologyVersion -like "*$($osInfo.Version)*") -and
        $_.ReleaseType -eq 'Benchmark'  # Only use official benchmark releases
    } | Sort-Object -Property StigVersion -Descending | Select-Object -First 1
    
    # If no exact match for Windows Server 2022, try various naming conventions
    if (-not $availableStigs -and $osInfo.Version -eq '2022') {
        Write-Host "Trying alternative naming conventions for Windows Server 2022..." -ForegroundColor Yellow
        
        # Try different variations including MS (Member Server) and DC (Domain Controller)
        # Prioritize detected role first
        $searchPatterns = if ($osInfo.Role) {
            @($osInfo.Role, 'MS', 'DC', '2022', 'Server2022', 'Server 2022', 'WS2022', 'WindowsServer2022')
        } else {
            @('MS', 'DC', '2022', 'Server2022', 'Server 2022', 'WS2022', 'WindowsServer2022')
        }
        foreach ($pattern in $searchPatterns) {
            $availableStigs = $allStigs | Where-Object {
                ($_.TechnologyRole -like '*Server*' -or $_.TechnologyRole -eq 'WindowsServer' -or $_.TechnologyRole -eq 'MS' -or $_.TechnologyRole -eq 'DC') -and
                ($_.TechnologyVersion -like "*$pattern*" -or $_.TechnologyVersion -eq '2022' -or $_.Title -like "*$pattern*") -and
                $_.ReleaseType -eq 'Benchmark'  # Only use official benchmark releases
            } | Sort-Object -Property StigVersion -Descending | Select-Object -First 1
            
            if ($availableStigs) {
                Write-Host "Found STIG using pattern: $pattern - $($availableStigs.TechnologyRole) $($availableStigs.TechnologyVersion)" -ForegroundColor Green
                break
            }
        }
    }
    
    # If still no match, try looking for any Windows Server STIG
    if (-not $availableStigs -and $osInfo.OsType -eq 'WindowsServer') {
        Write-Host "No exact version match, trying any Windows Server STIG..." -ForegroundColor Yellow
        $availableStigs = $allStigs | Where-Object {
            $_.TechnologyRole -like '*Server*' -or $_.TechnologyRole -eq 'WindowsServer'
        } | Sort-Object -Property StigVersion -Descending | Select-Object -First 1
    }
    
    if (-not $availableStigs) {
        Write-Warning "No STIG found for $($osInfo.OsType) $($osInfo.Version)"
        Write-Host "Available STIG technologies:" -ForegroundColor Yellow
        $allStigs | Group-Object TechnologyRole | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Group.TechnologyVersion -join ', ')" -ForegroundColor Gray
        }
        throw "No compatible STIG found for $($osInfo.OsType) $($osInfo.Version)"
    }
    
    Write-Host "Using STIG: $($availableStigs.Title) v$($availableStigs.StigVersion)"
    
    # Cache the STIG selection for deterministic future runs
    $stigCache = @{
        Technology = $availableStigs.TechnologyRole
        Version = $availableStigs.TechnologyVersion
        StigVersion = $availableStigs.StigVersion
        StigID = $availableStigs.Id
        SelectedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    $stigCache | ConvertTo-Json | Out-File -FilePath $stigCacheFile -Encoding UTF8
    Write-Host "Cached STIG selection for future runs" -ForegroundColor Green
    
    # Get the STIG object using the available STIG information
    try {
        $stig = Get-Stig -Technology $availableStigs.TechnologyRole -TechnologyVersion $availableStigs.TechnologyVersion
    } catch {
        Write-Host "Trying alternative STIG retrieval methods..." -ForegroundColor Yellow
        
        # Try different parameter combinations
        $stigMethods = @(
            @{ Technology = $osInfo.OsType; TechnologyVersion = $osInfo.Version },
            @{ Technology = 'WindowsServer'; TechnologyVersion = '2022' },
            @{ Technology = 'MS'; TechnologyVersion = '2022' },
            @{ Technology = 'DC'; TechnologyVersion = '2022' },
            @{ Technology = 'WindowsServer'; TechnologyVersion = '2019' },
            @{ Technology = $availableStigs.TechnologyRole; TechnologyVersion = $availableStigs.TechnologyVersion }
        )
        
        $stig = $null
        foreach ($method in $stigMethods) {
            try {
                Write-Host "Trying: Technology=$($method.Technology), Version=$($method.TechnologyVersion)" -ForegroundColor Gray
                $stig = Get-Stig -Technology $method.Technology -TechnologyVersion $method.TechnologyVersion
                if ($stig) {
                    Write-Host "Successfully retrieved STIG using Technology=$($method.Technology), Version=$($method.TechnologyVersion)" -ForegroundColor Green
                    break
                }
            } catch {
                Write-Host "Failed: $_" -ForegroundColor Gray
                continue
            }
        }
        
        if (-not $stig) {
            throw "Could not retrieve STIG object with any method"
        }
    }
    
    # Generate checklist (CKL file) for current state
    $cklPath = "reports\checklist-$Mode-$Timestamp.ckl"
    Write-Host "Generating STIG checklist..."
    New-StigCheckList -Stig $stig -OutputPath $cklPath
    
    # Run compliance test and capture results
    $testResults = Test-DscConfiguration -Detailed -ErrorAction SilentlyContinue
    
    # Generate detailed HTML report
    $htmlPath = "reports\report-$Mode-$Timestamp.html"
    $jsonPath = "reports\results-$Mode-$Timestamp.json"
    
    # Create HTML report
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>PowerSTIG Compliance Report - $Mode</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .summary { background: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .pass { color: green; }
        .fail { color: red; }
        .notapplicable { color: gray; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>PowerSTIG Compliance Report</h1>
    <div class="summary">
        <h2>Scan Summary</h2>
        <p><strong>Mode:</strong> $Mode</p>
        <p><strong>Date:</strong> $(Get-Date)</p>
        <p><strong>Host:</strong> $env:COMPUTERNAME</p>
        <p><strong>STIG:</strong> $($availableStigs.Title) v$($availableStigs.StigVersion)</p>
    </div>
    <h2>Compliance Results</h2>
    <table>
        <tr>
            <th>Rule ID</th>
            <th>Severity</th>
            <th>Status</th>
            <th>Title</th>
        </tr>
"@
    
    # Get all STIG rules and their current status
    $rules = Get-StigRule -Stig $stig
    $results = @()
    
    foreach ($rule in $rules) {
        $status = "Not Tested"
        $severity = $rule.Severity
        
        # Map to CAT levels
        $catLevel = switch ($severity) {
            "high" { "CAT I" }
            "medium" { "CAT II" }
            "low" { "CAT III" }
            default { $severity }
        }
        
        # Check if we have test results for this rule
        if ($testResults.ResourcesNotInDesiredState.ResourceId -contains $rule.Id) {
            $status = "Fail"
        } elseif ($testResults.ResourcesInDesiredState.ResourceId -contains $rule.Id) {
            $status = "Pass"
        }
        
        $results += [PSCustomObject]@{
            RuleId = $rule.Id
            Severity = $catLevel
            Status = $status
            Title = $rule.Title
        }
        
        $statusClass = switch ($status) {
            "Pass" { "pass" }
            "Fail" { "fail" }
            default { "notapplicable" }
        }
        
        $html += @"
        <tr>
            <td>$($rule.Id)</td>
            <td>$catLevel</td>
            <td class="$statusClass">$status</td>
            <td>$($rule.Title)</td>
        </tr>
"@
    }
    
    $html += @"
    </table>
    <div class="summary">
        <h3>Statistics</h3>
        <p>Total Rules: $($results.Count)</p>
        <p class="pass">Passed: $($results | Where-Object Status -eq 'Pass' | Measure-Object | Select-Object -ExpandProperty Count)</p>
        <p class="fail">Failed: $($results | Where-Object Status -eq 'Fail' | Measure-Object | Select-Object -ExpandProperty Count)</p>
        <p class="notapplicable">Not Tested: $($results | Where-Object Status -eq 'Not Tested' | Measure-Object | Select-Object -ExpandProperty Count)</p>
    </div>
</body>
</html>
"@
    
    # Save HTML report
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    
    # Save JSON results
    $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
    
    Write-Host "Scan complete. Results saved to:" -ForegroundColor Green
    Write-Host "  CKL:  $cklPath"
    Write-Host "  HTML: $htmlPath"
    Write-Host "  JSON: $jsonPath"
    
    # Show summary
    $passed = $results | Where-Object Status -eq 'Pass' | Measure-Object | Select-Object -ExpandProperty Count
    $failed = $results | Where-Object Status -eq 'Fail' | Measure-Object | Select-Object -ExpandProperty Count
    $catIFailed = $results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'CAT I' } | Measure-Object | Select-Object -ExpandProperty Count
    $catIIFailed = $results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'CAT II' } | Measure-Object | Select-Object -ExpandProperty Count
    
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Yellow
    Write-Host "  Passed: $passed" -ForegroundColor Green
    Write-Host "  Failed: $failed" -ForegroundColor Red
    if ($failed -gt 0) {
        Write-Host "    CAT I failures:  $catIFailed" -ForegroundColor Red
        Write-Host "    CAT II failures: $catIIFailed" -ForegroundColor Red
    }
}
catch {
    Write-Error "Scan failed: $_"
    exit 1
}