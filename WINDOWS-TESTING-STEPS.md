# Windows Docker Testing Steps

## Prerequisites on Windows Machine

1. **Windows 10/11 Pro or Enterprise** (Home edition won't work)
2. **Docker Desktop for Windows** installed and running
3. **PowerShell 5.1+** or **PowerShell 7+**

## Step-by-Step Instructions

### 1. Setup Docker Desktop
```cmd
# Download and install Docker Desktop from:
# https://www.docker.com/products/docker-desktop

# After installation, ensure you're in Windows container mode:
# Right-click Docker Desktop system tray icon → "Switch to Windows containers"
```

### 2. Verify Docker Setup
```powershell
# Check Docker is running
docker version

# Verify Windows container mode
docker info --format "{{.OSType}}"
# Should return: windows
```

### 3. Clone the Repository
```powershell
# Clone the repo
git clone https://github.com/NotINeverMe/stig-auto.git
cd stig-auto

# Switch to our feature branch
git checkout feature/windows-docker-testing
```

### 4. Run Tests Using Our Scripts

#### Option A: Use the PowerShell script (Recommended)
```powershell
# Run all tests
.\docker\test-locally.ps1

# Run specific test types
.\docker\test-locally.ps1 -TestType unit
.\docker\test-locally.ps1 -TestType powerstig
.\docker\test-locally.ps1 -TestType hardening

# Use different container types
.\docker\test-locally.ps1 -ContainerType server
.\docker\test-locally.ps1 -ContainerType both

# Force rebuild
.\docker\test-locally.ps1 -Force -Verbose
```

#### Option B: Use the batch file
```cmd
# Simple execution
docker\test-locally.cmd
```

#### Option C: Manual Docker commands
```powershell
# Build the container
docker build -f docker\windows\Dockerfile.servercore -t stig-test:local .

# Run basic test
docker run --rm stig-test:local -Command "Write-Host 'Container works!'"

# Run our test script
docker run --rm `
  -v "${PWD}\scripts:C:\stig-auto\scripts:ro" `
  -v "${PWD}\tests:C:\stig-auto\tests:ro" `
  -v "${PWD}\test-results:C:\test-results" `
  stig-test:local `
  -File C:\stig-auto\docker\test-scripts\run-tests.ps1 -TestType unit
```

### 5. Check Results
```powershell
# View test results
ls test-results\

# View test summary
Get-Content test-results\test-summary.json | ConvertFrom-Json

# View detailed logs
Get-Content test-results\test-run-*.log
```

## Expected Output

If working correctly, you should see:
```
Building Windows container...
Successfully built container
Running unit tests...
All tests passed!
Test Summary:
  Duration: 45.2 seconds
  Success: True
```

## Troubleshooting

### If Docker build fails:
```powershell
# Check Docker is in Windows mode
docker info --format "{{.OSType}}"

# Try pulling base image manually
docker pull mcr.microsoft.com/windows/servercore:ltsc2022
```

### If PowerShell modules fail to install:
```powershell
# Check internet connectivity in container
docker run --rm mcr.microsoft.com/windows/servercore:ltsc2022 powershell Test-NetConnection google.com

# Try with no cache
docker build --no-cache -f docker\windows\Dockerfile.servercore -t stig-test:local .
```

### If tests fail:
```powershell
# Run container interactively for debugging
docker run -it --rm stig-test:local powershell

# Inside container, check modules
PS C:\> Get-Module -ListAvailable | Where-Object Name -like "*STIG*"
PS C:\> Test-Path C:\stig-auto\docker\test-scripts\run-tests.ps1
```