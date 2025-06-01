#!/usr/bin/env bash

set -euo pipefail

# Parse command line arguments
MODE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --baseline)
            MODE="baseline"
            shift
            ;;
        --after)
            MODE="after"
            shift
            ;;
        *)
            echo "Usage: $0 [--baseline|--after]"
            echo "  --baseline: Run baseline scan before remediation"
            echo "  --after:    Run scan after remediation"
            exit 1
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "Error: Must specify --baseline or --after"
    exit 1
fi

# Determine OS and choose default STIG profile
DEFAULT_PROFILE=""
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    case "${ID}" in
        rhel*|centos*|rocky*|almalinux*)
            DEFAULT_PROFILE="xccdf_org.ssgproject.content_profile_stig"
            ;;
        ubuntu*)
            DEFAULT_PROFILE="xccdf_org.ssgproject.content_profile_stig"
            ;;
        *)
            DEFAULT_PROFILE="xccdf_org.ssgproject.content_profile_stig"
            ;;
    esac
else
    DEFAULT_PROFILE="xccdf_org.ssgproject.content_profile_stig"
fi

# Allow override via environment variable
STIG_PROFILE_ID="${STIG_PROFILE_ID:-$DEFAULT_PROFILE}"

# Create reports directory
mkdir -p reports

# Generate timestamp for unique filenames
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Find the most recent SCAP content file
SCAP_FILE=$(find scap_content -name "*.xml" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [[ -z "$SCAP_FILE" ]]; then
    echo "Error: No SCAP content found. Run get_scap_content.sh first."
    exit 1
fi

echo "Using SCAP content: $SCAP_FILE"
echo "Running $MODE scan..."

# Run OpenSCAP evaluation
oscap xccdf eval \
    --profile "$STIG_PROFILE_ID" \
    --results "reports/results-${MODE}-${TIMESTAMP}.arf" \
    --report "reports/report-${MODE}-${TIMESTAMP}.html" \
    "$SCAP_FILE"

echo "Scan complete. Results saved to:"
echo "  ARF: reports/results-${MODE}-${TIMESTAMP}.arf"
echo "  HTML: reports/report-${MODE}-${TIMESTAMP}.html"
