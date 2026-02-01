#!/bin/bash
# Skywalker v2: Muse Jaw Clench Detector startup script
#
# Usage:
#   ./run.sh              # Full flow: discover → stream → detect
#   ./run.sh --test       # Test mode (no Muse needed)
#   ./run.sh -v           # Verbose logging
#   ./run.sh -vv          # Extra verbose (trace-level)
#   ./run.sh --address XX:XX:XX:XX:XX:XX  # Use specific Muse

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Run with caffeinate to prevent Mac from sleeping
exec caffeinate -i python run.py "$@"
