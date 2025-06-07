<#
.SYNOPSIS
    Audit and logging configuration functions for NIST 800-171 compliance
.DESCRIPTION
    Implements audit and accountability controls mapped to NIST controls
#>

# Helper function for logging
function Write-HardeningLog {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"
    Write-Host $logMessage
}

# Helper function for getting valid audit subcategories
function Get-ValidAuditSubcategories {
    try {
        $result = & auditpol /list /subcategory:* 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $result | Where-Object { $_ -notlike "*---*" -and $_ -notlike "*Machine Name*" -and $_ -trim -ne "" }
        }
    } catch {
        Write-Warning "Could not retrieve audit subcategories: $_"
    }
    return $null
}

# Helper function for consistent action execution and logging
function Invoke-HardeningAction {
    param(
        [scriptblock]$Action,
        [string]$Description,
        [string]$NistControl,
        [switch]$DryRun
    )
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute - $Description" -ForegroundColor Yellow
        return $true
    }
    
    try {
        & $Action
        Write-Host "SUCCESS: $Description" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "FAILED: $Description - Error: $_" -ForegroundColor Red
        throw
    }
}

# NIST 3.3.1, 3.3.2 - Audit and Accountability
function Enable-AuditLogging {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Enable comprehensive audit logging"
    $nistControl = "3.3.1,3.3.2"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Configure audit policy via auditpol
        $auditCategories = @(
            "Account Logon/Credential Validation:Success,Failure"
            "Account Logon/Other Account Logon Events:Success,Failure"
            "Account Management/User Account Management:Success,Failure"
            "Account Management/Security Group Management:Success,Failure"
            "Detailed Tracking/Process Creation:Success"
            "Detailed Tracking/Process Termination:Success"
            "Logon/Logoff/Logon:Success,Failure"
            "Logon/Logoff/Logoff:Success"
            "Logon/Logoff/Special Logon:Success,Failure"
            "Object Access/File System:Success,Failure"
            "Object Access/Registry:Success,Failure"
            "Policy Change/Audit Policy Change:Success,Failure"
            "Policy Change/Authentication Policy Change:Success,Failure"
            "Privilege Use/Sensitive Privilege Use:Success,Failure"
            "System/Security State Change:Success,Failure"
            "System/Security System Extension:Success,Failure"
            "System/System Integrity:Success,Failure"
        )
        
        # Get valid subcategories first for validation
        $validSubcategories = Get-ValidAuditSubcategories
        
        foreach ($category in $auditCategories) {
            try {
                $parts = $category -split ':'
                $subcategory = $parts[0]
                $setting = $parts[1]
                
                Write-HardeningLog "Configuring audit policy for: $subcategory" -Level Info
                
                # Validate subcategory exists (case-insensitive)
                $matchingSubcat = $validSubcategories | Where-Object { $_ -like "*$subcategory*" } | Select-Object -First 1
                if (-not $matchingSubcat) {
                    Write-Warning "Subcategory '$subcategory' not found in system. Skipping..."
                    continue
                }
                
                if ($setting -eq "Success,Failure") {
                    $result = & auditpol /set /subcategory:"$subcategory" /success:enable /failure:enable 2>&1
                }
                elseif ($setting -eq "Success") {
                    $result = & auditpol /set /subcategory:"$subcategory" /success:enable /failure:disable 2>&1
                }
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Successfully configured audit policy: $subcategory" -ForegroundColor Green
                } else {
                    Write-Warning "Failed to configure audit policy '$subcategory': $result"
                }
            }
            catch {
                Write-Warning "Error configuring audit policy for '$subcategory': $_"
            }
        }
        
        # Configure PowerShell script block logging
        $psLoggingPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
        if (!(Test-Path $psLoggingPath)) {
            New-Item -Path $psLoggingPath -Force | Out-Null
        }
        Set-ItemProperty -Path $psLoggingPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord
        
        # Configure command line process auditing
        $cmdLinePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
        if (!(Test-Path $cmdLinePath)) {
            New-Item -Path $cmdLinePath -Force | Out-Null
        }
        Set-ItemProperty -Path $cmdLinePath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
    }
}

