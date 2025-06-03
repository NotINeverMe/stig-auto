<#
.SYNOPSIS
    Access control and authentication functions for NIST 800-171 compliance
.DESCRIPTION
    Implements access control configurations mapped to NIST controls
#>

# NIST 3.5.7, 3.5.8 - Identification and Authentication
function Set-PasswordPolicy {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure strong password policy"
    $nistControl = "3.5.7,3.5.8"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -Action {
        # Set local security policy
        $tempFile = "$env:TEMP\secpol.cfg"
        secedit /export /cfg $tempFile /quiet
        
        $content = Get-Content $tempFile
        $content = $content -replace "MinimumPasswordLength = \d+", "MinimumPasswordLength = 14"
        $content = $content -replace "PasswordComplexity = \d+", "PasswordComplexity = 1"
        $content = $content -replace "MinimumPasswordAge = \d+", "MinimumPasswordAge = 1"
        $content = $content -replace "MaximumPasswordAge = \d+", "MaximumPasswordAge = 60"
        $content = $content -replace "PasswordHistorySize = \d+", "PasswordHistorySize = 24"
        
        Set-Content -Path $tempFile -Value $content
        secedit /configure /db secedit.sdb /cfg $tempFile /quiet
        Remove-Item $tempFile -Force
        
        # Configure account lockout policy
        net accounts /lockoutthreshold:5 /lockoutwindow:15 /lockoutduration:15
    }
}

