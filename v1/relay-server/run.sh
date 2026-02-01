#!/bin/bash
# Relay Server Startup Script
# Runs the Python relay server with caffeinate to prevent Mac from sleeping

set -e  # Exit on error

cd "$(dirname "$0")"

echo "============================================"
echo "Bruxism Biofeedback Relay Server"
echo "============================================"
echo ""

# Get Mac's local IP address
MAC_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)

echo "Network Configuration:"
echo "   Mac IP Address: $MAC_IP"
echo ""
echo "Mind Monitor Setup (iPhone 1):"
echo "   - OSC Target IP: $MAC_IP"
echo "   - OSC Port: 5000"
echo ""
echo "iOS App Setup (iPhone 2):"
echo "   - Open Settings in app"
echo "   - Server IP: $MAC_IP"
echo "   - Server Port: 8765"
echo "   - Tap Connect to Server"
echo ""
echo "============================================"
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 not found. Please install Python 3.9+"
    exit 1
fi

# Check if dependencies are installed
if ! python3 -c "import pythonosc" 2>/dev/null; then
    echo "Dependencies not installed. Installing now..."
    python3 -m pip install -r requirements.txt
fi

echo "Starting relay server with caffeinate (prevents Mac sleep)..."
echo "Press Ctrl+C to stop"
echo ""

# Parse arguments - data collection is ON by default (unless test mode)
COLLECT_ENABLED=true
TEST_MODE=false

for arg in "$@"; do
    case $arg in
        --test)
            TEST_MODE=true
            ;;
        --no-collect)
            COLLECT_ENABLED=false
            ;;
    esac
done

# Build args
ARGS=""

if [ "$TEST_MODE" = true ]; then
    ARGS="--test"
    echo "============================================"
    echo "            *** TEST MODE ***"
    echo "============================================"
    echo ""
    echo "- Simulating jaw clench events every 5 seconds"
    echo "- No Muse headband required"
    echo "- Data collection automatically DISABLED"
    echo "  (training data will not be polluted)"
    echo ""
    # In test mode, we still pass --collect if it was enabled,
    # but server.py will override it to False
    if [ "$COLLECT_ENABLED" = true ]; then
        ARGS="$ARGS --collect"
    fi
elif [ "$COLLECT_ENABLED" = true ]; then
    ARGS="--collect"
    echo "Data collection ENABLED (recording EEG/ACC/GYRO to JSONL)"
else
    echo "Data collection DISABLED"
fi

echo ""

# Run server with caffeinate to prevent system sleep
caffeinate -i python3 server.py $ARGS
