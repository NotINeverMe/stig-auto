param(
    [switch]$Build,
    [switch]$Test,
    [switch]$Push,
    [ValidateSet("all", "unit", "powerstig", "hardening", "integration")]
    [string]$TestType = "all",
    [ValidateSet("servercore", "server", "both")]
    [string]$ContainerType = "servercore",
    [string]$Registry = "stig-auto",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

# Script configuration
$script:Config = @{
    ProjectRoot = Split-Path -Parent $PSScriptRoot
    DockerPath = Join-Path $PSScriptRoot "docker/windows"
    TestResultsPath = Join-Path $PSScriptRoot "test-results"
    Images = @{
        ServerCore = "$Registry/windows-test:core"
        Server = "$Registry/windows-test:full"
    }
}

# Ensure we're in the right directory
Set-Location $script:Config.ProjectRoot

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    
    $color = switch ($Type) {
        "Info" { "Cyan" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        default { "White" }
    }
    
    Write-Host "[$Type] $Message" -ForegroundColor $color
}

function Test-DockerRunning {
    try {
        docker version | Out-Null
        return $true
    } catch {
        Write-Status "Docker is not running or not installed" "Error"
        return $false
    }
}

function Build-Containers {
    Write-Status "Building Windows Docker containers..." "Info"
    
    $dockerfiles = @{
        ServerCore = "docker/windows/Dockerfile.servercore"
        Server = "docker/windows/Dockerfile.server"
    }
    
    $toBuild = if ($ContainerType -eq "both") { 
        $dockerfiles.Keys 
    } else { 
        @($ContainerType) 
    }
    
    foreach ($type in $toBuild) {
        Write-Status "Building $type container..." "Info"
        
        $dockerfile = $dockerfiles[$type]
        $image = $script:Config.Images[$type]
        
        $buildArgs = @(
            "build",
            "-f", $dockerfile,
            "-t", $image,
            "--build-arg", "BUILDKIT_INLINE_CACHE=1",
            "."
        )
        
        $result = docker @buildArgs
        
        if ($LASTEXITCODE -ne 0) {
            Write-Status "Failed to build $type container" "Error"
            return $false
        }
        
        Write-Status "Successfully built $type container" "Success"
    }
    
    return $true
}

function Run-Tests {
    param([string]$Type = "all", [string]$Container = "servercore")
    
    Write-Status "Running $Type tests in $Container container..." "Info"
    
    # Ensure test results directory exists
    if (-not (Test-Path $script:Config.TestResultsPath)) {
        New-Item -ItemType Directory -Force -Path $script:Config.TestResultsPath | Out-Null
    }
    
    # Clean previous results
    Get-ChildItem $script:Config.TestResultsPath -File | Remove-Item -Force
    
    $image = if ($Container -eq "servercore") { 
        $script:Config.Images.ServerCore 
    } else { 
        $script:Config.Images.Server 
    }
    
    $isolation = if ($Container -eq "servercore") { "process" } else { "hyperv" }
    
    $runArgs = @(
        "run",
        "--rm",
        "--isolation=$isolation",
        "-v", "$($script:Config.ProjectRoot)/scripts:C:/stig-auto/scripts:ro",
        "-v", "$($script:Config.ProjectRoot)/tests:C:/stig-auto/tests:ro",
        "-v", "$($script:Config.ProjectRoot)/roles:C:/stig-auto/roles:ro",
        "-v", "$($script:Config.ProjectRoot)/ansible:C:/stig-auto/ansible:ro",
        "-v", "$($script:Config.TestResultsPath):C:/test-results",
        "-e", "CI=true",
        $image,
        "-File", "C:/stig-auto/docker/test-scripts/run-tests.ps1",
        "-TestType", $Type
    )
    
    $result = docker @runArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Tests failed" "Error"
        return $false
    }
    
    Write-Status "Tests completed successfully" "Success"
    
    # Display results summary if available
    $summaryPath = Join-Path $script:Config.TestResultsPath "test-summary.json"
    if (Test-Path $summaryPath) {
        $summary = Get-Content $summaryPath | ConvertFrom-Json
        Write-Status "Test Summary:" "Info"
        $summary.Results | Format-Table -AutoSize
    }
    
    return $true
}

function Push-Images {
    Write-Status "Pushing images to registry..." "Info"
    
    $images = if ($ContainerType -eq "both") { 
        $script:Config.Images.Values 
    } else {
        @($script:Config.Images[$ContainerType])
    }
    
    foreach ($image in $images) {
        Write-Status "Pushing $image..." "Info"
        docker push $image
        
        if ($LASTEXITCODE -ne 0) {
            Write-Status "Failed to push $image" "Error"
            return $false
        }
    }
    
    Write-Status "All images pushed successfully" "Success"
    return $true
}

function Clean-Environment {
    Write-Status "Cleaning Docker environment..." "Info"
    
    # Remove containers
    docker ps -a -q --filter "ancestor=$($script:Config.Images.ServerCore)" | ForEach-Object {
        docker rm -f $_
    }
    docker ps -a -q --filter "ancestor=$($script:Config.Images.Server)" | ForEach-Object {
        docker rm -f $_
    }
    
    # Remove images
    docker rmi -f $script:Config.Images.ServerCore 2>$null
    docker rmi -f $script:Config.Images.Server 2>$null
    
    # Clean test results
    if (Test-Path $script:Config.TestResultsPath) {
        Remove-Item -Path $script:Config.TestResultsPath -Recurse -Force
    }
    
    Write-Status "Environment cleaned" "Success"
}

# Main execution
if (-not (Test-DockerRunning)) {
    exit 1
}

if ($Clean) {
    Clean-Environment
    if (-not ($Build -or $Test -or $Push)) {
        exit 0
    }
}

$success = $true

if ($Build) {
    $success = Build-Containers
    if (-not $success) {
        Write-Status "Build failed" "Error"
        exit 1
    }
}

if ($Test -and $success) {
    $success = Run-Tests -Type $TestType -Container $ContainerType
    if (-not $success) {
        Write-Status "Tests failed" "Error"
        exit 1
    }
}

if ($Push -and $success) {
    $success = Push-Images
    if (-not $success) {
        Write-Status "Push failed" "Error"
        exit 1
    }
}

if ($success) {
    Write-Status "All operations completed successfully" "Success"
    exit 0
} else {
    Write-Status "Operations failed" "Error"
    exit 1
}