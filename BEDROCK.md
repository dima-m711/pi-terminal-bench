# Running PI Terminal Bench with AWS Bedrock

This repo can run PI against Bedrock-backed models by forwarding AWS credentials from the host into the clean Harbor runtime.

## Recommended setup

```bash
cd pi-terminal-bench
export AWS_PROFILE=claude-code
export AWS_REGION=us-east-1
MODEL=bedrock/sonnet-4-6 ./run.sh
```

You can also use direct credentials instead of a profile:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...   # if applicable
export AWS_REGION=us-east-1
MODEL=bedrock/sonnet-4-6 ./run.sh
```

## Single-task smoke run

```bash
AWS_PROFILE=claude-code \
AWS_REGION=us-east-1 \
MODEL=bedrock/sonnet-4-6 \
TASK_IDS=<task-id> \
./run.sh
```

## Important note

This uses a clean PI installation inside Harbor, not your host-installed `pi` binary directly. The host AWS environment variables are forwarded into the evaluation runtime.

## Open question

The exact Bedrock provider/model string accepted by PI depends on the installed `@mariozechner/pi-coding-agent` version. If `bedrock/sonnet-4-6` is not accepted, inspect `pi --help` or PI model/provider docs and adjust the `MODEL=` string accordingly.
