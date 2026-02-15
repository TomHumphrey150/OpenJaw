#!/bin/bash
# Wrapper script that captures run output for debugging.
# Creates timestamped directory in logs/runs/ with full output and metadata.

set -e

# Create timestamped run directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="logs/runs/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

# Save metadata
cat > "$RUN_DIR/meta.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "command": "./run.py $*",
  "working_dir": "$(pwd)",
  "python_version": "$(python3 --version 2>&1)",
  "git_commit": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')",
  "git_dirty": $(git diff --quiet 2>/dev/null && echo 'false' || echo 'true')
}
EOF

# Copy current model config if exists
if [ -f "data/models/model.json" ]; then
    cp "data/models/model.json" "$RUN_DIR/model_config.json"
fi

echo "Run logged to: $RUN_DIR"
echo "---"

# Run with output captured to both terminal and file
# Using script command for proper terminal handling
if command -v script &> /dev/null; then
    # macOS/BSD script syntax
    script -q "$RUN_DIR/output.log" ./run.py "$@"
    EXIT_CODE=$?
else
    # Fallback: simple tee (loses colors)
    ./run.py "$@" 2>&1 | tee "$RUN_DIR/output.log"
    EXIT_CODE=${PIPESTATUS[0]}
fi

# Save exit info
echo "{\"exit_code\": $EXIT_CODE, \"end_time\": \"$(date -Iseconds)\"}" > "$RUN_DIR/exit.json"

echo "---"
echo "Run complete. Logs saved to: $RUN_DIR"