# NIST 3.3.8 - Audit Information Protection
function Configure-EventLogSecurity {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure event log security and retention"
    $nistControl = "3.3.8"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Configure Windows Event Log settings
        $logs = @(
            @{Name = 'Application'; MaxSize = 1024MB; Retention = 'Manual'}
            @{Name = 'Security'; MaxSize = 4096MB; Retention = 'Manual'}
            @{Name = 'System'; MaxSize = 1024MB; Retention = 'Manual'}
            @{Name = 'Microsoft-Windows-PowerShell/Operational'; MaxSize = 512MB; Retention = 'Manual'}
        )
        
        foreach ($log in $logs) {
            $logName = $log.Name
            
            # Set maximum log size
            wevtutil sl $logName /ms:$($log.MaxSize)
            
            # Set retention policy (manual = do not overwrite)
            wevtutil sl $logName /rt:false
            
            # Restrict access to security logs
            if ($logName -eq 'Security') {
                $sddl = "O:BAG:SYD:(A;;0x1;;;SY)(A;;0x5;;;BA)(A;;0x1;;;S-1-5-32-573)"
                wevtutil sl Security /ca:$sddl
            }
        }
        
        # Create event log backup directory
        $backupPath = "C:\Windows\System32\LogBackups"
        if (!(Test-Path $backupPath)) {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            
            # Restrict access to backup directory
            $acl = Get-Acl $backupPath
            $acl.SetAccessRuleProtection($true, $false)
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.AddAccessRule($adminRule)
            $acl.AddAccessRule($systemRule)
            Set-Acl -Path $backupPath -AclObject $acl
        }
    }
}

# NIST 3.3.4 - Audit Review, Analysis, and Reporting
function Enable-AuditCollection {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure centralized audit collection"
    $nistControl = "3.3.4"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Enable Windows Event Forwarding
        $wefService = Get-Service -Name "Wecsvc" -ErrorAction SilentlyContinue
        if ($wefService) {
            Set-Service -Name "Wecsvc" -StartupType Automatic
            Start-Service -Name "Wecsvc" -ErrorAction SilentlyContinue
        }
        
        # Configure Windows Event Collector
        wecutil qc -quiet
        
        # Enable remote management for event collection
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        
        # Configure WinRM for event forwarding
        winrm quickconfig -quiet
        winrm set winrm/config/service '@{AllowUnencrypted="false"}'
        winrm set winrm/config/service/auth '@{Kerberos="true"}'
        
        # Create scheduled task for event log export
        $taskName = "Export-SecurityLogs"
        $exportScript = @'
$date = Get-Date -Format "yyyyMMdd"
$exportPath = "C:\Windows\System32\LogBackups\Security_$date.evtx"
wevtutil epl Security $exportPath
# Compress older logs
Get-ChildItem "C:\Windows\System32\LogBackups\*.evtx" -Recurse | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | ForEach-Object {
    Compress-Archive -Path $_.FullName -DestinationPath "$($_.FullName).zip" -Force
    Remove-Item $_.FullName -Force
}
'@
        
        $action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$exportScript`""
        $trigger = New-ScheduledTaskTrigger -Daily -At 2:30am
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force
    }
}

# NIST 3.3.5 - Response to Audit Processing Failures
function Configure-AuditFailureResponse {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure audit failure handling"
    $nistControl = "3.3.5"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Configure audit failure response
        $auditPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        
        # Set crash on audit failure (0 = ignore, 1 = halt system, 2 = shutdown)
        # Using 1 for high security environments, 0 for normal operations
        Set-ItemProperty -Path $auditPath -Name "CrashOnAuditFail" -Value 0 -Type DWord
        
        # Configure alerts for audit log full
        $alertScript = @'
param($LogName)
$EventID = 1104  # Security log full
$Source = "Microsoft-Windows-Eventlog"
$Message = "Security audit log is full on $env:COMPUTERNAME"

# Create custom event
Write-EventLog -LogName Application -Source "AuditMonitor" -EventId 9999 -EntryType Error -Message $Message

# Send alert (implement your alerting mechanism here)
# Send-MailMessage -To "security@company.com" -Subject "Audit Log Full Alert" -Body $Message -SmtpServer "smtp.company.com"
'@
        
        # Create WMI event subscription for log full events
        $query = "SELECT * FROM __InstanceCreationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_NTLogEvent' AND TargetInstance.EventCode = 1104"
        
        $filterName = "AuditLogFullFilter"
        $consumerName = "AuditLogFullConsumer"
        
        # Remove existing if present
        Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='$filterName'" | Remove-WmiObject -ErrorAction SilentlyContinue
        Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='$consumerName'" | Remove-WmiObject -ErrorAction SilentlyContinue
        
        # Create new WMI event filter and consumer
        $filterArgs = @{
            Name = $filterName
            EventNamespace = "root\cimv2"
            QueryLanguage = "WQL"
            Query = $query
        }
        $filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments $filterArgs
        
        $consumerArgs = @{
            Name = $consumerName
            CommandLineTemplate = "powershell.exe -NoProfile -Command `"$alertScript`""
        }
        $consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments $consumerArgs
        
        # Bind filter to consumer
        $bindingArgs = @{
            Filter = $filter
            Consumer = $consumer
        }
        Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments $bindingArgs
    }
}

