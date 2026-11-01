#!/usr/bin/env bash
# Wrapper around scripts/LicenseTool. See the comment at the top of LicenseTool/main.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
if [ ! -x .build/licensetool ] || [ scripts/LicenseTool/main.swift -nt .build/licensetool ] || [ Sources/BrimCore/License.swift -nt .build/licensetool ]; then
  swiftc -O scripts/LicenseTool/main.swift Sources/BrimCore/License.swift -o .build/licensetool
fi
exec .build/licensetool "$@"
