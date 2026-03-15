#!/usr/bin/env bash
set -euo pipefail

# Run PI Terminal-Bench with Bedrock Sonnet 4.6 via existing run.sh

REPO_DIR="${REPO_DIR:-$HOME/Documents/2Projects/terminal-bantch/pi-terminal-bench}"
AWS_PROFILE="${AWS_PROFILE:-claude-code}"
AWS_REGION="${AWS_REGION:-us-east-1}"
MODEL="${MODEL:-amazon-bedrock/global.anthropic.claude-sonnet-4-6}"
TASK_IDS="${TASK_IDS:-build-cython-ext}"
N_ATTEMPTS="${N_ATTEMPTS:-1}"
N_CONCURRENT="${N_CONCURRENT:-1}"
DEBUG="${DEBUG:-1}"

cd "$REPO_DIR"

echo "Running PI Terminal-Bench"
echo "  repo:        $REPO_DIR"
echo "  profile:     $AWS_PROFILE"
echo "  region:      $AWS_REGION"
echo "  model:       $MODEL"
echo "  task(s):     $TASK_IDS"
echo "  attempts:    $N_ATTEMPTS"
echo "  concurrent:  $N_CONCURRENT"
echo "  debug:       $DEBUG"
echo

env \
  AWS_PROFILE="$AWS_PROFILE" \
  AWS_REGION="$AWS_REGION" \
  MODEL="$MODEL" \
  TASK_IDS="$TASK_IDS" \
  N_ATTEMPTS="$N_ATTEMPTS" \
  N_CONCURRENT="$N_CONCURRENT" \
  DEBUG="$DEBUG" \
  ./run.sh

echo
echo "Latest wrapper log:"
ls -t logs/*.log | head -1

echo
echo "Latest results dir:"
find pi-tbench-results -maxdepth 1 -mindepth 1 -type d | sort | tail -1