# NIST 3.1.13 - Remote Access
function Configure-RDPSecurity {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure secure RDP settings"
    $nistControl = "3.1.13,3.13.5"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -Action {
        # Enable RDP but with security settings
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
        
        # Force Network Level Authentication
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
        
        # Set minimum encryption level to High
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name MinEncryptionLevel -Value 3
        
        # Disable clipboard redirection
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name fDisableClip -Value 1
        
        # Disable drive redirection
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name fDisableCdm -Value 1
        
        # Set RDP port (optional - change from default 3389)
        # Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name PortNumber -Value 3390
        
        # Configure RDP firewall rule
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
        
        # Limit RDP access to specific group
        $rdpGroup = "Remote Desktop Users"
        if (!(Get-LocalGroup -Name $rdpGroup -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $rdpGroup -Description "Users allowed to connect via RDP"
        }
    }
}

# NIST 3.5.1, 3.5.2 - Authenticator Management
function Configure-LAPS {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure Local Administrator Password Solution (LAPS)"
    $nistControl = "3.5.1,3.5.2"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -Action {
        # Check if running on domain-joined machine
        $computerSystem = Get-WmiObject Win32_ComputerSystem
        if ($computerSystem.PartOfDomain -eq $false) {
            Write-HardeningLog "Computer is not domain-joined. LAPS requires domain membership." -Level Warning -NistControl $nistControl
            return
        }
        
        # Install LAPS if not present
        $lapsInstalled = Get-WmiObject -Query "SELECT * FROM Win32_Product WHERE Name LIKE '%Local Administrator Password Solution%'"
        
        if (!$lapsInstalled) {
            Write-HardeningLog "LAPS not installed. Downloading and installing..." -NistControl $nistControl
            
            $lapsUrl = "https://download.microsoft.com/download/C/7/A/C7AAD914-A8A6-4904-88A1-29E657445D03/LAPS.x64.msi"
            $lapsInstaller = "$env:TEMP\LAPS.x64.msi"
            
            Invoke-WebRequest -Uri $lapsUrl -OutFile $lapsInstaller
            Start-Process msiexec.exe -ArgumentList "/i `"$lapsInstaller`" /quiet" -Wait
            Remove-Item $lapsInstaller -Force
        }
        
        # Configure LAPS GPO settings via registry (would normally be done via GPO)
        $lapsRegPath = "HKLM:\SOFTWARE\Policies\Microsoft Services\AdmPwd"
        if (!(Test-Path $lapsRegPath)) {
            New-Item -Path $lapsRegPath -Force | Out-Null
        }
        
        # Enable LAPS
        Set-ItemProperty -Path $lapsRegPath -Name "AdmPwdEnabled" -Value 1 -Type DWord
        
        # Set password complexity
        Set-ItemProperty -Path $lapsRegPath -Name "PasswordComplexity" -Value 4 -Type DWord
        
        # Set password length
        Set-ItemProperty -Path $lapsRegPath -Name "PasswordLength" -Value 20 -Type DWord
        
        # Set password age (30 days)
        Set-ItemProperty -Path $lapsRegPath -Name "PasswordAgeDays" -Value 30 -Type DWord
    }
}

# NIST 3.5.3 - Multifactor Authentication
function Enable-MultifactorAuth {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure multifactor authentication requirements"
    $nistControl = "3.5.3"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -Action {
        # Configure Windows Hello for Business via registry
        $helloRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
        if (!(Test-Path $helloRegPath)) {
            New-Item -Path $helloRegPath -Force | Out-Null
        }
        
        # Enable Windows Hello for Business
        Set-ItemProperty -Path $helloRegPath -Name "Enabled" -Value 1 -Type DWord
        
        # Require PIN
        Set-ItemProperty -Path $helloRegPath -Name "RequireSecurityDevice" -Value 1 -Type DWord
        
        # Set minimum PIN length
        Set-ItemProperty -Path $helloRegPath -Name "MinimumPINLength" -Value 6 -Type DWord
        
        # Configure smart card requirements for domain accounts
        $scRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Set-ItemProperty -Path $scRegPath -Name "ScForceOption" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        
        Write-HardeningLog "MFA configuration applied. Additional setup required in Azure AD or on-premises AD." -Level Warning -NistControl $nistControl
    }
}

# NIST 3.1.5 - Access Control
function Configure-UserRights {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure user rights assignments"
    $nistControl = "3.1.5"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -Action {
        # Export current security policy
        $tempFile = "$env:TEMP\userrights.inf"
        secedit /export /areas USER_RIGHTS /cfg $tempFile /quiet
        
        # Read and modify the policy
        $content = Get-Content $tempFile
        
        # Ensure only Administrators can shut down the system
        $content = $content -replace "SeShutdownPrivilege = .*", "SeShutdownPrivilege = *S-1-5-32-544"
        
        # Deny guest account logon rights
        $content = $content -replace "SeDenyInteractiveLogonRight = .*", "SeDenyInteractiveLogonRight = *S-1-5-32-546,Guest"
        
        # Restrict who can access computer from network
        $content = $content -replace "SeNetworkLogonRight = .*", "SeNetworkLogonRight = *S-1-5-32-544,*S-1-5-32-545"
        
        Set-Content -Path $tempFile -Value $content
        
        # Apply the modified policy
        secedit /configure /db secedit.sdb /cfg $tempFile /areas USER_RIGHTS /quiet
        Remove-Item $tempFile -Force
    }
}

# NIST 3.1.1, 3.1.2 - Account Management
function Configure-AccountManagement {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $description = "Configure account management settings"
    $nistControl = "3.1.1,3.1.2"
    
    Invoke-HardeningAction -Description $description -NistControl $nistControl -Action {
        # Disable Guest account
        Disable-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
        
        # Rename Administrator account
        $adminAccount = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
        if ($adminAccount) {
            Rename-LocalUser -Name "Administrator" -NewName "LocalAdmin" -ErrorAction SilentlyContinue
        }
        
        # Set account expiration for temporary accounts
        $tempUsers = Get-LocalUser | Where-Object { $_.Description -like "*temp*" -or $_.Description -like "*temporary*" }
        foreach ($user in $tempUsers) {
            $expirationDate = (Get-Date).AddDays(90)
            Set-LocalUser -Name $user.Name -AccountExpires $expirationDate
        }
        
        # Configure inactive account auto-disable (via scheduled task)
        $taskName = "Disable-InactiveAccounts"
        $action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"Get-LocalUser | Where-Object {`$_.Enabled -and `$_.LastLogon -lt (Get-Date).AddDays(-90)} | Disable-LocalUser`""
        $trigger = New-ScheduledTaskTrigger -Daily -At 2am
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force
    }
}

Export-ModuleMember -Function @(
    'Set-PasswordPolicy',
    'Configure-RDPSecurity',
    'Configure-LAPS',
    'Enable-MultifactorAuth',
    'Configure-UserRights',
    'Configure-AccountManagement'
)