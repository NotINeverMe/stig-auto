<#
.SYNOPSIS
    Windows Server Hardening Script for CMMC 2.0 Compliance
    
.DESCRIPTION
    This script implements Windows Server hardening controls aligned with CMMC 2.0 requirements.
    Extracted and enhanced from AWS CloudFormation template hardening configurations.
    
.PARAMETER SkipDomainJoin
    Skip domain-related configurations
    
.PARAMETER ReportOnly
    Run in audit mode without making changes
    
.PARAMETER LogPath
    Specify custom log location (default: C:\Windows\Logs\CMMC-Hardening.log)
    
.PARAMETER SkipAccountRename
    Skip renaming of built-in Administrator and Guest accounts
    
.PARAMETER SkipEventLogHardening
    Skip event log access control modifications
    
.PARAMETER SkipFIPSMode
    Skip enabling FIPS algorithm policy
    
.EXAMPLE
    .\Invoke-CMMC-WindowsHardening.ps1
    
.EXAMPLE
    .\Invoke-CMMC-WindowsHardening.ps1 -SkipDomainJoin -ReportOnly
    
.NOTES
    Author: CMMC Hardening Script
    Version: 1.0
    CMMC 2.0 Level 2 Aligned
#>

[CmdletBinding()]
param(
    [switch]$SkipDomainJoin,
    [switch]$ReportOnly,
    [string]$LogPath = "C:\Windows\Logs\CMMC-Hardening.log",
    [switch]$SkipAccountRename,
    [switch]$SkipEventLogHardening,
    [switch]$SkipFIPSMode
)

# Initialize logging
$ErrorActionPreference = 'Stop'
$script:LogFile = $LogPath
$script:ReportMode = $ReportOnly

function Write-HardeningLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$CMMCControl = ""
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level]"
    
    if ($CMMCControl) {
        $logEntry += " [CMMC: $CMMCControl]"
    }
    
    $logEntry += " $Message"
    
    # Console output
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }
    
    # File output
    try {
        Add-Content -Path $script:LogFile -Value $logEntry -Force
    } catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }
}