# NIST 3.3.9 - Protection of Audit Information
function Protect-AuditLogs {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Protect audit logs from unauthorized access"
    $nistControl = "3.3.9"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Create audit log integrity monitoring
        $monitorScript = @'
# Calculate and store hash of security logs
$logPath = "C:\Windows\System32\winevt\Logs"
$hashFile = "C:\Windows\System32\LogBackups\LogHashes.csv"

$hashes = @()
Get-ChildItem "$logPath\*.evtx" | ForEach-Object {
    $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256
    $hashes += [PSCustomObject]@{
        FileName = $_.Name
        Hash = $hash.Hash
        LastModified = $_.LastWriteTime
    }
}

$hashes | Export-Csv -Path $hashFile -NoTypeInformation

# Check for tampering
if (Test-Path $hashFile) {
    $oldHashes = Import-Csv $hashFile
    foreach ($oldHash in $oldHashes) {
        $currentFile = Get-Item "$logPath\$($oldHash.FileName)" -ErrorAction SilentlyContinue
        if ($currentFile) {
            $currentHash = Get-FileHash -Path $currentFile.FullName -Algorithm SHA256
            if ($currentHash.Hash -ne $oldHash.Hash) {
                Write-EventLog -LogName Application -Source "AuditMonitor" -EventId 9998 -EntryType Warning -Message "Potential tampering detected in $($oldHash.FileName)"
            }
        }
    }
}
'@
        
        # Create scheduled task for integrity monitoring
        $taskName = "Monitor-AuditLogIntegrity"
        $action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$monitorScript`""
        $trigger = New-ScheduledTaskTrigger -Daily -At 3am -RepetitionInterval (New-TimeSpan -Hours 6)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force
        
        # Configure file system auditing on log directories
        $logDirectories = @(
            "C:\Windows\System32\winevt\Logs",
            "C:\Windows\System32\LogBackups"
        )
        
        foreach ($dir in $logDirectories) {
            if (Test-Path $dir) {
                $acl = Get-Acl $dir
                $auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule(
                    "Everyone",
                    "Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership",
                    "ContainerInherit,ObjectInherit",
                    "None",
                    "Success,Failure"
                )
                $acl.AddAuditRule($auditRule)
                Set-Acl -Path $dir -AclObject $acl
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Enable-AuditLogging',
    'Configure-EventLogSecurity',
    'Enable-AuditCollection',
    'Configure-AuditFailureResponse',
    'Protect-AuditLogs'
)