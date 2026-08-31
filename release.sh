#!/bin/bash
# One-command TestFlight prep. Sets a fresh, always-increasing build number so the
# upload never collides, regenerates the Xcode project, and tells you the next step.
# Run this on the Mac, then Archive in Xcode (codesign needs the GUI keychain).
set -euo pipefail
cd "$(dirname "$0")"

BUILD=$(date +%Y%m%d%H%M)   # e.g. 202608301447 — monotonic, unique per minute

# Overwrite the build number (CFBundleVersion) in project.yml.
/usr/bin/sed -i '' -E "s/CFBundleVersion: \"[0-9]+\"/CFBundleVersion: \"$BUILD\"/" project.yml

# Regenerate the .xcodeproj from project.yml (picks up the new build number,
# entitlements, team, and any new source files).
xcodegen

MARKETING=$(/usr/bin/sed -nE 's/.*CFBundleShortVersionString: "([^"]+)".*/\1/p' project.yml | head -1)
echo ""
echo "  ✅ Version $MARKETING (build $BUILD) — project regenerated."
echo ""
echo "  Next, in Xcode (open P25Monitor.xcodeproj):"
echo "    1. Any device / 'Any iOS Device (arm64)' as the run target"
echo "    2. Product ▸ Archive"
echo "    3. In the Organizer: Distribute App ▸ TestFlight (& App Store)"
echo ""
echo "  Signing is automatic; CarPlay is in the managed profile. If Signing shows a"
echo "  red error, tick 'Automatically manage signing' and pick team 634QAM3ZHG."