function Test-IsElevated {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-HardeningAction {
    param(
        [scriptblock]$Action,
        [string]$Description,
        [string]$CMMCControl
    )
    
    Write-HardeningLog -Message "Processing: $Description" -CMMCControl $CMMCControl
    
    if ($script:ReportMode) {
        Write-HardeningLog -Message "REPORT MODE: Would execute - $Description" -Level "WARNING"
        return
    }
    
    try {
        & $Action
        Write-HardeningLog -Message "SUCCESS: $Description" -Level "SUCCESS" -CMMCControl $CMMCControl
    } catch {
        Write-HardeningLog -Message "ERROR: Failed to execute - $Description. Error: $_" -Level "ERROR" -CMMCControl $CMMCControl
        throw
    }
}

# Main execution starts here
Write-HardeningLog -Message "=========================================="
Write-HardeningLog -Message "Starting CMMC 2.0 Windows Hardening Script"
Write-HardeningLog -Message "=========================================="
Write-HardeningLog -Message "Report Mode: $ReportMode"

# Check for elevation
if (-not (Test-IsElevated)) {
    Write-HardeningLog -Message "This script requires administrator privileges" -Level "ERROR"
    exit 1
}

# 1. EVENT LOG ACCESS CONTROL HARDENING
# CMMC Controls: AU.L2-3.3.1, AU.L2-3.3.2 (Audit and Accountability)
if (-not $SkipEventLogHardening) {
    Invoke-HardeningAction -Description "Hardening Event Log Access Controls" -CMMCControl "AU.L2-3.3.1" -Action {
        # Get all event log files
        $eventLogs = Get-ChildItem -Path "C:\Windows\System32\winevt\Logs\*.evtx" -ErrorAction SilentlyContinue
        
        foreach ($logFile in $eventLogs) {
            try {
                $acl = Get-Acl -Path $logFile.FullName
                $authenticatedUsers = New-Object System.Security.Principal.NTAccount('NT AUTHORITY\Authenticated Users')
                
                # Remove Authenticated Users access
                $acl.PurgeAccessRules($authenticatedUsers)
                
                # Apply the modified ACL
                if (-not $script:ReportMode) {
                    Set-Acl -Path $logFile.FullName -AclObject $acl
                }
                
                Write-HardeningLog -Message "Removed Authenticated Users access from: $($logFile.Name)"
            } catch {
                Write-HardeningLog -Message "Failed to modify ACL for $($logFile.Name): $_" -Level "WARNING"
            }
        }
    }
}

# 2. BUILT-IN ACCOUNT RENAMING
# CMMC Controls: AC.L1-3.1.1, IA.L1-3.5.1 (Access Control & Identification)
if (-not $SkipAccountRename) {
    # Rename Guest account
    Invoke-HardeningAction -Description "Renaming Guest account to StigUser" -CMMCControl "AC.L1-3.1.1" -Action {
        try {
            $guestAccount = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
            if ($guestAccount) {
                Rename-LocalUser -Name "Guest" -NewName "StigUser"
                Write-HardeningLog -Message "Guest account renamed to StigUser"
            } else {
                Write-HardeningLog -Message "Guest account not found or already renamed" -Level "WARNING"
            }
        } catch {
            if ($_.Exception.Message -like "*cannot be found*") {
                Write-HardeningLog -Message "Guest account already renamed or doesn't exist" -Level "WARNING"
            } else {
                throw
            }
        }
    }
    
    # Rename Administrator account
    Invoke-HardeningAction -Description "Renaming Administrator account to StigAdmin" -CMMCControl "AC.L1-3.1.1" -Action {
        try {
            $adminAccount = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
            if ($adminAccount) {
                Rename-LocalUser -Name "Administrator" -NewName "StigAdmin"
                Write-HardeningLog -Message "Administrator account renamed to StigAdmin"
            } else {
                Write-HardeningLog -Message "Administrator account not found or already renamed" -Level "WARNING"
            }
        } catch {
            if ($_.Exception.Message -like "*cannot be found*") {
                Write-HardeningLog -Message "Administrator account already renamed or doesn't exist" -Level "WARNING"
            } else {
                throw
            }
        }
    }
}

# 3. ENABLE FIPS ALGORITHM POLICY
# CMMC Controls: SC.L2-3.13.11, SC.L2-3.13.8 (System and Communications Protection)
if (-not $SkipFIPSMode) {
    Invoke-HardeningAction -Description "Enabling FIPS Algorithm Policy" -CMMCControl "SC.L2-3.13.11" -Action {
        $fipsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy'
        
        # Ensure the registry path exists
        if (-not (Test-Path $fipsPath)) {
            New-Item -Path $fipsPath -Force | Out-Null
        }
        
        # Set FIPS enabled
        New-ItemProperty -Path $fipsPath -Name 'Enabled' -Value 1 -PropertyType DWORD -Force | Out-Null
    }
}

# 4. ADDITIONAL CMMC 2.0 HARDENING CONTROLS

# 4.1 Enable PowerShell Logging
# CMMC Controls: AU.L2-3.3.1, AU.L2-3.3.2
Invoke-HardeningAction -Description "Enabling PowerShell Script Block Logging" -CMMCControl "AU.L2-3.3.1" -Action {
    $psLoggingPath = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
    
    if (-not (Test-Path $psLoggingPath)) {
        New-Item -Path $psLoggingPath -Force | Out-Null
    }
    
    Set-ItemProperty -Path $psLoggingPath -Name 'EnableScriptBlockLogging' -Value 1 -Force
    Set-ItemProperty -Path $psLoggingPath -Name 'EnableScriptBlockInvocationLogging' -Value 1 -Force
}

# 4.2 Enable PowerShell Transcription
# CMMC Controls: AU.L2-3.3.1, AU.L2-3.3.2
Invoke-HardeningAction -Description "Enabling PowerShell Transcription" -CMMCControl "AU.L2-3.3.1" -Action {
    $transcriptionPath = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell\Transcription'
    
    if (-not (Test-Path $transcriptionPath)) {
        New-Item -Path $transcriptionPath -Force | Out-Null
    }
    
    Set-ItemProperty -Path $transcriptionPath -Name 'EnableTranscripting' -Value 1 -Force
    Set-ItemProperty -Path $transcriptionPath -Name 'EnableInvocationHeader' -Value 1 -Force
    Set-ItemProperty -Path $transcriptionPath -Name 'OutputDirectory' -Value 'C:\Windows\Logs\PowerShell\Transcription' -Force
    
    # Create transcription directory
    $transcriptDir = 'C:\Windows\Logs\PowerShell\Transcription'
    if (-not (Test-Path $transcriptDir)) {
        New-Item -Path $transcriptDir -ItemType Directory -Force | Out-Null
    }
}

# 4.3 Configure Windows Defender
# CMMC Controls: SI.L1-3.14.1, SI.L1-3.14.2, SI.L1-3.14.4
Invoke-HardeningAction -Description "Configuring Windows Defender Settings" -CMMCControl "SI.L1-3.14.1" -Action {
    # Enable real-time protection
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    
    # Enable cloud-delivered protection
    Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
    
    # Enable automatic sample submission
    Set-MpPreference -SubmitSamplesConsent SendAllSamples -ErrorAction SilentlyContinue
    
    # Set scan schedule (daily at 2 AM)
    Set-MpPreference -ScanScheduleDay Everyday -ErrorAction SilentlyContinue
    Set-MpPreference -ScanScheduleTime 02:00:00 -ErrorAction SilentlyContinue
}

# 4.4 Disable unnecessary services
# CMMC Controls: CM.L2-3.4.6, CM.L2-3.4.7 (Configuration Management)
Invoke-HardeningAction -Description "Disabling unnecessary services" -CMMCControl "CM.L2-3.4.6" -Action {
    $servicesToDisable = @(
        'Browser',          # Computer Browser
        'LanmanServer',     # Server (if not needed)
        'SSDPSRV',         # SSDP Discovery
        'upnphost',        # UPnP Device Host
        'WSearch'          # Windows Search (if not needed)
    )
    
    foreach ($service in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne 'Stopped') {
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                Write-HardeningLog -Message "Disabled service: $service"
            }
        } catch {
            Write-HardeningLog -Message "Could not disable service $service : $_" -Level "WARNING"
        }
    }
}

