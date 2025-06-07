<#
.SYNOPSIS
    System and information protection functions for NIST 800-171 compliance
.DESCRIPTION
    Implements system and information integrity controls mapped to NIST controls
#>

# Helper function for logging
function Write-HardeningLog {
    param(
        [string]$Message,
        [string]$Level = "Info",
        [string]$NistControl = ""
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = if ($NistControl) { "[NIST: $NistControl]" } else { "" }
    $logMessage = "$timestamp [$Level] $prefix - $Message"
    Write-Host $logMessage
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

# NIST 3.14.1, 3.14.2 - System and Information Integrity
function Configure-WindowsDefender {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure Windows Defender with optimal security settings"
    $nistControl = "3.14.1,3.14.2"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Enable Windows Defender features
        Set-MpPreference -DisableRealtimeMonitoring $false
        Set-MpPreference -DisableBehaviorMonitoring $false
        Set-MpPreference -DisableBlockAtFirstSeen $false
        Set-MpPreference -DisableIOAVProtection $false
        Set-MpPreference -DisablePrivacyMode $false
        Set-MpPreference -DisableScriptScanning $false
        Set-MpPreference -DisableArchiveScanning $false
        Set-MpPreference -DisableEmailScanning $false
        
        # Configure cloud protection
        Set-MpPreference -MAPSReporting Advanced
        Set-MpPreference -SubmitSamplesConsent SendAllSamples
        Set-MpPreference -CloudBlockLevel High
        Set-MpPreference -CloudExtendedTimeout 50
        
        # Configure scanning options
        Set-MpPreference -ScanScheduleDay Everyday
        Set-MpPreference -ScanScheduleTime 120  # 2:00 AM
        Set-MpPreference -ScanScheduleQuickScanTime 180  # 3:00 AM
        Set-MpPreference -CheckForSignaturesBeforeRunningScan $true
        Set-MpPreference -SignatureUpdateInterval 1  # Every hour
        
        # Configure real-time protection
        Set-MpPreference -RealTimeScanDirection 0  # Both incoming and outgoing
        Set-MpPreference -DisableCatchupFullScan $false
        Set-MpPreference -DisableCatchupQuickScan $false
        
        # Configure PUA protection
        Set-MpPreference -PUAProtection Enabled
        
        # Configure network protection
        Set-MpPreference -EnableNetworkProtection Enabled
        
        # Configure exploit protection
        Set-ProcessMitigation -System -Enable DEP,SEHOP,CFG
        
        # Update signatures
        Update-MpSignature -ErrorAction SilentlyContinue
    }
}

# NIST 3.14.1 - Flaw Remediation
function Install-SecurityUpdates {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Install security updates from Windows Update"
    $nistControl = "3.14.1"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Check if PSWindowsUpdate module is installed
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-HardeningLog "Installing PSWindowsUpdate module..." -NistControl $nistControl
            Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck
        }
        
        Import-Module PSWindowsUpdate
        
        # Get available security updates (try different parameter combinations for compatibility)
        try {
            $updates = Get-WindowsUpdate -Category "Security Updates" -NotInstalled
        } catch {
            Write-Warning "NotInstalled parameter not supported, trying alternative approach..."
            try {
                $updates = Get-WindowsUpdate | Where-Object { $_.Status -eq "Available" -and $_.Categories -like "*Security*" }
            } catch {
                Write-Warning "Alternative approach failed, trying basic Get-WindowsUpdate..."
                $updates = Get-WindowsUpdate | Where-Object { $_.Categories -like "*Security*" }
            }
        }
        
        if ($updates.Count -eq 0) {
            Write-HardeningLog "No security updates available" -Level Info -NistControl $nistControl
            return
        }
        
        Write-HardeningLog "Found $($updates.Count) security updates to install" -NistControl $nistControl
        
        # Install updates
        $installResult = Install-WindowsUpdate -Category "Security Updates" -AcceptAll -IgnoreReboot -Verbose
        
        # Check if reboot is required
        if (Get-WURebootStatus -Silent) {
            Write-HardeningLog "System reboot required to complete updates" -Level Warning -NistControl $nistControl
        }
    }
}

