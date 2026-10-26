#!/usr/bin/env sh
# Linux/macOS entry point. The installer is install.py (same flags; on Windows run: py -3 install.py).
#   ./install.sh               install for every agent found on this machine
#   ./install.sh --check       status + smoke test (exit 1 if not usable yet)
#   ./install.sh --uninstall   remove everything the installer added
dir="$(cd "$(dirname "$0")" && pwd)"
for py in python3 python; do
  if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then
    exec "$py" "$dir/install.py" "$@"
  fi
done
echo "install.sh: Python 3.9+ not found (python3 / python)" >&2
exit 1
