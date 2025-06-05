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

# Determine OS and STIG version
function Get-OSInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $caption = $os.Caption
    
    if ($caption -match 'Windows 10') {
        return @{ OsType = 'WindowsClient'; Version = '10.0' }
    } elseif ($caption -match 'Windows 11') {
        return @{ OsType = 'WindowsClient'; Version = '11.0' }
    } elseif ($caption -match 'Windows Server 2022') {
        return @{ OsType = 'WindowsServer'; Version = '2022' }
    } elseif ($caption -match 'Windows Server 2019') {
        return @{ OsType = 'WindowsServer'; Version = '2019' }
    } elseif ($caption -match 'Windows Server 2016') {
        return @{ OsType = 'WindowsServer'; Version = '2016' }
    } else {
        throw "Unsupported OS: $caption"
    }
}

$osInfo = Get-OSInfo
Write-Host "Detected OS: $($osInfo.OsType) $($osInfo.Version)"

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
    $availableStigs = $allStigs | Where-Object {
        $_.TechnologyRole -eq $osInfo.OsType -and 
        ($_.TechnologyVersion -eq $osInfo.Version -or 
         $_.TechnologyVersion -eq $osInfo.Version.ToString() -or
         $_.TechnologyVersion -like "*$($osInfo.Version)*")
    } | Sort-Object -Property StigVersion -Descending | Select-Object -First 1
    
    # If no exact match, try broader search for Windows Server
    if (-not $availableStigs -and $osInfo.OsType -eq 'WindowsServer') {
        Write-Host "No exact version match, trying broader search for Windows Server..." -ForegroundColor Yellow
        $availableStigs = $allStigs | Where-Object {
            $_.TechnologyRole -eq 'WindowsServer'
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
    
    # Get the STIG object
    $stig = Get-Stig -Technology $osInfo.OsType -TechnologyVersion $osInfo.Version
    
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