#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

MODEL="${MODEL:-anthropic/claude-opus-4-5}"
JOBS_DIR="${JOBS_DIR:-./pi-tbench-results}"
N_CONCURRENT="${N_CONCURRENT:-4}"
N_ATTEMPTS="${N_ATTEMPTS:-5}"
TASK_IDS="${TASK_IDS:-}"
ENV_NAME="${ENV_NAME:-}"
DEBUG_MODE="${DEBUG_MODE:-${DEBUG:-0}}"
QUIET_MODE="${QUIET_MODE:-${QUIET:-0}}"
LOG_DIR="${LOG_DIR:-./logs}"
LOG_FILE="${LOG_FILE:-}"

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

# AWS credential strategy:
#   1. If AWS_PROFILE is set and ~/.aws exists → mount ~/.aws into container (no token expiry)
#   2. If AWS_PROFILE is set but no ~/.aws → resolve static STS creds (may expire)
#   3. If AWS_ACCESS_KEY_ID is set directly → use as-is

aws_mount_mode=0
aws_profile_resolved=0

if [ -n "${AWS_PROFILE:-}" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  if [ -d "$HOME/.aws" ]; then
    # Approach A: Mount ~/.aws into the container for auto-refreshing credentials
    echo "Mounting ~/.aws into container for profile: ${AWS_PROFILE}"
    export HOST_AWS_DIR="$HOME/.aws"
    aws_mount_mode=1

    # Validate credentials on the host before starting
    echo "Validating AWS credentials for profile: ${AWS_PROFILE}"
    aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null
  else
    # Fallback: resolve static creds (may expire on long runs)
    if ! command -v aws >/dev/null 2>&1; then
      echo "Error: AWS CLI is required when using AWS_PROFILE"
      exit 1
    fi

    echo "Warning: ~/.aws not found — resolving static STS credentials (may expire on long runs)"
    echo "Resolving AWS credentials from profile: ${AWS_PROFILE}"
    eval "$(aws configure export-credentials --profile "$AWS_PROFILE" --format env-no-export)"
    aws_profile_resolved=1

    # Unset AWS_PROFILE so it is NOT forwarded into the container.
    # The container has no ~/.aws/config, so the profile name is useless there
    # and causes the AWS SDK to ignore the static creds we just resolved.
    unset AWS_PROFILE
  fi
fi

if [ "$aws_mount_mode" -ne 1 ]; then
  # Validate static creds if present
  if [ -n "${AWS_PROFILE:-}" ] || [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    if ! command -v aws >/dev/null 2>&1; then
      echo "Error: AWS CLI is required for Bedrock credential validation"
      exit 1
    fi

    AWS_STS_ENV=( )
    if [ -n "${AWS_REGION:-}" ]; then
      AWS_STS_ENV+=(AWS_REGION="$AWS_REGION")
    fi
    if [ -n "${AWS_DEFAULT_REGION:-}" ]; then
      AWS_STS_ENV+=(AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION")
    fi
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
      AWS_STS_ENV+=(AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID")
    fi
    if [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
      AWS_STS_ENV+=(AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY")
    fi
    if [ -n "${AWS_SESSION_TOKEN:-}" ]; then
      AWS_STS_ENV+=(AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN")
    fi

    echo "Validating AWS credentials with sts get-caller-identity"
    env "${AWS_STS_ENV[@]}" aws sts get-caller-identity >/dev/null
  fi
fi

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running"
    exit 1
fi

# Activate venv
source .venv/bin/activate

mkdir -p "$LOG_DIR"
if [ -z "$LOG_FILE" ]; then
  timestamp="$(date +%Y%m%d-%H%M%S)"
  task_slug="${TASK_IDS:-all-tasks}"
  task_slug="${task_slug//\*/star}"
  task_slug="${task_slug//\//-}"
  task_slug="${task_slug// /-}"
  LOG_FILE="$LOG_DIR/run-${timestamp}-${task_slug}.log"
fi

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

if [ -n "$ENV_NAME" ]; then
  CMD+=(--env "$ENV_NAME")
fi

if [ "$DEBUG_MODE" = "1" ]; then
  CMD+=(--debug)
fi

if [ "$QUIET_MODE" = "1" ]; then
  CMD+=(--quiet)
fi

for key in \
  ANTHROPIC_OAUTH_TOKEN \
  ANTHROPIC_API_KEY \
  OPENAI_API_KEY \
  OPENAI_BASE_URL \
  GEMINI_API_KEY \
  GROQ_API_KEY \
  XAI_API_KEY \
  OPENROUTER_API_KEY \
  AWS_PROFILE \
  AWS_REGION \
  AWS_DEFAULT_REGION \
  AWS_ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY \
  AWS_SESSION_TOKEN; do
  if [ -n "${!key:-}" ]; then
    CMD+=(--ae "$key=${!key}")
  fi
done

printf 'Running:'
printf ' %q' "${CMD[@]}"
printf '\n'
echo "Log file: $LOG_FILE"

set +e
"${CMD[@]}" 2>&1 | tee "$LOG_FILE"
cmd_status=${PIPESTATUS[0]}
set -e

echo "Harbor exit status: $cmd_status"
echo "Saved log to: $LOG_FILE"
exit "$cmd_status"