# NIST 3.1.19, 3.1.20 - Device Control
function Enable-DeviceControl {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure device control policies"
    $nistControl = "3.1.19,3.1.20"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Disable USB storage devices
        $usbStorPath = "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR"
        Set-ItemProperty -Path $usbStorPath -Name "Start" -Value 4 -Type DWord
        
        # Configure removable storage policies
        $removableStoragePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices"
        if (!(Test-Path $removableStoragePath)) {
            New-Item -Path $removableStoragePath -Force | Out-Null
        }
        
        # Deny all removable storage
        $deviceClasses = @(
            "{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}",  # Generic removable storage
            "{53f56307-b6bf-11d0-94f2-00a0c91efb8b}",  # Disk drives
            "{53f5630a-b6bf-11d0-94f2-00a0c91efb8b}",  # CD/DVD
            "{53f56308-b6bf-11d0-94f2-00a0c91efb8b}"   # Tape drives
        )
        
        foreach ($deviceClass in $deviceClasses) {
            $devicePath = Join-Path $removableStoragePath $deviceClass
            if (!(Test-Path $devicePath)) {
                New-Item -Path $devicePath -Force | Out-Null
            }
            Set-ItemProperty -Path $devicePath -Name "Deny_All" -Value 1 -Type DWord
        }
        
        # Configure Windows Defender Device Guard
        $deviceGuardPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
        if (!(Test-Path $deviceGuardPath)) {
            New-Item -Path $deviceGuardPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $deviceGuardPath -Name "EnableVirtualizationBasedSecurity" -Value 1 -Type DWord
        Set-ItemProperty -Path $deviceGuardPath -Name "RequirePlatformSecurityFeatures" -Value 1 -Type DWord
        
        # Configure BitLocker for removable drives
        $bitlockerPath = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
        if (!(Test-Path $bitlockerPath)) {
            New-Item -Path $bitlockerPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $bitlockerPath -Name "RDVDenyCrossOrg" -Value 1 -Type DWord
        Set-ItemProperty -Path $bitlockerPath -Name "RDVDenyWriteAccess" -Value 1 -Type DWord
    }
}

# NIST 3.4.8 - Application Execution Control
function Configure-AppLocker {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure AppLocker application control policies"
    $nistControl = "3.4.8"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Start Application Identity service (required for AppLocker)
        Set-Service -Name "AppIDSvc" -StartupType Automatic
        Start-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        
        # Create default AppLocker rules
        $appLockerPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="Allow Everyone in Program Files" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7b51" Name="Allow Everyone in Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="Allow Administrators Everywhere" Description="" UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>
  <RuleCollection Type="Msi" EnforcementMode="Enabled">
    <FilePublisherRule Id="b7af7102-efde-4369-8a89-7a6a392d1473" Name="Allow all digitally signed MSI" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="*" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
  <RuleCollection Type="Script" EnforcementMode="Enabled">
    <FilePathRule Id="06dce67b-934c-454f-a263-2515c8796a5d" Name="Allow Everyone in Program Files" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="9e4b6b2d-94d1-4c09-896e-23e6d128d89b" Name="Allow Everyone in Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
        
        # Save policy to temp file
        $policyFile = "$env:TEMP\AppLockerPolicy.xml"
        Set-Content -Path $policyFile -Value $appLockerPolicy
        
        # Import the policy
        Set-AppLockerPolicy -XmlPolicy $policyFile -ErrorAction SilentlyContinue
        
        # Clean up
        Remove-Item $policyFile -Force
        
        # Configure AppLocker event log
        wevtutil sl "Microsoft-Windows-AppLocker/EXE and DLL" /ms:104857600
        wevtutil sl "Microsoft-Windows-AppLocker/MSI and Script" /ms:104857600
    }
}

