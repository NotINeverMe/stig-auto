#Requires -RunAsAdministrator
#Requires -Module PowerSTIG

param(
    [string[]]$Categories = @('CAT_I', 'CAT_II'),
    [switch]$WhatIf
)

Write-Host "PowerSTIG Remediation Script" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan

# Import PowerSTIG
try {
    Import-Module PowerSTIG -ErrorAction Stop
} catch {
    Write-Error "PowerSTIG module not found. Please install it first: Install-Module PowerSTIG"
    exit 1
}

# Determine OS
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
Write-Host "Detected OS: $($osInfo.OsType) $($osInfo.Version)" -ForegroundColor Green

# Map categories to severity levels
$severityMap = @{
    'CAT_I' = 'high'
    'CAT_II' = 'medium'
    'CAT_III' = 'low'
}

$selectedSeverities = @()
foreach ($cat in $Categories) {
    if ($severityMap.ContainsKey($cat)) {
        $selectedSeverities += $severityMap[$cat]
    }
}

Write-Host "Remediating categories: $($Categories -join ', ')" -ForegroundColor Yellow
Write-Host "Severity levels: $($selectedSeverities -join ', ')" -ForegroundColor Yellow

try {
    # Get the STIG
    $stig = Get-Stig -Technology $osInfo.OsType -TechnologyVersion $osInfo.Version
    
    # Generate DSC configuration
    $configName = "STIGRemediation"
    $outputPath = Join-Path $env:TEMP $configName
    
    Write-Host "Generating DSC configuration..." -ForegroundColor Cyan
    
    # Create configuration script content
    $configScript = @"
Configuration $configName
{
    Import-DscResource -ModuleName PowerSTIG
    
    Node localhost
    {
        WindowsClient BaseLine
        {
            OsVersion   = '$($osInfo.Version)'
            StigVersion = '$($stig.Version.ToString())'
            Exception   = @{}
            OrgSettings = @{}
            SkipRule    = @()
        }
    }
}

$configName -OutputPath '$outputPath'
"@

    # For Windows Server, adjust the resource type
    if ($osInfo.OsType -eq 'WindowsServer') {
        $configScript = $configScript -replace 'WindowsClient BaseLine', 'WindowsServer BaseLine'
    }
    
    # Execute configuration script
    $scriptPath = Join-Path $env:TEMP "$configName.ps1"
    $configScript | Out-File -FilePath $scriptPath -Encoding UTF8
    
    & $scriptPath
    
    if ($WhatIf) {
        Write-Host "WhatIf: Would apply DSC configuration from $outputPath" -ForegroundColor Yellow
        Write-Host "Configuration MOF generated but not applied." -ForegroundColor Yellow
        
        # Show what would be changed
        $testResults = Test-DscConfiguration -Path $outputPath -Detailed
        Write-Host ""
        Write-Host "Current non-compliant settings:" -ForegroundColor Red
        $testResults.ResourcesNotInDesiredState | ForEach-Object {
            Write-Host "  - $($_.ResourceId)" -ForegroundColor Red
        }
    } else {
        Write-Host "Applying DSC configuration..." -ForegroundColor Cyan
        
        # Apply configuration
        Start-DscConfiguration -Path $outputPath -Wait -Verbose -Force
        
        Write-Host "Remediation complete!" -ForegroundColor Green
        
        # Test compliance
        Write-Host "Testing compliance..." -ForegroundColor Cyan
        $testResults = Test-DscConfiguration -Detailed
        
        if ($testResults.InDesiredState) {
            Write-Host "System is now compliant with STIG requirements!" -ForegroundColor Green
        } else {
            Write-Warning "Some settings could not be remediated:"
            $testResults.ResourcesNotInDesiredState | ForEach-Object {
                Write-Warning "  - $($_.ResourceId)"
            }
        }
    }
    
    # Clean up
    Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
    
} catch {
    Write-Error "Remediation failed: $_"
    exit 1
}