#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "============================================"
echo "  Bruxism Dashboard"
echo "============================================"

# Check for node
if ! command -v node &> /dev/null; then
    echo "Error: node not found. Please install Node.js 18+"
    exit 1
fi

# Check node version
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "Warning: Node.js 18+ recommended (found v$NODE_VERSION)"
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

# Build TypeScript if needed
if [ ! -d "dist" ] || [ "src/server.ts" -nt "dist/server.js" ]; then
    echo "Building TypeScript..."
    npm run build
fi

echo ""
echo "Starting server at http://localhost:3000"
echo "Press Ctrl+C to stop"
echo ""

npm start
