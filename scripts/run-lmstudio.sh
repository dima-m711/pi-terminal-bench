#!/usr/bin/env bash
set -euo pipefail

# Run a single Terminal-Bench task with PI + LM Studio (local model)
#
# LM Studio must be running on this machine with its API server enabled.
# Default: http://localhost:1234/v1
#
# Usage:
#   ./scripts/run-lmstudio.sh
#
# Override defaults:
#   TASK_IDS=build-pmars MODEL=mlx-community/some-other-model ./scripts/run-lmstudio.sh

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# LM Studio settings
LMSTUDIO_PORT="${LMSTUDIO_PORT:-1234}"
# Inside Docker, the host is reachable via host.docker.internal
OPENAI_BASE_URL="${OPENAI_BASE_URL:-http://host.docker.internal:${LMSTUDIO_PORT}/v1}"
OPENAI_API_KEY="${OPENAI_API_KEY:-lm-studio}"
MODEL="${MODEL:-openai/mlx-community/qwen3.5-35b-a3b}"

# Task settings
TASK_IDS="${TASK_IDS:-build-cython-ext}"
N_ATTEMPTS="${N_ATTEMPTS:-1}"
N_CONCURRENT="${N_CONCURRENT:-1}"
DEBUG="${DEBUG:-1}"
JOBS_DIR="${JOBS_DIR:-./pi-tbench-results-lmstudio}"

cd "$REPO_DIR"

# Verify LM Studio is reachable on the host
echo "Checking LM Studio at http://localhost:${LMSTUDIO_PORT}/v1/models ..."
if ! curl -s --connect-timeout 5 "http://localhost:${LMSTUDIO_PORT}/v1/models" > /dev/null 2>&1; then
  echo "Error: LM Studio API not reachable at http://localhost:${LMSTUDIO_PORT}/v1"
  echo "Make sure LM Studio is running and its local server is started."
  exit 1
fi
echo "LM Studio is up."

# Show loaded models
echo
echo "Loaded models:"
curl -s "http://localhost:${LMSTUDIO_PORT}/v1/models" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for m in data.get('data', []):
    print(f'  - {m[\"id\"]}')
" 2>/dev/null || echo "  (could not list models)"

echo
echo "============================================"
echo "  PI Terminal-Bench — LM Studio"
echo "============================================"
echo "  model:          $MODEL"
echo "  base url:       $OPENAI_BASE_URL"
echo "  task:           $TASK_IDS"
echo "  attempts:       $N_ATTEMPTS"
echo "  concurrent:     $N_CONCURRENT"
echo "  results dir:    $JOBS_DIR"
echo "============================================"
echo

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running"
  exit 1
fi

# Activate venv
source .venv/bin/activate

LOG_DIR="${LOG_DIR:-./logs}"
mkdir -p "$LOG_DIR"
timestamp="$(date +%Y%m%d-%H%M%S)"
task_slug="${TASK_IDS:-all-tasks}"
task_slug="${task_slug//\*/star}"
task_slug="${task_slug//\//-}"
task_slug="${task_slug// /-}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/lmstudio-${timestamp}-${task_slug}.log}"

CMD=(
  harbor run
  -d terminal-bench@2.0
  --agent-import-path pi_terminal_bench:PiAgent
  -m "$MODEL"
  --n-attempts "$N_ATTEMPTS"
  --jobs-dir "$JOBS_DIR"
  -n "$N_CONCURRENT"
)

if [ -n "$TASK_IDS" ]; then
  CMD+=(--task-name "$TASK_IDS")
fi

if [ "$DEBUG" = "1" ]; then
  CMD+=(--debug)
fi

# Forward OpenAI-compatible env vars into the container
CMD+=(--ae "OPENAI_API_KEY=${OPENAI_API_KEY}")
CMD+=(--ae "OPENAI_BASE_URL=${OPENAI_BASE_URL}")

printf 'Running:'
printf ' %q' "${CMD[@]}"
printf '\n'
echo "Log file: $LOG_FILE"
echo

set +e
"${CMD[@]}" 2>&1 | tee "$LOG_FILE"
cmd_status=${PIPESTATUS[0]}
set -e

echo
echo "Harbor exit status: $cmd_status"
echo "Saved log to: $LOG_FILE"

echo
echo "Results directory:"
LATEST_RUN="$(find "$JOBS_DIR" -maxdepth 1 -mindepth 1 -type d | sort | tail -1)"
echo "$LATEST_RUN"

echo
echo "View results:"
echo "  source .venv/bin/activate && harbor view $LATEST_RUN"

exit "$cmd_status"