# NIST 3.14.6, 3.14.7 - Information System Monitoring
function Enable-AdvancedThreatProtection {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Enable advanced threat detection and monitoring"
    $nistControl = "3.14.6,3.14.7"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Enable Attack Surface Reduction rules
        $asrRules = @{
            # Block executable content from email client and webmail
            "BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550" = 1
            # Block all Office applications from creating child processes
            "D4F940AB-401B-4EFC-AADC-AD5F3C50688A" = 1
            # Block Office applications from creating executable content
            "3B576869-A4EC-4529-8536-B80A7769E899" = 1
            # Block Office applications from injecting code into other processes
            "75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84" = 1
            # Block JavaScript or VBScript from launching downloaded executable content
            "D3E037E1-3EB8-44C8-A917-57927947596D" = 1
            # Block execution of potentially obfuscated scripts
            "5BEB7EFE-FD9A-4556-801D-275E5FFC04CC" = 1
            # Block Win32 API calls from Office macros
            "92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B" = 1
        }
        
        foreach ($rule in $asrRules.GetEnumerator()) {
            Add-MpPreference -AttackSurfaceReductionRules_Ids $rule.Key -AttackSurfaceReductionRules_Actions $rule.Value
        }
        
        # Enable controlled folder access
        Set-MpPreference -EnableControlledFolderAccess Enabled
        
        # Add protected folders
        $protectedFolders = @(
            "$env:USERPROFILE\Documents",
            "$env:USERPROFILE\Desktop",
            "C:\Windows\System32\LogBackups"
        )
        
        foreach ($folder in $protectedFolders) {
            if (Test-Path $folder) {
                Add-MpPreference -ControlledFolderAccessProtectedFolders $folder
            }
        }
        
        # Configure Windows Defender ATP settings
        $atpPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection"
        if (!(Test-Path $atpPath)) {
            New-Item -Path $atpPath -Force | Out-Null
        }
        
        # Enable sample submission
        Set-ItemProperty -Path $atpPath -Name "AllowSampleCollection" -Value 1 -Type DWord
        
        # Configure EDR in block mode
        Set-ItemProperty -Path $atpPath -Name "ForceDefenderPassiveMode" -Value 0 -Type DWord
    }
}

# NIST 3.13.16 - Protection of CUI at Rest
function Enable-BitLockerEncryption {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Enable BitLocker drive encryption"
    $nistControl = "3.13.16"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Check if BitLocker is available
        $bitlockerFeature = Get-WindowsFeature -Name BitLocker -ErrorAction SilentlyContinue
        if ($bitlockerFeature -and $bitlockerFeature.InstallState -ne 'Installed') {
            Install-WindowsFeature -Name BitLocker -IncludeAllSubFeature -IncludeManagementTools
            Write-HardeningLog "BitLocker feature installed. Reboot required." -Level Warning -NistControl $nistControl
            return
        }
        
        # Get system drive
        $systemDrive = $env:SystemDrive
        
        # Check if already encrypted
        $bitlockerStatus = Get-BitLockerVolume -MountPoint $systemDrive -ErrorAction SilentlyContinue
        if ($bitlockerStatus -and $bitlockerStatus.ProtectionStatus -eq 'On') {
            Write-HardeningLog "BitLocker already enabled on system drive" -Level Info -NistControl $nistControl
            return
        }
        
        # Enable BitLocker with TPM
        Enable-BitLocker -MountPoint $systemDrive -EncryptionMethod Aes256 -UsedSpaceOnly -TpmProtector -ErrorAction SilentlyContinue
        
        # Add recovery password protector
        Add-BitLockerKeyProtector -MountPoint $systemDrive -RecoveryPasswordProtector
        
        # Backup recovery information to AD if domain joined
        $computerSystem = Get-WmiObject Win32_ComputerSystem
        if ($computerSystem.PartOfDomain) {
            Backup-BitLockerKeyProtector -MountPoint $systemDrive -KeyProtectorId (Get-BitLockerVolume -MountPoint $systemDrive).KeyProtector[1].KeyProtectorId
        }
        
        # Start encryption
        Resume-BitLocker -MountPoint $systemDrive
        
        Write-HardeningLog "BitLocker encryption started on system drive" -Level Success -NistControl $nistControl
    }
}

Export-ModuleMember -Function @(
    'Configure-WindowsDefender',
    'Install-SecurityUpdates',
    'Enable-DeviceControl',
    'Configure-AppLocker',
    'Enable-AdvancedThreatProtection',
    'Enable-BitLockerEncryption'
)