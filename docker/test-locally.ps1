param(
    [ValidateSet("build", "test", "clean", "all")]
    [string]$Action = "all",
    
    [ValidateSet("servercore", "server", "both")]
    [string]$ContainerType = "servercore",
    
    [ValidateSet("unit", "powerstig", "hardening", "integration", "all")]
    [string]$TestType = "unit",
    
    [switch]$Force,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Configuration
$script:Config = @{
    ProjectRoot = Split-Path -Parent $PSScriptRoot
    Images = @{
        ServerCore = "stig-test:servercore"
        Server = "stig-test:server"
    }
    TestResultsPath = Join-Path $PSScriptRoot "../test-results"
}

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function Test-DockerWindows {
    try {
        $dockerInfo = docker info --format '{{.OSType}}'
        if ($dockerInfo -ne 'windows') {
            Write-Warning "Docker is not in Windows container mode. Please switch to Windows containers."
            Write-Host "In Docker Desktop: Right-click system tray → Switch to Windows containers"
            return $false
        }
        return $true
    } catch {
        Write-Error "Docker is not running or not accessible: $_"
        return $false
    }
}

function Build-Container {
    param([string]$Type)
    
    Write-Status "Building $Type container..." "Yellow"
    
    $dockerfile = switch ($Type) {
        "servercore" { "docker/windows/Dockerfile.servercore" }
        "server" { "docker/windows/Dockerfile.server" }
    }
    
    $image = $script:Config.Images[$Type]
    
    $buildArgs = @(
        "build",
        "-f", $dockerfile,
        "-t", $image,
        "--no-cache"
    )
    
    if ($Force) {
        $buildArgs += "--force-rm"
    }
    
    $buildArgs += "."
    
    Write-Status "Running: docker $($buildArgs -join ' ')" "Gray"
    
    Push-Location $script:Config.ProjectRoot
    try {
        & docker @buildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Docker build failed with exit code $LASTEXITCODE"
        }
        Write-Status "Successfully built $Type container" "Green"
    } finally {
        Pop-Location
    }
}

function Test-Container {
    param([string]$Type, [string]$TestType)
    
    Write-Status "Running $TestType tests in $Type container..." "Yellow"
    
    # Ensure test results directory exists
    if (-not (Test-Path $script:Config.TestResultsPath)) {
        New-Item -ItemType Directory -Force -Path $script:Config.TestResultsPath | Out-Null
    }
    
    # Clean previous results
    Get-ChildItem $script:Config.TestResultsPath -File -ErrorAction SilentlyContinue | Remove-Item -Force
    
    $image = $script:Config.Images[$Type]
    
    $runArgs = @(
        "run",
        "--rm",
        "--isolation=process"
    )
    
    # Mount source directories as read-only
    $mounts = @(
        "$($script:Config.ProjectRoot)/scripts:C:/stig-auto/scripts:ro",
        "$($script:Config.ProjectRoot)/tests:C:/stig-auto/tests:ro",
        "$($script:Config.ProjectRoot)/roles:C:/stig-auto/roles:ro",
        "$($script:Config.ProjectRoot)/ansible:C:/stig-auto/ansible:ro",
        "$($script:Config.TestResultsPath):C:/test-results"
    )
    
    foreach ($mount in $mounts) {
        $runArgs += "-v", $mount
    }
    
    # Add environment variables
    $runArgs += "-e", "CI=true"
    $runArgs += "-e", "LOCAL_TEST=true"
    
    # Add image and command
    $runArgs += $image
    $runArgs += "-File", "C:/stig-auto/docker/test-scripts/run-tests.ps1"
    $runArgs += "-TestType", $TestType
    
    if ($Verbose) {
        $runArgs += "-Verbose"
    }
    
    Write-Status "Running: docker $($runArgs -join ' ')" "Gray"
    
    & docker @runArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Tests failed with exit code $LASTEXITCODE" "Red"
        return $false
    }
    
    Write-Status "Tests completed successfully" "Green"
    
    # Display results summary
    $summaryPath = Join-Path $script:Config.TestResultsPath "test-summary.json"
    if (Test-Path $summaryPath) {
        $summary = Get-Content $summaryPath | ConvertFrom-Json
        Write-Status "Test Summary:" "Cyan"
        Write-Host "  Duration: $($summary.Duration.TotalSeconds) seconds" -ForegroundColor Gray
        Write-Host "  Success: $($summary.Success)" -ForegroundColor $(if ($summary.Success) { "Green" } else { "Red" })
        
        if ($summary.Results) {
            $summary.Results.PSObject.Properties | ForEach-Object {
                $status = if ($_.Value) { "PASS" } else { "FAIL" }
                $color = if ($_.Value) { "Green" } else { "Red" }
                Write-Host "  $($_.Name): $status" -ForegroundColor $color
            }
        }
    }
    
    return $true
}

