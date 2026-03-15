#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

MODEL="${MODEL:-anthropic/claude-opus-4-5}"
JOBS_DIR="${JOBS_DIR:-./pi-tbench-results}"
N_CONCURRENT="${N_CONCURRENT:-4}"
N_ATTEMPTS="${N_ATTEMPTS:-5}"
TASK_IDS="${TASK_IDS:-}"
ENV_NAME="${ENV_NAME:-}"

has_standard_provider_cred=0
if [ -n "${ANTHROPIC_API_KEY:-}" ] \
  || [ -n "${ANTHROPIC_OAUTH_TOKEN:-}" ] \
  || [ -n "${OPENAI_API_KEY:-}" ] \
  || [ -n "${GEMINI_API_KEY:-}" ] \
  || [ -n "${GROQ_API_KEY:-}" ] \
  || [ -n "${XAI_API_KEY:-}" ] \
  || [ -n "${OPENROUTER_API_KEY:-}" ]; then
  has_standard_provider_cred=1
fi

has_aws_cred=0
if [ -n "${AWS_PROFILE:-}" ] \
  || { [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; }; then
  has_aws_cred=1
fi

if [ "$has_standard_provider_cred" -ne 1 ] && [ "$has_aws_cred" -ne 1 ]; then
    echo "Error: set either a supported provider credential (ANTHROPIC_OAUTH_TOKEN, ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, GROQ_API_KEY, XAI_API_KEY, OPENROUTER_API_KEY) or AWS credentials/profile for Bedrock"
    exit 1
fi

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running"
    exit 1
fi

# Activate venv
source .venv/bin/activate

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
  CMD+=(--task-ids "$TASK_IDS")
fi

if [ -n "$ENV_NAME" ]; then
  CMD+=(--env "$ENV_NAME")
fi

"${CMD[@]}"
