# pi-terminal-bench

Harbor agent adapter for [pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) coding agent to run [Terminal-Bench](https://tbench.ai/) evaluations.

## Installation

```bash
# Install uv if not already installed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install harbor
uv tool install harbor

# Install this package (for development)
cd ~/workspaces/pi-terminal-bench
uv venv
source .venv/bin/activate
uv pip install -e ".[dev]"
```

## Required: Apply Harbor Fix

There is a bug in Harbor's `upload_dir` function that causes verifier failures when the agent creates a `/tests` directory during task execution. The fix must be applied before running evaluations.

**The Problem:** When using `docker cp /path/to/source container:/target`:
- If `/target` does NOT exist: copies contents of `source` into `/target` ✓
- If `/target` ALREADY exists: copies `source` as a subdirectory `/target/source/` ✗

The pi agent (and other agents) may create `/tests` during task execution, causing the verifier's test files to end up at `/tests/tests/test.sh` instead of `/tests/test.sh`.

**Apply the fix:**

```bash
# Find Harbor's docker.py location
HARBOR_DOCKER=$(python -c "import harbor.environments.docker.docker as m; print(m.__file__)")

# Apply the patch (backs up original first)
cp "$HARBOR_DOCKER" "${HARBOR_DOCKER}.bak"

# Edit the upload_dir function - change this:
#   async def upload_dir(self, source_dir: Path | str, target_dir: str):
#       await self._run_docker_compose_command(
#           ["cp", str(source_dir), f"main:{target_dir}"],
#           check=True,
#       )
#
# To this:
#   async def upload_dir(self, source_dir: Path | str, target_dir: str):
#       # Append /. to source to copy contents, not the directory itself
#       source = str(source_dir).rstrip('/') + '/.'
#       await self._run_docker_compose_command(
#           ["cp", source, f"main:{target_dir}"],
#           check=True,
#       )
```

Or use this one-liner to apply the patch:

```bash
python -c "
import harbor.environments.docker.docker as m
p = m.__file__
t = open(p).read()
old = '''    async def upload_dir(self, source_dir: Path | str, target_dir: str):
        await self._run_docker_compose_command(
            [
                \"cp\",
                str(source_dir),
                f\"main:{target_dir}\",
            ],
            check=True,
        )'''
new = '''    async def upload_dir(self, source_dir: Path | str, target_dir: str):
        # Append /. to source to copy contents, not the directory itself
        source = str(source_dir).rstrip('/') + '/.'
        await self._run_docker_compose_command(
            [
                \"cp\",
                source,
                f\"main:{target_dir}\",
            ],
            check=True,
        )'''
if old in t:
    open(p, 'w').write(t.replace(old, new))
    print('✓ Patch applied successfully')
else:
    print('✗ Already patched or file structure changed')
"
```

**Verify the patch:**

```bash
python -c "from harbor.environments.docker.docker import DockerEnvironment; import inspect; print('PATCHED' if 'rstrip' in inspect.getsource(DockerEnvironment.upload_dir) else 'NOT PATCHED')"
```

See [ERROR.md](./ERROR.md) for detailed investigation of this issue.

## Prerequisites

- Docker running
- At least one provider credential for the model you want to run:
  ```bash
  # Anthropic (OAuth token preferred)
  export ANTHROPIC_OAUTH_TOKEN="..."
  # OR
  export ANTHROPIC_API_KEY="..."

  # OpenAI
  export OPENAI_API_KEY="..."

  # Google
  export GEMINI_API_KEY="..."

  # Other supported providers
  export GROQ_API_KEY="..."
  export XAI_API_KEY="..."
  export OPENROUTER_API_KEY="..."

  # AWS Bedrock
  export AWS_PROFILE="claude-code"
  export AWS_REGION="us-east-1"
  # or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN directly
  ```

## Authentication and installation model

`pi-terminal-bench` does **not** reuse your already-installed local `pi` binary directly.

Instead, Harbor creates a clean evaluation environment and installs `pi` inside it using npm from `install-pi.sh.j2`. That means:

- it uses a **separate clean PI installation** for benchmark runs
- it **can** use provider credentials forwarded from your host environment
- it does **not** automatically reuse your local interactive PI login/session/config unless you explicitly build support for copying or mounting that state

In practice, the most reliable setup is to provide model/provider credentials through environment variables and run PI in a clean benchmark environment.

For AWS Bedrock-backed PI runs, the Harbor adapter now forwards AWS environment variables such as `AWS_PROFILE`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` into the clean PI runtime.

## Usage

### Run with pi agent on Terminal-Bench

```bash
# Run locally with Docker (Anthropic example)
harbor run \
  -d terminal-bench@2.0 \
  --agent-import-path pi_terminal_bench:PiAgent \
  -m anthropic/claude-sonnet-4-5 \
  -n 4

# Run locally with Docker (OpenAI example)
harbor run \
  -d terminal-bench@2.0 \
  --agent-import-path pi_terminal_bench:PiAgent \
  -m openai/gpt-5 \
  -n 4

# Run locally with Docker (AWS Bedrock example)
AWS_PROFILE=claude-code AWS_REGION=us-east-1 harbor run \
  -d terminal-bench@2.0 \
  --agent-import-path pi_terminal_bench:PiAgent \
  -m bedrock/sonnet-4-6 \
  -n 4

# Run on cloud (Daytona)
export DAYTONA_API_KEY="..."
harbor run \
  -d terminal-bench@2.0 \
  --agent-import-path pi_terminal_bench:PiAgent \
  -m anthropic/claude-sonnet-4-5 \
  --env daytona \
  -n 32
```

Or use the helper script:

```bash
# Anthropic
MODEL=anthropic/claude-sonnet-4-5 ./run.sh

# OpenAI
OPENAI_API_KEY=... MODEL=openai/gpt-5 ./run.sh

# AWS Bedrock
AWS_PROFILE=claude-code AWS_REGION=us-east-1 MODEL=bedrock/sonnet-4-6 ./run.sh
```

### Validate setup with oracle

```bash
harbor run -d terminal-bench@2.0 -a oracle
```

### Run a single task for testing

```bash
harbor run \
  -d terminal-bench@2.0 \
  --agent-import-path pi_terminal_bench:PiAgent \
  -m anthropic/claude-sonnet-4-5 \
  --task-ids <task-id>
```

Helper script form:

```bash
TASK_IDS=<task-id> ./run.sh
```

## Leaderboard Submission

To submit results to the Terminal-Bench leaderboard:

```bash
harbor run \
  -d terminal-bench@2.0 \
  --agent-import-path pi_terminal_bench:PiAgent \
  -m anthropic/claude-sonnet-4-5 \
  --k 5 \
  --jobs-dir "./pi-tbench-results"
```

You can also set `MODEL=...` and `JOBS_DIR=...` when using `./run.sh`.

Then email the jobs directory to:
- mchlmerrill@gmail.com
- alex@laude.org

## Viewing Results

After running evaluations, use `show-results.js` to display results with leaderboard comparison:

```bash
./show-results.js
```

This will parse the latest results from `pi-tbench-results/` and show where pi ranks on the Terminal-Bench 2.0 leaderboard.

## Development

```bash
# Run tests
pytest

# Lint
ruff check src/
ruff format src/
```

## License

MIT
