[CmdletBinding()]
param(
    # Override detected OS (e.g. rhel8, ubuntu22, windows2022)
    [string]$OS
)

# Check if we're on Windows and should use PowerSTIG
if ($PSVersionTable.PSVersion.Major -ge 5 -and $PSVersionTable.Platform -ne 'Unix') {
    Write-Host "Windows detected - PowerSTIG will handle STIG data automatically" -ForegroundColor Cyan
    Write-Host "PowerSTIG downloads and caches STIG content on first use." -ForegroundColor Green
    
    # Ensure PowerSTIG is available
    if (Get-Module -ListAvailable -Name PowerSTIG) {
        Import-Module PowerSTIG
        Write-Host "PowerSTIG module is ready. STIG content will be downloaded when running scans." -ForegroundColor Green
        
        # Create a placeholder file to satisfy downstream scripts
        New-Item -ItemType Directory -Force -Path "scap_content" | Out-Null
        $placeholderFile = "scap_content\powerstig-managed.txt"
        "PowerSTIG manages STIG content automatically for Windows systems" | Out-File $placeholderFile
        
        exit 0
    } else {
        Write-Warning "PowerSTIG module not found. Please run bootstrap.ps1 first."
        Write-Host "Falling back to traditional SCAP content download..."
    }
}

# Default: get OS from system
if (-not $OS) {
    $caption = (Get-CimInstance Win32_OperatingSystem).Caption
    if ($caption -match '(\d{4})') {
        $OSID = "windows$($Matches[1])"
    } else {
        throw "Unable to determine Windows version from '$caption'"
    }
    $OS = $OSID
} else {
    $OSID = $OS
}

# Create scap_content directory
New-Item -ItemType Directory -Force -Path "scap_content" | Out-Null

# Generate filename with current quarter
$CurrentDate = Get-Date -Format "yyyy-MM"
$SafeOS = $OSID -replace '[^\w\-]', '-'
$Filename = "scap_content\$SafeOS-$CurrentDate.xml"

Write-Host "Fetching SCAP content for $OS..."

try {
    $DownloadUrl = $null
    
    # Try NIST NCP first for Windows 2022
    if ($OSID.ToLower() -eq 'windows2022') {
        Write-Host "Attempting to download Windows 2022 SCAP content from NIST NCP..."
        $NistUrl = "https://ncp.nist.gov/checklist/1034/SCAP_1.3_SCAP_Benchmark_U_MS_Windows_Server_2022_STIG_V2R4.zip"
        $ZipFile = "scap_content\windows2022-v2r4.zip"
        
        try {
            $response = Invoke-WebRequest -Uri $NistUrl -OutFile $ZipFile -PassThru
            
            # Check if we got a ZIP file or HTML page
            $fileBytes = [System.IO.File]::ReadAllBytes($ZipFile)
            $isZip = ($fileBytes.Length -gt 4 -and 
                     $fileBytes[0] -eq 0x50 -and $fileBytes[1] -eq 0x4B -and 
                     ($fileBytes[2] -eq 0x03 -or $fileBytes[2] -eq 0x05))
            
            if ($isZip) {
                # Extract the ZIP file
                $ExtractPath = "scap_content\windows2022"
                New-Item -ItemType Directory -Force -Path $ExtractPath | Out-Null
                Expand-Archive -Path $ZipFile -DestinationPath $ExtractPath -Force
                
                # Find the SCAP XML file
                $ScapFile = Get-ChildItem -Path $ExtractPath -Filter "*.xml" -Recurse | Select-Object -First 1
                if ($ScapFile) {
                    Copy-Item $ScapFile.FullName $Filename
                    Write-Host "SCAP content saved to: $Filename"
                    Remove-Item $ZipFile -Force
                    $DownloadUrl = $NistUrl  # Mark as successful
                }
            } else {
                Write-Warning "NIST returned HTML page instead of ZIP file (possibly access restricted)"
                Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "NIST download failed: $_"
            Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Fallback to DoD Cyber Exchange (manual implementation needed)
    if (-not $DownloadUrl) {
        Write-Host "Attempting to download from DoD Cyber Exchange..."
        Write-Warning "DoD site access requires CAC authentication - manual implementation needed"
    }
    
    # Final fallback to SCAP Security Guide GitHub releases
    if (-not $DownloadUrl) {
        Write-Host "Falling back to SCAP Security Guide GitHub releases..."
        $GitHubApi = "https://api.github.com/repos/ComplianceAsCode/content/releases/latest"
        $Release = Invoke-RestMethod -Uri $GitHubApi

        switch ($OSID.ToLower()) {
            'rhel8' { $assetPattern = 'rhel8' }
            'ubuntu22' { $assetPattern = 'ubuntu-22\.04|ubuntu2204' }
            'ubuntu2204' { $assetPattern = 'ubuntu-22\.04|ubuntu2204' }
            'windows2022' { $assetPattern = 'windows-server-2022|windows2022' }
            Default { $assetPattern = [Regex]::Escape($OSID) }
        }

        $Asset = $Release.assets | Where-Object { $_.name -match $assetPattern } | Select-Object -First 1
        $DownloadUrl = $Asset.browser_download_url
        
        if ($DownloadUrl) {
            Write-Host "Downloading from: $DownloadUrl"
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $Filename
            Unblock-File -Path $Filename
            Write-Host "SCAP content saved to: $Filename"
        }
    }
    
    if (-not $DownloadUrl) {
        throw "Could not find SCAP content for $OS from any source"
    }
}
catch {
    Write-Error "Error: Could not download SCAP content for $OS - $_"
    exit 1
}

Write-Host "SCAP content download complete"
