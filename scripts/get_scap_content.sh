#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 [--os <os_id>]" >&2
    echo "  --os  Override detected OS (e.g. rhel8, ubuntu22, windows2022)" >&2
}

# Parse command line arguments
OS_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --os)
            OS_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Default: parse OS from /etc/os-release
if [[ -z "$OS_ID" ]]; then
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        VERSION_MAJOR="${VERSION_ID%%.*}"
        OS_ID="${ID}${VERSION_MAJOR}"
    else
        echo "Error: Cannot determine OS. Use --os parameter or ensure /etc/os-release exists." >&2
        exit 1
    fi
fi

# Create scap_content directory
mkdir -p scap_content

# Generate filename with current date
CURRENT_DATE=$(date +"%Y-%m")
FILENAME="scap_content/${OS_ID}-${CURRENT_DATE}.xml"

echo "Fetching SCAP content for ${OS_ID}..."

# Try DoD Cyber Exchange first
DOD_URL="https://public.cyber.mil/stigs/scap/"
if curl -f -s "$DOD_URL" > /dev/null 2>&1; then
    echo "Attempting to download from DoD Cyber Exchange..."
    # Note: This would need specific implementation based on DoD site structure
    echo "Warning: DoD site access requires manual implementation of specific URLs"
fi

# Fallback to SCAP Security Guide GitHub releases
echo "Falling back to SCAP Security Guide GitHub releases..."
GITHUB_API="https://api.github.com/repos/ComplianceAsCode/content/releases/latest"
# Find asset matching the OS ID
DOWNLOAD_URL=$(curl -s "$GITHUB_API" \
    | grep -o '"browser_download_url": "[^"]*' \
    | cut -d'"' -f4 \
    | grep -i "$OS_ID" \
    | head -n 1)

if [[ -n "$DOWNLOAD_URL" ]]; then
    echo "Downloading from: $DOWNLOAD_URL"
    curl -L -o "$FILENAME" "$DOWNLOAD_URL"
    echo "SCAP content saved to: $FILENAME"
else
    echo "Error: Could not find SCAP content for $OS_ID"
    exit 1
fi

echo "SCAP content download complete"
