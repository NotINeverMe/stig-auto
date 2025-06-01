#Requires -RunAsAdministrator

# Enable WinRM
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Enable-PSRemoting -Force

# Install Chocolatey if not present
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# Install required packages
choco install git ansible openscap -y

# Clone repo to C:\stig-pipe if not present
if (!(Test-Path "C:\stig-pipe")) {
    Write-Host "Cloning repository to C:\stig-pipe"
    git clone https://github.com/NotINeverMe/stig-auto.git "C:\stig-pipe"
}

# Change to repo directory and install Ansible roles
Set-Location "C:\stig-pipe"
ansible-galaxy install -r ansible\requirements.yml --roles-path roles\

# Execute remediation pipeline
Write-Host "Getting SCAP content..."
& scripts\get_scap_content.ps1

Write-Host "Running baseline scan..."
& scripts\scan.ps1 -Baseline

Write-Host "Running Ansible remediation..."
ansible-playbook ansible\remediate.yml -t CAT_I,CAT_II

Write-Host "Verifying remediation..."
& scripts\verify.ps1

Write-Host "Remediation complete" -ForegroundColor Green
