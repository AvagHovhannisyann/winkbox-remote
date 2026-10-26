#!/bin/bash
# Signs WinkRemote.ipa with the Apple ID you gave `xtool setup` and installs it on the iPhone plugged into this Mac.
# An app signed with a free Apple ID stops opening after 7 days: run this again to renew it (its settings stay).
set -euo pipefail
cd "$(dirname "$0")"
[ -f WinkRemote.ipa ] || ./build.sh
command -v xtool >/dev/null || { echo "xtool isn't installed: brew install --cask xtool-org/tap/xtool"; exit 1; }
xtool install WinkRemote.ipa
