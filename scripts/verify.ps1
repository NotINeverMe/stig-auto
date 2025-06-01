Write-Host "Running post-remediation verification scan..."

# Run the after scan
try {
    & scripts\scan.ps1 -After
    Write-Host "Verification scan complete."
    
    # Find the most recent baseline and after reports
    $BaselineReport = Get-ChildItem -Path "reports" -Filter "report-baseline-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $AfterReport = Get-ChildItem -Path "reports" -Filter "report-after-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    
    if ($BaselineReport -and $AfterReport) {
        Write-Host ""
        Write-Host "Comparison reports available:"
        Write-Host "  Baseline: $($BaselineReport.FullName)"
        Write-Host "  After remediation: $($AfterReport.FullName)"
        Write-Host ""
        Write-Host "Please review both reports to verify remediation effectiveness."
    } else {
        Write-Warning "Could not find both baseline and after reports for comparison."
    }
}
catch {
    Write-Error "Verification scan failed: $_"
    exit 1
}

Write-Host "Verification complete."
