<#
.SYNOPSIS
    Security baseline configuration functions for NIST 800-171 compliance
.DESCRIPTION
    Implements security baseline configurations mapped to NIST controls
#>

# Helper logging function
function Write-HardeningLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',
        [string]$NistControl = ''
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = if ($NistControl) { "[$NistControl]" } else { "" }
    $logEntry = "$timestamp [$Level] $prefix - $Message"
    
    $color = switch ($Level) {
        'Info' { 'White' }
        'Warning' { 'Yellow' }  
        'Error' { 'Red' }
        'Success' { 'Green' }
        default { 'White' }
    }
    
    Write-Host $logEntry -ForegroundColor $color
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

# NIST 3.4.2, 3.4.6 - Configuration Management
function Set-SecureExecutionPolicy {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Set PowerShell execution policy to RemoteSigned"
    $nistControl = "3.4.2,3.4.6"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        Set-ExecutionPolicy RemoteSigned -Force -Scope LocalMachine
    }
}

# NIST 3.13.1, 3.13.5 - Boundary Protection
function Enable-WindowsFirewall {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Enable Windows Firewall for all profiles"
    $nistControl = "3.13.1,3.13.5"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
        
        # Configure default actions
        Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block -DefaultOutboundAction Allow
        
        # Enable logging
        Set-NetFirewallProfile -Profile Domain,Public,Private -LogBlocked True -LogMaxSizeKilobytes 4096
    }
}

# NIST 3.13.8, 3.13.11 - Communications Protection
function Disable-LegacyProtocols {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $protocols = @(
        @{Name = 'SMBv1'; NistControl = '3.13.8'}
        @{Name = 'TLS1.0'; NistControl = '3.13.11'}
        @{Name = 'TLS1.1'; NistControl = '3.13.11'}
    )
    
    foreach ($protocol in $protocols) {
        $description = "Disable legacy protocol: $($protocol.Name)"
        
        Invoke-HardeningAction -Description $description -NistControl $protocol.NistControl -DryRun:$DryRun -Action {
            switch ($protocol.Name) {
                'SMBv1' {
                    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
                    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
                }
                'TLS1.0' {
                    New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -Force
                    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -Name 'Enabled' -Value 0 -PropertyType 'DWord' -Force
                    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -Name 'DisabledByDefault' -Value 1 -PropertyType 'DWord' -Force
                }
                'TLS1.1' {
                    New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server' -Force
                    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server' -Name 'Enabled' -Value 0 -PropertyType 'DWord' -Force
                    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server' -Name 'DisabledByDefault' -Value 1 -PropertyType 'DWord' -Force
                }
            }
        }
    }
}

# NIST 3.13.11 - Cryptographic Protection
function Set-FIPSMode {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Enable FIPS 140-2 compliant cryptography"
    $nistControl = "3.13.11"
    
    # First check current status
    $registryPath = "HKLM:\System\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy"
    $currentValue = $null
    
    if (Test-Path $registryPath) {
        $currentValue = (Get-ItemProperty -Path $registryPath -Name Enabled -ErrorAction SilentlyContinue).Enabled
    }
    
    if ($currentValue -eq 1) {
        Write-Host "FIPS mode is already enabled" -ForegroundColor Green
        return $true
    }
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        if (!(Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force | Out-Null
        }
        Set-ItemProperty -Path $registryPath -Name Enabled -Value 1 -Type DWord
        Write-Host "FIPS mode enabled. System restart required." -ForegroundColor Yellow
    }
}

# NIST 3.4.6, 3.4.7 - Least Functionality
function Disable-UnnecessaryServices {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $servicesToDisable = @(
        @{Name = 'Fax'; DisplayName = 'Fax Service'}
        @{Name = 'RemoteRegistry'; DisplayName = 'Remote Registry'}
        @{Name = 'TapiSrv'; DisplayName = 'Telephony'}
        @{Name = 'Messenger'; DisplayName = 'Messenger'}
        @{Name = 'Alerter'; DisplayName = 'Alerter'}
        @{Name = 'ClipSrv'; DisplayName = 'ClipBook'}
        @{Name = 'Browser'; DisplayName = 'Computer Browser'}
    )
    
    foreach ($service in $servicesToDisable) {
        $description = "Disable unnecessary service: $($service.DisplayName)"
        $nistControl = "3.4.6,3.4.7"
        
        Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
            $svc = Get-Service -Name $service.Name -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service.Name -StartupType Disabled
            }
        }
    }
}

# NIST 3.12.1, 3.12.2 - Security Assessment
function Apply-STIGBaseline {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [string]$StigVersion = 'Windows_Server-2022-MS-3.1'
    )
    
    $description = "Apply DISA STIG baseline using PowerSTIG"
    $nistControl = "3.12.1,3.12.2"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -DryRun:$DryRun -Action {
        # Check if PowerSTIG is installed
        if (-not (Get-Module -ListAvailable -Name 'PowerSTIG')) {
            Write-HardeningLog "Installing PowerSTIG module..." -NistControl $nistControl
            Install-Module -Name PowerSTIG -Force -SkipPublisherCheck -AllowClobber
        }
        
        Import-Module PowerSTIG
        
        # Backup registry before applying STIG
        $backupPath = "$env:TEMP\PreSTIG_RegistryBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
        reg export HKLM $backupPath /y
        Write-HardeningLog "Registry backed up to: $backupPath" -NistControl $nistControl
        
        # Apply STIG configuration
        $stigPath = "$env:TEMP\STIG_Config"
        if (!(Test-Path $stigPath)) {
            New-Item -ItemType Directory -Path $stigPath -Force | Out-Null
        }
        
        # Generate and apply STIG configuration
        $configuration = @"
configuration WindowsServerSTIG
{
    Import-DscResource -ModuleName PowerSTIG

    Node localhost
    {
        WindowsServer STIGBaseline
        {
            OsVersion   = '2022'
            OsRole      = 'MS'
            SkipRule    = @()
        }
    }
}
"@
        
        $configFile = Join-Path $stigPath "WindowsServerSTIG.ps1"
        Set-Content -Path $configFile -Value $configuration
        
        . $configFile
        WindowsServerSTIG -OutputPath $stigPath
        
        Start-DscConfiguration -Path $stigPath -Wait -Verbose -Force
    }
}

Export-ModuleMember -Function @(
    'Set-SecureExecutionPolicy',
    'Enable-WindowsFirewall',
    'Disable-LegacyProtocols',
    'Set-FIPSMode',
    'Disable-UnnecessaryServices',
    'Apply-STIGBaseline'
)