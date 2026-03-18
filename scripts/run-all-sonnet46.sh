#!/usr/bin/env bash
set -euo pipefail

# Run ALL 89 Terminal-Bench tasks with PI + Bedrock Sonnet 4.6
#
# Usage:
#   ./scripts/run-all-sonnet46.sh
#
# Override defaults:
#   N_ATTEMPTS=3 N_CONCURRENT=2 ./scripts/run-all-sonnet46.sh
#
# Exclude specific tasks:
#   EXCLUDE_TASKS="some-flaky-task" ./scripts/run-all-sonnet46.sh

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
AWS_PROFILE="${AWS_PROFILE:-claude-code}"
AWS_REGION="${AWS_REGION:-us-east-1}"
MODEL="${MODEL:-amazon-bedrock/global.anthropic.claude-sonnet-4-6}"
N_ATTEMPTS="${N_ATTEMPTS:-1}"
N_CONCURRENT="${N_CONCURRENT:-4}"
DEBUG="${DEBUG:-0}"
EXCLUDE_TASKS="${EXCLUDE_TASKS:-}"

cd "$REPO_DIR"

echo "============================================"
echo "  PI Terminal-Bench — Full Suite"
echo "============================================"
echo "  model:       $MODEL"
echo "  attempts:    $N_ATTEMPTS"
echo "  concurrent:  $N_CONCURRENT"
echo "  debug:       $DEBUG"
echo "  exclude:     ${EXCLUDE_TASKS:-none}"
echo "============================================"
echo

# Run all tasks (no --task-name filter = all tasks)
env \
  AWS_PROFILE="$AWS_PROFILE" \
  AWS_REGION="$AWS_REGION" \
  MODEL="$MODEL" \
  TASK_IDS="" \
  N_ATTEMPTS="$N_ATTEMPTS" \
  N_CONCURRENT="$N_CONCURRENT" \
  DEBUG="$DEBUG" \
  ./run.sh

echo
echo "============================================"
echo "  Run complete"
echo "============================================"

echo
echo "Latest wrapper log:"
ls -t logs/*.log | head -1

echo
echo "Results directory:"
LATEST_RUN="$(find pi-tbench-results -maxdepth 1 -mindepth 1 -type d | sort | tail -1)"
echo "$LATEST_RUN"

echo
echo "View results:"
echo "  source .venv/bin/activate && harbor view $LATEST_RUN"