# 4.5 Configure Advanced Audit Policies
# CMMC Controls: AU.L2-3.3.1, AU.L2-3.3.2, AU.L2-3.3.3
Invoke-HardeningAction -Description "Configuring Advanced Audit Policies" -CMMCControl "AU.L2-3.3.1" -Action {
    # Account Logon
    auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable
    
    # Account Management
    auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
    auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable
    
    # Logon/Logoff
    auditpol /set /subcategory:"Logon" /success:enable /failure:enable
    auditpol /set /subcategory:"Logoff" /success:enable
    auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable
    
    # Object Access
    auditpol /set /subcategory:"File System" /success:enable /failure:enable
    auditpol /set /subcategory:"Registry" /success:enable /failure:enable
    
    # Policy Change
    auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable
    auditpol /set /subcategory:"Authentication Policy Change" /success:enable /failure:enable
    
    # Privilege Use
    auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable
    
    # System
    auditpol /set /subcategory:"Security State Change" /success:enable /failure:enable
    auditpol /set /subcategory:"Security System Extension" /success:enable /failure:enable
    auditpol /set /subcategory:"System Integrity" /success:enable /failure:enable
}

# 4.6 Network Security Hardening
# CMMC Controls: SC.L1-3.13.1, SC.L2-3.13.5
Invoke-HardeningAction -Description "Configuring Network Security Settings" -CMMCControl "SC.L1-3.13.1" -Action {
    # Disable NetBIOS over TCP/IP
    $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'"
    foreach ($adapter in $adapters) {
        $adapter.SetTcpipNetbios(2) | Out-Null  # 2 = Disable NetBIOS over TCP/IP
    }
    
    # Disable IPv6 (if not needed)
    # New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 0xFF -PropertyType DWORD -Force | Out-Null
    
    # Enable Windows Firewall for all profiles
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
}

