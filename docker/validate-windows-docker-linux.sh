#!/bin/bash
# Script to validate Windows Docker setup on Linux systems
# This simulates what would happen on a Windows system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Windows Docker Pipeline Validation (Linux Simulation) ===${NC}"
echo "This script validates the Windows Docker setup without actually running containers"
echo

# Function to check file exists
check_file() {
    local file=$1
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} Found: $file"
        return 0
    else
        echo -e "${RED}✗${NC} Missing: $file"
        return 1
    fi
}

# Function to check directory exists
check_dir() {
    local dir=$1
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC} Found directory: $dir"
        return 0
    else
        echo -e "${RED}✗${NC} Missing directory: $dir"
        return 1
    fi
}

# Function to validate PowerShell syntax
validate_powershell() {
    local file=$1
    echo -n "  Checking PowerShell syntax in $(basename "$file")... "
    
    # Basic syntax checks
    if grep -q 'param\s*(' "$file" && ! grep -q '^)' "$file"; then
        echo -e "${RED}Missing closing parenthesis for param block${NC}"
        return 1
    fi
    
    # Check for common syntax issues
    local open_braces=$(grep -o '{' "$file" | wc -l)
    local close_braces=$(grep -o '}' "$file" | wc -l)
    if [ "$open_braces" -ne "$close_braces" ]; then
        echo -e "${RED}Unmatched braces: $open_braces open, $close_braces close${NC}"
        return 1
    fi
    
    echo -e "${GREEN}OK${NC}"
    return 0
}

# Track errors
ERRORS=0

echo -e "${YELLOW}1. Checking Docker directory structure...${NC}"
check_dir "docker/windows" || ((ERRORS++))
check_dir "docker/test-scripts" || ((ERRORS++))

echo -e "\n${YELLOW}2. Checking Dockerfile existence...${NC}"
check_file "docker/windows/Dockerfile.servercore" || ((ERRORS++))
check_file "docker/windows/Dockerfile.server" || ((ERRORS++))
check_file "docker/windows/docker-compose.yml" || ((ERRORS++))

echo -e "\n${YELLOW}3. Checking test scripts...${NC}"
check_file "docker/test-scripts/run-tests.ps1" || ((ERRORS++))
check_file "docker/test-scripts/validate-stig.ps1" || ((ERRORS++))
check_file "docker/build-and-test.ps1" || ((ERRORS++))

echo -e "\n${YELLOW}4. Checking GitHub workflow...${NC}"
check_file ".github/workflows/windows-docker-tests.yml" || ((ERRORS++))

echo -e "\n${YELLOW}5. Validating PowerShell scripts...${NC}"
for ps1_file in docker/**/*.ps1; do
    if [ -f "$ps1_file" ]; then
        validate_powershell "$ps1_file" || ((ERRORS++))
    fi
done

echo -e "\n${YELLOW}6. Checking Docker Compose syntax...${NC}"
if command -v docker-compose &> /dev/null; then
    cd docker/windows
    if docker-compose config > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Docker Compose configuration is valid"
    else
        echo -e "${RED}✗${NC} Docker Compose configuration has errors"
        ((ERRORS++))
    fi
    cd ../..
else
    echo -e "${YELLOW}!${NC} docker-compose not installed, skipping validation"
fi

echo -e "\n${YELLOW}7. Checking for required source directories...${NC}"
check_dir "scripts" || ((ERRORS++))
check_dir "tests" || ((ERRORS++))
check_dir "roles" || ((ERRORS++))
check_dir "ansible" || ((ERRORS++))

echo -e "\n${YELLOW}8. Checking for Windows-specific test files...${NC}"
check_file "tests/windows/WindowsHardening.Tests.ps1" || ((ERRORS++))
check_dir "scripts/windows-hardening" || ((ERRORS++))

echo -e "\n${YELLOW}9. Validating Dockerfile syntax...${NC}"
for dockerfile in docker/windows/Dockerfile*; do
    echo -n "  Checking $(basename "$dockerfile")... "
    
    # Check for escape character
    if head -n 1 "$dockerfile" | grep -q '^# escape=`$'; then
        echo -e "${GREEN}escape character defined${NC}"
    else
        echo -e "${RED}missing escape character definition${NC}"
        ((ERRORS++))
    fi
    
    # Check for ARG WINDOWS_VERSION
    if grep -q '^ARG WINDOWS_VERSION=' "$dockerfile"; then
        echo -e "    ${GREEN}✓${NC} ARG WINDOWS_VERSION found"
    else
        echo -e "    ${RED}✗${NC} Missing ARG WINDOWS_VERSION"
        ((ERRORS++))
    fi
done

echo -e "\n${YELLOW}10. Creating test summary report...${NC}"
cat > docker/test-validation-report.txt << EOF
Windows Docker Test Pipeline Validation Report
Generated: $(date)
System: $(uname -a)

Structure Check: $([ $ERRORS -eq 0 ] && echo "PASSED" || echo "FAILED")
Total Errors: $ERRORS

Files Checked:
$(find docker -type f -name "*.ps1" -o -name "*.yml" -o -name "Dockerfile*" | sort)

Next Steps:
1. Commit these changes to git
2. Push to GitHub to trigger Windows CI/CD tests
3. Or run on a Windows system with Docker Desktop

To run on Windows:
  .\docker\build-and-test.ps1 -Build -Test

To run specific tests:
  docker-compose -f docker\windows\docker-compose.yml run stig-test-core
EOF

echo -e "${GREEN}✓${NC} Created validation report: docker/test-validation-report.txt"

# Summary
echo -e "\n${YELLOW}=== VALIDATION SUMMARY ===${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC} The Windows Docker pipeline is ready."
    echo -e "\nNext steps:"
    echo -e "  1. Commit changes: ${YELLOW}git add -A && git commit -m \"Add Windows Docker testing pipeline\"${NC}"
    echo -e "  2. Push to trigger CI: ${YELLOW}git push origin feature/powerstig-windows-implementation${NC}"
    echo -e "  3. The GitHub Actions workflow will run automatically on Windows runners"
else
    echo -e "${RED}❌ Found $ERRORS error(s)${NC} that need to be fixed."
    echo -e "Please review the errors above and fix them before proceeding."
fi

exit $ERRORS