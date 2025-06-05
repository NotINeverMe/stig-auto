# Windows Docker Testing for STIG Automation

This directory contains Docker configurations for testing Windows STIG compliance and hardening scripts in containerized environments.

## Overview

The Windows Docker testing setup provides:
- Isolated testing environments for STIG compliance validation
- CI/CD integration for automated testing
- Support for multiple Windows Server versions
- PowerSTIG and hardening module testing

## Prerequisites

### Local Development
- Windows 10/11 Pro or Enterprise (with Hyper-V)
- Docker Desktop for Windows
- Windows containers mode enabled

### CI/CD (GitHub Actions)
- Runs on `windows-2022` runners
- Automatically configured for Windows containers

## Container Types

### 1. **Server Core** (`Dockerfile.servercore`)
- Lightweight Windows Server Core image
- Best for unit tests and script validation
- Uses process isolation for better performance
- Includes PowerSTIG, Pester, and core modules

### 2. **Full Server** (`Dockerfile.server`)
- Full Windows Server with desktop experience
- Required for comprehensive STIG testing
- Uses Hyper-V isolation
- Includes all optional modules and features

## Quick Start

### Building Containers

```powershell
# Build Server Core container
docker build -f docker/windows/Dockerfile.servercore -t stig-test:core .

# Build Full Server container
docker build -f docker/windows/Dockerfile.server -t stig-test:full .

# Or use the helper script
.\docker\build-and-test.ps1 -Build
```

### Running Tests

```powershell
# Run all tests
.\docker\build-and-test.ps1 -Test

# Run specific test type
.\docker\build-and-test.ps1 -Test -TestType unit

# Run tests in specific container
.\docker\build-and-test.ps1 -Test -ContainerType server
```

### Using Docker Compose

```powershell
cd docker/windows

# Run all services
docker-compose up

# Run specific service
docker-compose run stig-test-core

# Run with custom test type
docker-compose run stig-test-core powershell -File C:/stig-auto/docker/test-scripts/run-tests.ps1 -TestType unit
```

## Test Types

### Unit Tests (`unit`)
- Pester tests for PowerShell modules
- Syntax validation
- Function testing
- Code coverage analysis

### PowerSTIG Tests (`powerstig`)
- PowerSTIG module availability
- STIG data validation
- DSC compilation tests
- Configuration testing

### Hardening Tests (`hardening`)
- Windows hardening module validation
- NIST 800-171 control testing
- Dry-run execution
- Module import verification

### Integration Tests (`integration`)
- Full pipeline testing
- Bootstrap process validation
- Ansible syntax checking
- End-to-end workflow

## CI/CD Integration

The GitHub Actions workflow (`windows-docker-tests.yml`) provides:
- Automated testing on push/PR
- Matrix testing across container types
- Test result artifacts
- Multi-version Windows testing

### Workflow Triggers
- Push to main/develop branches
- Pull requests to main
- Manual workflow dispatch
- Path-based triggers for Windows files

## Directory Structure

```
docker/
├── windows/
│   ├── Dockerfile.servercore    # Lightweight container
│   ├── Dockerfile.server        # Full Windows container
│   ├── docker-compose.yml       # Compose configuration
│   └── README.md               # This file
├── test-scripts/
│   ├── run-tests.ps1           # Main test runner
│   └── validate-stig.ps1       # STIG validation script
└── build-and-test.ps1          # Helper script
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STIG_PROFILE` | Windows STIG profile to test | `windows2022` |
| `TEST_MODE` | Testing mode indicator | `docker` |
| `PESTER_OUTPUT_DIRECTORY` | Test results location | `C:\test-results` |
| `FULL_STIG_TEST` | Enable comprehensive testing | `false` |

## Limitations

### Container Limitations
- Cannot modify kernel-level settings
- Limited Group Policy access
- No domain join capabilities
- Service installation restrictions
- Registry modifications may be limited

### Testing Scope
- Focus on script logic validation
- Use dry-run/WhatIf modes
- Mock system calls where needed
- Validate without applying changes

## Troubleshooting

### Common Issues

1. **Container build fails**
   ```powershell
   # Ensure Windows containers mode
   & "$env:ProgramFiles\Docker\Docker\DockerCli.exe" -SwitchDaemon
   ```

2. **Isolation errors**
   ```powershell
   # Check Windows version compatibility
   docker version
   ```

3. **Module installation fails**
   ```powershell
   # Run with elevated privileges
   docker build --no-cache -f Dockerfile.servercore .
   ```

### Debug Mode

```powershell
# Run interactive container
docker run -it --rm stig-test:core powershell

# Check module availability
Get-Module -ListAvailable | Where-Object Name -like "*STIG*"

# Test script manually
& C:/stig-auto/docker/test-scripts/run-tests.ps1 -Verbose
```

## Best Practices

1. **Container Size**
   - Use Server Core for most tests
   - Reserve Full Server for integration tests
   - Clean up images regularly

2. **Test Isolation**
   - Mount scripts as read-only
   - Use separate test results volume
   - Don't persist container state

3. **Performance**
   - Use process isolation when possible
   - Cache PowerShell modules in image
   - Parallelize independent tests

4. **Security**
   - Don't include credentials in images
   - Use minimal required privileges
   - Scan images for vulnerabilities

## Contributing

When adding new tests:
1. Update test runner script for new test types
2. Add appropriate volume mounts in docker-compose
3. Document any new environment requirements
4. Update CI/CD workflow if needed

## Future Enhancements

- [ ] Support for Windows Server 2016
- [ ] Kubernetes Job definitions
- [ ] Test result dashboards
- [ ] Performance benchmarking
- [ ] Security scanning integration