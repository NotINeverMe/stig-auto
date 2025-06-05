#!/bin/bash

# Script to show the exact Docker commands that would run on Windows
# This helps validate the setup without actually running Windows containers

echo "=== Windows Docker Test Commands ==="
echo
echo "These are the commands that would run on a Windows system with Docker Desktop:"
echo

echo "1. VERIFY DOCKER SETUP:"
echo "   docker version"
echo "   docker info --format '{{.OSType}}'  # Should return 'windows'"
echo

echo "2. BUILD CONTAINERS:"
echo "   # Server Core (lightweight)"
echo "   docker build -f docker/windows/Dockerfile.servercore -t stig-test:servercore ."
echo
echo "   # Full Server (comprehensive)"
echo "   docker build -f docker/windows/Dockerfile.server -t stig-test:server ."
echo

echo "3. RUN UNIT TESTS:"
echo "   docker run --rm \\"
echo "     --isolation=process \\"
echo "     -v \"\${PWD}/scripts:C:/stig-auto/scripts:ro\" \\"
echo "     -v \"\${PWD}/tests:C:/stig-auto/tests:ro\" \\"
echo "     -v \"\${PWD}/roles:C:/stig-auto/roles:ro\" \\"
echo "     -v \"\${PWD}/test-results:C:/test-results\" \\"
echo "     -e CI=true \\"
echo "     stig-test:servercore \\"
echo "     -File C:/stig-auto/docker/test-scripts/run-tests.ps1 -TestType unit"
echo

echo "4. RUN POWERSTIG TESTS:"
echo "   docker run --rm \\"
echo "     --isolation=process \\"
echo "     -v \"\${PWD}/scripts:C:/stig-auto/scripts:ro\" \\"
echo "     -v \"\${PWD}/tests:C:/stig-auto/tests:ro\" \\"
echo "     -v \"\${PWD}/test-results:C:/test-results\" \\"
echo "     stig-test:servercore \\"
echo "     -File C:/stig-auto/docker/test-scripts/run-tests.ps1 -TestType powerstig"
echo

echo "5. RUN ALL TESTS:"
echo "   docker run --rm \\"
echo "     --isolation=process \\"
echo "     -v \"\${PWD}/scripts:C:/stig-auto/scripts:ro\" \\"
echo "     -v \"\${PWD}/tests:C:/stig-auto/tests:ro\" \\"
echo "     -v \"\${PWD}/roles:C:/stig-auto/roles:ro\" \\"
echo "     -v \"\${PWD}/test-results:C:/test-results\" \\"
echo "     stig-test:servercore \\"
echo "     -File C:/stig-auto/docker/test-scripts/run-tests.ps1 -TestType all"
echo

echo "6. USING THE HELPER SCRIPTS:"
echo "   # PowerShell (recommended)"
printf "   .\\\\docker\\\\test-locally.ps1\n"
printf "   .\\\\docker\\\\test-locally.ps1 -TestType unit\n"
printf "   .\\\\docker\\\\test-locally.ps1 -ContainerType server -TestType all\n"
echo
echo "   # Command Line"
printf "   docker\\\\test-locally.cmd\n"
echo

echo "7. USING DOCKER COMPOSE:"
echo "   cd docker/windows"
echo "   docker-compose build"
echo "   docker-compose run --rm stig-test-core"
echo

echo "8. CLEAN UP:"
echo "   docker container prune -f"
echo "   docker image rm stig-test:servercore stig-test:server"
echo "   docker system prune -f"
echo

echo "=== File Structure Validation ==="
echo "Checking that all required files exist:"
echo

files=(
    "docker/windows/Dockerfile.servercore"
    "docker/windows/Dockerfile.server" 
    "docker/windows/docker-compose.yml"
    "docker/test-scripts/run-tests.ps1"
    "docker/test-scripts/validate-stig.ps1"
    "docker/build-and-test.ps1"
    "docker/test-locally.ps1"
    "docker/test-locally.cmd"
)

all_good=true
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file"
    else
        echo "✗ $file (MISSING)"
        all_good=false
    fi
done

echo
if [ "$all_good" = true ]; then
    echo "✅ All required files are present\!"
    echo "📁 You can now copy this project to a Windows machine and run the tests."
else
    echo "❌ Some files are missing. Please check the file structure."
fi

echo
echo "=== Next Steps ==="
echo "1. Copy this project to a Windows 10/11 machine with Docker Desktop"
echo "2. Ensure Docker Desktop is in 'Windows containers' mode"
printf "3. Run: .\\\\docker\\\\test-locally.ps1\n"
echo "4. Check test results in the test-results/ directory"