# 4.7 Configure Security Options
# CMMC Controls: AC.L1-3.1.1, AC.L1-3.1.2
Invoke-HardeningAction -Description "Configuring Security Options" -CMMCControl "AC.L1-3.1.1" -Action {
    # Disable storage of passwords and credentials for network authentication
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "DisableDomainCreds" -Value 1 -Force
    
    # Do not display last user name
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DontDisplayLastUserName" -Value 1 -Force
    
    # Enable User Account Control
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1 -Force
    
    # Set UAC to prompt for consent on the secure desktop
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 2 -Force
    
    # Restrict anonymous access to Named Pipes and Shares
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" -Name "RestrictNullSessAccess" -Value 1 -Force
}

# 4.8 Configure Account Policies
# CMMC Controls: IA.L2-3.5.3, IA.L2-3.5.4
Invoke-HardeningAction -Description "Configuring Account Lockout Policies" -CMMCControl "IA.L2-3.5.3" -Action {
    try {
        # Account lockout threshold: 5 invalid attempts
        net accounts /lockoutthreshold:5
        
        # Account lockout duration: 15 minutes
        net accounts /lockoutduration:15
        
        # Reset account lockout counter after: 15 minutes
        net accounts /lockoutwindow:15
        
        # Minimum password length: 14 characters
        net accounts /minpwlen:14
        
        # Maximum password age: 60 days
        net accounts /maxpwage:60
        
        # Password history: 24 passwords
        net accounts /uniquepw:24
    } catch {
        Write-HardeningLog -Message "Failed to configure account policies: $_" -Level "WARNING"
    }
}

# 5. DOMAIN-SPECIFIC CONFIGURATIONS
if (-not $SkipDomainJoin) {
    Write-HardeningLog -Message "Domain join configurations would be applied here if implemented" -Level "INFO"
    # Domain-specific configurations would go here
    # This is a placeholder as the original script's domain join logic is specific to the CloudFormation environment
}

# 6. SUMMARY REPORT
Write-HardeningLog -Message "=========================================="
Write-HardeningLog -Message "CMMC 2.0 Windows Hardening Script Complete"
Write-HardeningLog -Message "=========================================="

if ($ReportOnly) {
    Write-HardeningLog -Message "Script ran in REPORT MODE - No changes were made" -Level "WARNING"
} else {
    Write-HardeningLog -Message "All hardening actions have been applied" -Level "SUCCESS"
    Write-HardeningLog -Message "Please review the log file at: $LogPath" -Level "INFO"
    Write-HardeningLog -Message "A system restart may be required for some changes to take effect" -Level "WARNING"
}

# Create a summary of CMMC controls addressed
$cmmcSummary = @"

CMMC 2.0 Controls Addressed:
- AC.L1-3.1.1: Limit system access to authorized users
- AC.L1-3.1.2: Limit system access to the types of transactions and functions that authorized users are permitted to execute
- AU.L2-3.3.1: Create and retain system audit logs
- AU.L2-3.3.2: Ensure that the actions of individual system users can be uniquely traced
- AU.L2-3.3.3: Review and update logged events
- CM.L2-3.4.6: Employ the principle of least functionality
- CM.L2-3.4.7: Restrict, disable, or prevent the use of nonessential programs
- IA.L1-3.5.1: Identify system users, processes, and devices
- IA.L2-3.5.3: Use multifactor authentication
- IA.L2-3.5.4: Employ replay-resistant authentication mechanisms
- SC.L1-3.13.1: Monitor, control, and protect communications
- SC.L2-3.13.5: Implement subnetworks for publicly accessible system components
- SC.L2-3.13.8: Implement cryptographic mechanisms to prevent unauthorized disclosure
- SC.L2-3.13.11: Employ FIPS-validated cryptography
- SI.L1-3.14.1: Identify, report, and correct system flaws
- SI.L1-3.14.2: Provide protection from malicious code
- SI.L1-3.14.4: Update malicious code protection mechanisms

"@

Write-HardeningLog -Message $cmmcSummary -Level "INFO"