function Clean-Environment {
    Write-Status "Cleaning Docker environment..." "Yellow"
    
    # Remove containers
    $containers = docker ps -a -q --filter "ancestor=$($script:Config.Images.ServerCore)" 2>$null
    if ($containers) {
        docker rm -f $containers 2>$null
    }
    
    $containers = docker ps -a -q --filter "ancestor=$($script:Config.Images.Server)" 2>$null
    if ($containers) {
        docker rm -f $containers 2>$null
    }
    
    # Remove images if Force is specified
    if ($Force) {
        docker rmi -f $script:Config.Images.ServerCore 2>$null
        docker rmi -f $script:Config.Images.Server 2>$null
    }
    
    # Clean test results
    if (Test-Path $script:Config.TestResultsPath) {
        Remove-Item -Path $script:Config.TestResultsPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Status "Environment cleaned" "Green"
}

function Show-Usage {
    Write-Host @"
Windows Docker STIG Testing Script

USAGE:
    .\docker\test-locally.ps1 [OPTIONS]

OPTIONS:
    -Action <build|test|clean|all>     What to do (default: all)
    -ContainerType <servercore|server|both>  Which container to use (default: servercore)
    -TestType <unit|powerstig|hardening|integration|all>  Which tests to run (default: unit)
    -Force                             Force rebuild/clean
    -Verbose                           Verbose output

EXAMPLES:
    # Build and test everything
    .\docker\test-locally.ps1

    # Just build containers
    .\docker\test-locally.ps1 -Action build

    # Run unit tests only
    .\docker\test-locally.ps1 -Action test -TestType unit

    # Run all tests on server container
    .\docker\test-locally.ps1 -ContainerType server -TestType all

    # Clean everything and rebuild
    .\docker\test-locally.ps1 -Force

REQUIREMENTS:
    - Windows 10/11 with Docker Desktop
    - Docker Desktop switched to Windows containers
    - Administrator privileges (recommended)
"@
}

# Main execution
Write-Status "Windows Docker STIG Testing Script" "Cyan"
Write-Status "Project Root: $($script:Config.ProjectRoot)" "Gray"

# Check prerequisites
if (-not (Test-DockerWindows)) {
    exit 1
}

# Handle actions
switch ($Action) {
    "build" {
        if ($ContainerType -eq "both") {
            Build-Container "servercore"
            Build-Container "server"
        } else {
            Build-Container $ContainerType
        }
    }
    
    "test" {
        if ($ContainerType -eq "both") {
            $success = $true
            $success = Test-Container "servercore" $TestType -and $success
            $success = Test-Container "server" $TestType -and $success
            
            if (-not $success) {
                exit 1
            }
        } else {
            if (-not (Test-Container $ContainerType $TestType)) {
                exit 1
            }
        }
    }
    
    "clean" {
        Clean-Environment
    }
    
    "all" {
        # Build
        if ($ContainerType -eq "both") {
            Build-Container "servercore"
            Build-Container "server"
        } else {
            Build-Container $ContainerType
        }
        
        # Test
        if ($ContainerType -eq "both") {
            $success = $true
            $success = Test-Container "servercore" $TestType -and $success
            $success = Test-Container "server" $TestType -and $success
            
            if (-not $success) {
                exit 1
            }
        } else {
            if (-not (Test-Container $ContainerType $TestType)) {
                exit 1
            }
        }
    }
    
    default {
        Show-Usage
        exit 1
    }
}

Write-Status "All operations completed successfully!" "Green"