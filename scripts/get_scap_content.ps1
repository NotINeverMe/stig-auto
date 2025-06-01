param(
    [string]$OS = $null
)

# Default: get OS from system
if (-not $OS) {
    $OS = (Get-CimInstance Win32_OperatingSystem).Caption
}

# Create scap_content directory
New-Item -ItemType Directory -Force -Path "scap_content" | Out-Null

# Generate filename with current quarter
$CurrentDate = Get-Date -Format "yyyy-MM"
$SafeOS = $OS -replace '[^\w\-]', '-'
$Filename = "scap_content\$SafeOS-$CurrentDate.xml"

Write-Host "Fetching SCAP content for $OS..."

try {
    # Try DoD Cyber Exchange
    $DoDUrl = "https://public.cyber.mil/stigs/scap/"
    Write-Host "Attempting to download from DoD Cyber Exchange..."
    
    # Note: This would need specific implementation based on DoD site structure
    Write-Warning "DoD site access requires manual implementation of specific URLs"
    
    # Fallback to SCAP Security Guide GitHub releases
    Write-Host "Falling back to SCAP Security Guide GitHub releases..."
    $GitHubApi = "https://api.github.com/repos/ComplianceAsCode/content/releases/latest"
    $Release = Invoke-RestMethod -Uri $GitHubApi
    $DownloadUrl = $Release.assets[0].browser_download_url
    
    if ($DownloadUrl) {
        Write-Host "Downloading from: $DownloadUrl"
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $Filename
        
        # Unblock the file
        Unblock-File -Path $Filename
        
        Write-Host "SCAP content saved to: $Filename"
    } else {
        throw "Could not find SCAP content for $OS"
    }
}
catch {
    Write-Error "Error: Could not download SCAP content for $OS - $_"
    exit 1
}

Write-Host "SCAP content download complete"
