#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Check for critical STIG findings and fail pipeline if CAT I violations exist
.DESCRIPTION
    Reviews scan results and implements security gating for high-severity findings
.PARAMETER ReportPath
    Path to the scan report JSON file
.PARAMETER FailOnCatI
    Fail the pipeline if CAT I findings exist (default: true)
.PARAMETER FailOnCatII
    Fail the pipeline if more than the threshold CAT II findings exist
.PARAMETER CatIIThreshold
    Maximum allowed CAT II findings before failing (default: 10)
#>

param(
    [Parameter(Mandatory)]
    [string]$ReportPath,
    
    [switch]$FailOnCatI = $true,
    
    [switch]$FailOnCatII,
    
    [int]$CatIIThreshold = 10
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ReportPath)) {
    Write-Error "Report file not found: $ReportPath"
    exit 1
}

try {
    $results = Get-Content $ReportPath | ConvertFrom-Json
    Write-Host "Analyzing STIG compliance results from: $ReportPath" -ForegroundColor Cyan
} catch {
    Write-Error "Failed to parse report file: $_"
    exit 1
}

# Count findings by severity
$catIFindings = $results | Where-Object { $_.Severity -eq 'CAT I' -and $_.Status -eq 'Fail' }
$catIIFindings = $results | Where-Object { $_.Severity -eq 'CAT II' -and $_.Status -eq 'Fail' }
$catIIIFindings = $results | Where-Object { $_.Severity -eq 'CAT III' -and $_.Status -eq 'Fail' }

$catICount = ($catIFindings | Measure-Object).Count
$catIICount = ($catIIFindings | Measure-Object).Count
$catIIICount = ($catIIIFindings | Measure-Object).Count

Write-Host ""
Write-Host "=== STIG Findings Security Gate ===" -ForegroundColor Yellow
Write-Host "CAT I (High) Findings: $catICount" -ForegroundColor $(if ($catICount -eq 0) { 'Green' } else { 'Red' })
Write-Host "CAT II (Medium) Findings: $catIICount" -ForegroundColor $(if ($catIICount -le $CatIIThreshold) { 'Green' } else { 'Yellow' })
Write-Host "CAT III (Low) Findings: $catIIICount" -ForegroundColor Green

$pipelineFailed = $false
$failureReasons = @()

# Check CAT I findings
if ($FailOnCatI -and $catICount -gt 0) {
    $pipelineFailed = $true
    $failureReasons += "CAT I findings detected"
    
    Write-Host ""
    Write-Host "CAT I FINDINGS (CRITICAL):" -ForegroundColor Red
    foreach ($finding in $catIFindings) {
        Write-Host "  - $($finding.RuleId): $($finding.Title)" -ForegroundColor Red
    }
}

# Check CAT II findings
if ($FailOnCatII -and $catIICount -gt $CatIIThreshold) {
    $pipelineFailed = $true
    $failureReasons += "CAT II findings exceed threshold ($catIICount > $CatIIThreshold)"
    
    Write-Host ""
    Write-Host "CAT II FINDINGS (EXCEEDS THRESHOLD):" -ForegroundColor Yellow
    foreach ($finding in $catIIFindings) {
        Write-Host "  - $($finding.RuleId): $($finding.Title)" -ForegroundColor Yellow
    }
}

# Generate exception check
$exceptionFile = "security-exceptions.json"
if (Test-Path $exceptionFile) {
    Write-Host ""
    Write-Host "Checking security exceptions file..." -ForegroundColor Cyan
    
    try {
        $exceptions = Get-Content $exceptionFile | ConvertFrom-Json
        $exemptFindings = @()
        
        foreach ($finding in $catIFindings) {
            if ($exceptions.exemptions.ruleIds -contains $finding.RuleId) {
                $exemptFindings += $finding.RuleId
                Write-Host "  Exempted CAT I finding: $($finding.RuleId)" -ForegroundColor Yellow
            }
        }
        
        if ($exemptFindings.Count -gt 0) {
            $remainingCatI = $catICount - $exemptFindings.Count
            Write-Host "CAT I findings after exemptions: $remainingCatI" -ForegroundColor Cyan
            
            if ($remainingCatI -eq 0) {
                $pipelineFailed = $false
                $failureReasons = $failureReasons | Where-Object { $_ -notlike "*CAT I*" }
            }
        }
        
    } catch {
        Write-Warning "Failed to process security exceptions file: $_"
    }
}

Write-Host ""
if ($pipelineFailed) {
    Write-Host "SECURITY GATE: FAILED" -ForegroundColor Red
    Write-Host "Failure reasons:" -ForegroundColor Red
    foreach ($reason in $failureReasons) {
        Write-Host "  - $reason" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "To override CAT I findings, create a security-exceptions.json file:" -ForegroundColor Yellow
    Write-Host @"
{
  "exemptions": {
    "ruleIds": ["V-12345", "V-67890"],
    "justification": "Business requirement exception",
    "approver": "Security Team",
    "expiryDate": "2025-12-31"
  }
}
"@ -ForegroundColor Gray
    
    exit 1
} else {
    Write-Host "SECURITY GATE: PASSED" -ForegroundColor Green
    Write-Host "No critical security violations detected" -ForegroundColor Green
    exit 0
}