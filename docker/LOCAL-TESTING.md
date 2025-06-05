# Local Windows Docker Testing Guide

This guide shows how to run the Windows STIG Docker tests on your local Windows machine.

## Prerequisites

### Required Software
- **Windows 10/11 Pro or Enterprise** (with Hyper-V support)
- **Docker Desktop for Windows** (latest version)
- **PowerShell 5.1+** or **PowerShell Core 7+**

### Setup Steps

1. **Install Docker Desktop**
   - Download from: https://www.docker.com/products/docker-desktop
   - Install with default settings
   - Restart your computer if prompted

2. **Switch to Windows Containers**
   ```
   Right-click Docker system tray icon → "Switch to Windows containers"
   ```
   
3. **Verify Docker Setup**
   ```cmd
   docker version
   docker info --format "{{.OSType}}"
   ```
   The OS Type should show `windows`.

## Quick Start

### Option 1: PowerShell Script (Recommended)

```powershell
# Navigate to project directory
cd C:\path\to\stig-auto

# Run all tests (build + test)
.\docker\test-locally.ps1

# Or with specific options
.\docker\test-locally.ps1 -TestType unit -Verbose
```

### Option 2: Command Line Batch File

```cmd
# Navigate to project directory
cd C:\path\to\stig-auto

# Run all tests
docker\test-locally.cmd

# The batch file will call the PowerShell script
```

### Option 3: Manual Docker Commands

```powershell
# Build the container
docker build -f docker/windows/Dockerfile.servercore -t stig-test:servercore .

# Run unit tests
docker run --rm `
  -v "${PWD}/scripts:C:/stig-auto/scripts:ro" `
  -v "${PWD}/tests:C:/stig-auto/tests:ro" `
  -v "${PWD}/test-results:C:/test-results" `
  stig-test:servercore `
  -File C:/stig-auto/docker/test-scripts/run-tests.ps1 -TestType unit
```

## Test Options

### Test Types
- **unit** - PowerShell module unit tests using Pester
- **powerstig** - PowerSTIG module validation and DSC compilation
- **hardening** - Windows hardening module tests
- **integration** - Full pipeline integration tests
- **all** - Run all test types

### Container Types
- **servercore** - Lightweight Windows Server Core (recommended for most tests)
- **server** - Full Windows Server with desktop experience (for comprehensive testing)

## Usage Examples

```powershell
# Build containers only
.\docker\test-locally.ps1 -Action build

# Run specific test type
.\docker\test-locally.ps1 -TestType powerstig

# Test both container types
.\docker\test-locally.ps1 -ContainerType both

# Force rebuild and test
.\docker\test-locally.ps1 -Force

# Clean up containers and images
.\docker\test-locally.ps1 -Action clean -Force

# Run verbose tests on full server container
.\docker\test-locally.ps1 -ContainerType server -TestType all -Verbose
```

## Using Docker Compose

```powershell
# Navigate to docker/windows directory
cd docker\windows

# Build all services
docker-compose build

# Run specific service
docker-compose run --rm stig-test-core

# Run with custom command
docker-compose run --rm stig-test-core powershell `
  -File C:/stig-auto/docker/test-scripts/run-tests.ps1 -TestType unit
```

## Test Results

Test results are saved to the `test-results/` directory:

```
test-results/
├── test-summary.json          # Overall test summary
├── pester-results.xml         # Unit test results (JUnit format)
├── coverage.xml               # Code coverage report
├── stig-validation-report.json # PowerSTIG validation results
└── test-run-*.log            # Detailed test logs
```

### Viewing Results

```powershell
# View test summary
Get-Content test-results\test-summary.json | ConvertFrom-Json | Format-List

# View Pester results in browser (if HTML report exists)
Invoke-Item test-results\pester-results.html

# Check logs
Get-Content test-results\test-run-*.log -Tail 50
```

## Troubleshooting

### Common Issues

1. **"Docker is not in Windows container mode"**
   ```
   Solution: Right-click Docker Desktop → Switch to Windows containers
   ```

2. **"Access denied" or permission errors**
   ```
   Solution: Run PowerShell as Administrator
   ```

3. **Container build timeouts**
   ```
   Solution: Increase Docker Desktop memory/CPU limits
   Docker Desktop → Settings → Resources
   ```

4. **PowerShell module installation fails**
   ```
   Solution: Check internet connection and firewall settings
   May need to configure proxy settings in Docker Desktop
   ```

5. **Out of disk space**
   ```
   Solution: Clean up Docker images and containers
   docker system prune -a --volumes
   ```

### Debug Mode

Run containers interactively for debugging:

```powershell
# Start interactive PowerShell session in container
docker run -it --rm stig-test:servercore powershell

# Inside container, run tests manually
PS C:\stig-auto> .\docker\test-scripts\run-tests.ps1 -TestType unit -Verbose

# Check module availability
PS C:\stig-auto> Get-Module -ListAvailable | Where-Object Name -like "*STIG*"
```

### Performance Tips

1. **Use Server Core for faster builds** (default)
2. **Increase Docker memory** to 8GB+ for better performance
3. **Enable BuildKit** for faster builds:
   ```cmd
   set DOCKER_BUILDKIT=1
   ```
4. **Use .dockerignore** to exclude unnecessary files (already included)

## Build Times

Expected build times on modern hardware:
- **Server Core container**: 15-25 minutes
- **Full Server container**: 25-35 minutes
- **Test execution**: 2-5 minutes per test type

## Integration with IDEs

### Visual Studio Code
1. Install Docker extension
2. Open project in VS Code
3. Use integrated terminal to run tests
4. View test results in built-in terminal

### PowerShell ISE
1. Open test scripts directly
2. Run individual test functions
3. Debug PowerShell modules

## Next Steps

After local testing succeeds:
1. Commit changes to git
2. Push to trigger GitHub Actions CI/CD
3. Create pull request for code review
4. Deploy to production environments

For questions or issues, check the project documentation or create an issue in the GitHub repository.