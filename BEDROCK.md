# Running PI Terminal Bench with AWS Bedrock

This repo can run PI against Bedrock-backed models by forwarding AWS credentials from the host into the clean Harbor runtime.

## Recommended setup (mount `~/.aws`)

The best approach for long-running benchmarks is to mount your host `~/.aws` directory into the container. This allows the AWS SDK inside the container to use your SSO token cache, which auto-refreshes and won't expire during multi-hour runs.

```bash
cd pi-terminal-bench

# One-time: patch Harbor to support ~/.aws mounting
./scripts/patch-harbor-aws-mount.sh

# Run (credentials auto-refresh from your SSO session)
AWS_PROFILE=claude-code \
AWS_REGION=us-east-1 \
MODEL=amazon-bedrock/global.anthropic.claude-sonnet-4-6 \
./run.sh
```

When `AWS_PROFILE` is set and `~/.aws` exists on the host, `run.sh` automatically:
1. Sets `HOST_AWS_DIR=$HOME/.aws` so Harbor mounts it read-only at `/root/.aws`
2. Forwards `AWS_PROFILE` and `AWS_REGION` into the container
3. The AWS SDK uses the profile's SSO token cache — no static token expiry

### Fallback: static credentials

If `~/.aws` doesn't exist, `run.sh` falls back to resolving static STS credentials via `aws configure export-credentials`. These **will expire** after ~1 hour (SSO default), which can cause failures on long runs.

You can also use direct credentials instead of a profile:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...   # if applicable
export AWS_REGION=us-east-1
MODEL=amazon-bedrock/global.anthropic.claude-sonnet-4-6 ./run.sh
```

## Single-task smoke run

```bash
AWS_PROFILE=claude-code \
AWS_REGION=us-east-1 \
MODEL=amazon-bedrock/global.anthropic.claude-sonnet-4-6 \
TASK_IDS=build-cython-ext \
N_ATTEMPTS=1 \
N_CONCURRENT=1 \
DEBUG=1 \
./run.sh
```

This prints Harbor debug logs and saves them under `./logs/`.

## Full benchmark run

```bash
# All 89 tasks
AWS_PROFILE=claude-code \
AWS_REGION=us-east-1 \
MODEL=amazon-bedrock/global.anthropic.claude-sonnet-4-6 \
N_ATTEMPTS=1 \
N_CONCURRENT=4 \
./run.sh
```

Or use the helper:

```bash
scripts/run-all-sonnet46.sh
```

## Harbor AWS mount patch

The patch script `scripts/patch-harbor-aws-mount.sh` modifies Harbor's `DockerEnvironment` to:
1. Add a `docker-compose-aws-mount.yaml` that bind-mounts `$HOST_AWS_DIR` at `/root/.aws:ro`
2. Include this compose file in the Docker compose chain when `HOST_AWS_DIR` is set
3. Pass `HOST_AWS_DIR` through Harbor's env var system

This patch is applied to the local `.venv` and needs to be re-applied after `pip install --upgrade harbor`.

## Important notes

- This uses a clean PI installation inside Harbor, not your host-installed `pi` binary
- The `~/.aws` directory is mounted **read-only** — the container cannot modify your credentials
- The container can read all profiles in `~/.aws`, not just the target profile
- For CI/CD environments without `~/.aws`, use IAM user credentials (no expiry) instead

## Open question

The exact Bedrock provider/model string accepted by PI depends on the installed `@mariozechner/pi-coding-agent` version. The tested working string is `amazon-bedrock/global.anthropic.claude-sonnet-4-6`.
