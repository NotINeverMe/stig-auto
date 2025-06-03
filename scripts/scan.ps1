param(
    [switch]$Baseline,
    [switch]$After
)

if (-not $Baseline -and -not $After) {
    Write-Host "Usage: .\scan.ps1 [-Baseline|-After]"
    Write-Host "  -Baseline: Run baseline scan before remediation"
    Write-Host "  -After:    Run scan after remediation"
    exit 1
}

# Check if we're on Windows and should use PowerSTIG
if ($PSVersionTable.PSVersion.Major -ge 5 -and $PSVersionTable.Platform -ne 'Unix') {
    # Windows - use PowerSTIG
    $powerStigScript = Join-Path $PSScriptRoot "scan-powerstig.ps1"
    if (Test-Path $powerStigScript) {
        Write-Host "Windows detected - using PowerSTIG for scanning..." -ForegroundColor Cyan
        if ($Baseline) {
            & $powerStigScript -Baseline
        } else {
            & $powerStigScript -After
        }
        exit $LASTEXITCODE
    } else {
        Write-Warning "PowerSTIG scan script not found. Falling back to OpenSCAP..."
    }
}

$Mode = if ($Baseline) { "baseline" } else { "after" }

# Determine default STIG profile based on OS
$DefaultProfile = 'xccdf_org.ssgproject.content_profile_stig'
if (Test-Path '/etc/os-release') {
    $idLine = Select-String -Path '/etc/os-release' -Pattern '^ID=' | Select-Object -First 1
    if ($idLine) {
        $id = ($idLine.Line -replace '^ID=', '').Trim('"')
        switch ($id) {
            'rhel' { $DefaultProfile = 'xccdf_org.ssgproject.content_profile_stig' }
            'ubuntu' { $DefaultProfile = 'xccdf_org.ssgproject.content_profile_stig' }
        }
    }
} else {
    $caption = (Get-CimInstance Win32_OperatingSystem).Caption
    if ($caption -match 'Windows') {
        $DefaultProfile = 'xccdf_org.ssgproject.content_profile_stig'
    }
}

# Allow override via environment variable
$STIG_PROFILE_ID = if ($env:STIG_PROFILE_ID) { $env:STIG_PROFILE_ID } else { $DefaultProfile }

# Create reports directory
New-Item -ItemType Directory -Force -Path "reports" | Out-Null

# Generate timestamp for unique filenames
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# Find the most recent SCAP content file
$ScapFile = Get-ChildItem -Path "scap_content" -Filter "*.xml" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $ScapFile) {
    Write-Error "No SCAP content found. Run get_scap_content.ps1 first."
    exit 1
}

Write-Host "Using SCAP content: $($ScapFile.FullName)"
Write-Host "Running $Mode scan..."

try {
    # Run OpenSCAP evaluation
    $ResultsFile = "reports\results-$Mode-$Timestamp.arf"
    $ReportFile = "reports\report-$Mode-$Timestamp.html"

    & oscap.exe xccdf eval `
        --profile $STIG_PROFILE_ID `
        --results $ResultsFile `
        --report $ReportFile `
        $ScapFile.FullName

    $rc = $LASTEXITCODE
    if ($rc -ne 0 -and $rc -ne 2) {
        throw "OpenSCAP failed with exit code $rc"
    }

    Write-Host "Scan complete. Results saved to:"
    Write-Host "  ARF: $ResultsFile"
    Write-Host "  HTML: $ReportFile"
}
catch {
    Write-Error "Scan failed: $_"
    exit 1
}
