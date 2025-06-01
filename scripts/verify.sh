#!/usr/bin/env bash

set -euo pipefail

echo "Running post-remediation verification scan..."

# Run the after scan
./scripts/scan.sh --after

echo "Verification scan complete."

# Find the most recent baseline and after reports
BASELINE_REPORT=$(find reports -name "report-baseline-*.html" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
AFTER_REPORT=$(find reports -name "report-after-*.html" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [[ -n "$BASELINE_REPORT" && -n "$AFTER_REPORT" ]]; then
    echo ""
    echo "Comparison reports available:"
    echo "  Baseline: $BASELINE_REPORT"
    echo "  After remediation: $AFTER_REPORT"
    echo ""
    echo "Please review both reports to verify remediation effectiveness."
else
    echo "Warning: Could not find both baseline and after reports for comparison."
fi

echo "Verification complete."
