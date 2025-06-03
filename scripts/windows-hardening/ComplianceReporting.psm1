<#
.SYNOPSIS
    Compliance reporting functions for NIST 800-171
.DESCRIPTION
    Generates compliance reports and validation checks
#>

function Export-ComplianceReport {
    [CmdletBinding()]
    param(
        [string]$ReportPath = "C:\Windows\Temp\WindowsHardening_Report.html",
        [int]$SuccessCount = 0,
        [int]$FailureCount = 0
    )
    
    $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $computerName = $env:COMPUTERNAME
    $osVersion = (Get-WmiObject Win32_OperatingSystem).Caption
    
    # Define NIST control mappings
    $nistControls = @{
        "3.1.1" = "Limit information system access to authorized users"
        "3.1.2" = "Limit information system access to authorized processes"
        "3.1.5" = "Employ the principle of least privilege"
        "3.1.13" = "Employ cryptographic mechanisms for remote access"
        "3.1.19" = "Encrypt CUI on mobile devices"
        "3.1.20" = "Verify and control connections to external systems"
        "3.3.1" = "Create and retain audit records"
        "3.3.2" = "Ensure audit record capacity"
        "3.3.4" = "Alert on audit logging process failures"
        "3.3.5" = "Correlate audit record review"
        "3.3.8" = "Protect audit information"
        "3.3.9" = "Limit management of audit logging"
        "3.4.2" = "Establish and maintain baseline configurations"
        "3.4.6" = "Employ the principle of least functionality"
        "3.4.7" = "Restrict nonessential programs"
        "3.4.8" = "Apply deny-by-exception policy"
        "3.5.1" = "Identify information system users"
        "3.5.2" = "Authenticate users"
        "3.5.3" = "Use multifactor authentication"
        "3.5.7" = "Enforce minimum password complexity"
        "3.5.8" = "Prohibit password reuse"
        "3.12.1" = "Conduct security control assessments"
        "3.12.2" = "Develop and implement plans of action"
        "3.13.1" = "Monitor and control communications"
        "3.13.5" = "Implement subnetworks"
        "3.13.8" = "Implement cryptographic mechanisms"
        "3.13.11" = "Employ FIPS-validated cryptography"
        "3.13.16" = "Protect the confidentiality of CUI at rest"
        "3.14.1" = "Identify and manage information system flaws"
        "3.14.2" = "Provide protection from malicious code"
        "3.14.6" = "Monitor organizational systems"
        "3.14.7" = "Identify unauthorized use"
    }
    
    # Read log file to extract control implementation status
    $logPath = "C:\Windows\Temp\WindowsHardening.log"
    $implementedControls = @{}
    
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath
        foreach ($line in $logContent) {
            if ($line -match '\[NIST: ([\d.,]+)\]') {
                $controls = $matches[1] -split ','
                foreach ($control in $controls) {
                    $control = $control.Trim()
                    if ($line -match 'SUCCESS:') {
                        $implementedControls[$control] = 'Implemented'
                    }
                    elseif ($line -match 'FAILED:') {
                        $implementedControls[$control] = 'Failed'
                    }
                    elseif ($line -match 'DRY RUN:') {
                        $implementedControls[$control] = 'Planned'
                    }
                }
            }
        }
    }
    
    # Generate HTML report
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Windows Hardening Compliance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .summary { background-color: white; padding: 20px; margin: 20px 0; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .controls { background-color: white; padding: 20px; margin: 20px 0; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background-color: #34495e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .implemented { color: #27ae60; font-weight: bold; }
        .failed { color: #e74c3c; font-weight: bold; }
        .planned { color: #f39c12; font-weight: bold; }
        .not-implemented { color: #95a5a6; }
        .metric { display: inline-block; margin: 10px 20px; }
        .metric-value { font-size: 24px; font-weight: bold; }
        .chart { width: 100%; height: 20px; background-color: #ecf0f1; border-radius: 10px; overflow: hidden; margin: 20px 0; }
        .chart-fill { height: 100%; background-color: #27ae60; transition: width 0.5s; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Windows Hardening Compliance Report</h1>
        <p>Generated on: $reportDate</p>
        <p>Computer: $computerName | OS: $osVersion</p>
    </div>
    
    <div class="summary">
        <h2>Executive Summary</h2>
        <div class="metric">
            <span class="metric-value">$($SuccessCount + $FailureCount)</span> Total Tasks
        </div>
        <div class="metric">
            <span class="metric-value implemented">$SuccessCount</span> Successful
        </div>
        <div class="metric">
            <span class="metric-value failed">$FailureCount</span> Failed
        </div>
        
        <div class="chart">
            <div class="chart-fill" style="width: $(if (($SuccessCount + $FailureCount) -gt 0) { ($SuccessCount / ($SuccessCount + $FailureCount) * 100) } else { 0 })%"></div>
        </div>
        
        <p>This report provides a comprehensive overview of the Windows hardening measures implemented to achieve NIST 800-171 compliance.</p>
    </div>
    
    <div class="controls">
        <h2>NIST 800-171 Control Implementation Status</h2>
        <table>
            <tr>
                <th>Control ID</th>
                <th>Description</th>
                <th>Status</th>
            </tr>
"@
    
    # Add control status rows
    foreach ($control in $nistControls.GetEnumerator() | Sort-Object Name) {
        $status = if ($implementedControls.ContainsKey($control.Key)) {
            $implementedControls[$control.Key]
        } else {
            "Not Implemented"
        }
        
        $statusClass = switch ($status) {
            "Implemented" { "implemented" }
            "Failed" { "failed" }
            "Planned" { "planned" }
            default { "not-implemented" }
        }
        
        $html += @"
            <tr>
                <td>$($control.Key)</td>
                <td>$($control.Value)</td>
                <td class="$statusClass">$status</td>
            </tr>
"@
    }
    
    $html += @"
        </table>
    </div>
    
    <div class="summary">
        <h2>Recommendations</h2>
        <ul>
            <li>Review and remediate any failed controls</li>
            <li>Schedule regular compliance scans</li>
            <li>Maintain audit logs for compliance verification</li>
            <li>Keep security policies and software up to date</li>
        </ul>
    </div>
</body>
</html>
"@
    
    # Save report
    Set-Content -Path $ReportPath -Value $html
    Write-Host "Compliance report saved to: $ReportPath" -ForegroundColor Green
}

function Test-ComplianceStatus {
    [CmdletBinding()]
    param()
    
    $complianceChecks = @()
    
    # Check FIPS mode
    $fipsCheck = @{
        Control = "3.13.11"
        Description = "FIPS-validated cryptography"
        Status = "Unknown"
    }
    
    $fipsEnabled = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name Enabled -ErrorAction SilentlyContinue).Enabled
    $fipsCheck.Status = if ($fipsEnabled -eq 1) { "Compliant" } else { "Non-Compliant" }
    $complianceChecks += $fipsCheck
    
    # Check Windows Defender
    $defenderCheck = @{
        Control = "3.14.2"
        Description = "Anti-malware protection"
        Status = "Unknown"
    }
    
    try {
        $defenderStatus = Get-MpComputerStatus
        $defenderCheck.Status = if ($defenderStatus.RealTimeProtectionEnabled) { "Compliant" } else { "Non-Compliant" }
    }
    catch {
        $defenderCheck.Status = "Error"
    }
    $complianceChecks += $defenderCheck
    
    # Check audit policy
    $auditCheck = @{
        Control = "3.3.1"
        Description = "Audit logging enabled"
        Status = "Unknown"
    }
    
    $auditPolicy = auditpol /get /category:* | Select-String "Success|Failure"
    $auditCheck.Status = if ($auditPolicy.Count -gt 10) { "Compliant" } else { "Partial" }
    $complianceChecks += $auditCheck
    
    # Check BitLocker
    $bitlockerCheck = @{
        Control = "3.13.16"
        Description = "Encryption at rest"
        Status = "Unknown"
    }
    
    try {
        $bitlockerStatus = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        $bitlockerCheck.Status = if ($bitlockerStatus.ProtectionStatus -eq 'On') { "Compliant" } else { "Non-Compliant" }
    }
    catch {
        $bitlockerCheck.Status = "Not Applicable"
    }
    $complianceChecks += $bitlockerCheck
    
    return $complianceChecks
}

Export-ModuleMember -Function @(
    'Export-ComplianceReport',
    'Test-ComplianceStatus'
)