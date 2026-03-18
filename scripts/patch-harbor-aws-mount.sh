#!/usr/bin/env bash
set -euo pipefail

# Patches Harbor's DockerEnvironment to support mounting ~/.aws
# into the container when HOST_AWS_DIR env var is set.
#
# This allows AWS_PROFILE + SSO credentials to work inside containers
# without resolving static STS tokens (which expire after ~1 hour).
#
# Usage:
#   ./scripts/patch-harbor-aws-mount.sh
#
# Then run with:
#   AWS_PROFILE=claude-code AWS_REGION=us-east-1 MODEL=... ./run.sh

cd "$(dirname "$0")/.."
source .venv/bin/activate

HARBOR_DOCKER_DIR=$(python3 -c "from pathlib import Path; import harbor.environments.docker.docker as m; print(Path(m.__file__).parent)")
HARBOR_DOCKER_PY="$HARBOR_DOCKER_DIR/docker.py"

echo "Harbor docker module dir: $HARBOR_DOCKER_DIR"
echo "Harbor docker.py: $HARBOR_DOCKER_PY"

# Step 1: Create the AWS mount compose override file
AWS_COMPOSE="$HARBOR_DOCKER_DIR/docker-compose-aws-mount.yaml"
cat > "$AWS_COMPOSE" <<'YAML'
services:
  main:
    volumes:
      - ${HOST_AWS_DIR}:/root/.aws:ro
YAML
echo "Created: $AWS_COMPOSE"

# Step 2: Apply monkey-patch to Harbor's DockerEnvironment
python3 - <<'PYEOF'
import textwrap
from pathlib import Path
import harbor.environments.docker.docker as mod

docker_py = Path(mod.__file__)
source = docker_py.read_text()

# Check if already patched
if "docker-compose-aws-mount" in source:
    print("Already patched — skipping.")
    raise SystemExit(0)

# Patch 1: Add HOST_AWS_DIR to DockerEnvironmentEnvVars
old_envvars = '''class DockerEnvironmentEnvVars(BaseModel):
    main_image_name: str
    context_dir: str
    host_verifier_logs_path: str
    host_agent_logs_path: str
    host_artifacts_path: str
    env_verifier_logs_path: str
    env_agent_logs_path: str
    env_artifacts_path: str
    prebuilt_image_name: str | None = None
    cpus: int = 1
    memory: str = "1G"'''

new_envvars = '''class DockerEnvironmentEnvVars(BaseModel):
    main_image_name: str
    context_dir: str
    host_verifier_logs_path: str
    host_agent_logs_path: str
    host_artifacts_path: str
    env_verifier_logs_path: str
    env_agent_logs_path: str
    env_artifacts_path: str
    prebuilt_image_name: str | None = None
    cpus: int = 1
    memory: str = "1G"
    host_aws_dir: str | None = None'''

if old_envvars not in source:
    print("ERROR: Could not find DockerEnvironmentEnvVars block to patch")
    raise SystemExit(1)

source = source.replace(old_envvars, new_envvars)
print("Patched DockerEnvironmentEnvVars: added host_aws_dir field")

# Patch 2: Add _DOCKER_COMPOSE_AWS_MOUNT_PATH class variable
old_class_vars = '''    _DOCKER_COMPOSE_NO_NETWORK_PATH = COMPOSE_NO_NETWORK_PATH'''

new_class_vars = '''    _DOCKER_COMPOSE_NO_NETWORK_PATH = COMPOSE_NO_NETWORK_PATH
    _DOCKER_COMPOSE_AWS_MOUNT_PATH = COMPOSE_BASE_PATH.parent / "docker-compose-aws-mount.yaml"'''

if old_class_vars not in source:
    print("ERROR: Could not find class variables block to patch")
    raise SystemExit(1)

source = source.replace(old_class_vars, new_class_vars)
print("Patched DockerEnvironment: added _DOCKER_COMPOSE_AWS_MOUNT_PATH")

# Patch 3: Add HOST_AWS_DIR to __init__ env_vars construction
old_init_envvars = '''        self._env_vars = DockerEnvironmentEnvVars(
            main_image_name=f"hb__{environment_name}",
            context_dir=str(self.environment_dir.resolve().absolute()),
            host_verifier_logs_path=str(trial_paths.verifier_dir.resolve().absolute()),
            host_agent_logs_path=str(trial_paths.agent_dir.resolve().absolute()),
            host_artifacts_path=str(trial_paths.artifacts_dir.resolve().absolute()),
            env_verifier_logs_path=str(EnvironmentPaths.verifier_dir),
            env_agent_logs_path=str(EnvironmentPaths.agent_dir),
            env_artifacts_path=str(EnvironmentPaths.artifacts_dir),
            prebuilt_image_name=task_env_config.docker_image,
            cpus=task_env_config.cpus,
            memory=f"{task_env_config.memory_mb}M",
        )'''

new_init_envvars = '''        self._env_vars = DockerEnvironmentEnvVars(
            main_image_name=f"hb__{environment_name}",
            context_dir=str(self.environment_dir.resolve().absolute()),
            host_verifier_logs_path=str(trial_paths.verifier_dir.resolve().absolute()),
            host_agent_logs_path=str(trial_paths.agent_dir.resolve().absolute()),
            host_artifacts_path=str(trial_paths.artifacts_dir.resolve().absolute()),
            env_verifier_logs_path=str(EnvironmentPaths.verifier_dir),
            env_agent_logs_path=str(EnvironmentPaths.agent_dir),
            env_artifacts_path=str(EnvironmentPaths.artifacts_dir),
            prebuilt_image_name=task_env_config.docker_image,
            cpus=task_env_config.cpus,
            memory=f"{task_env_config.memory_mb}M",
            host_aws_dir=os.environ.get("HOST_AWS_DIR"),
        )'''

if old_init_envvars not in source:
    print("ERROR: Could not find __init__ env_vars block to patch")
    raise SystemExit(1)

source = source.replace(old_init_envvars, new_init_envvars)
print("Patched __init__: added host_aws_dir from HOST_AWS_DIR env var")

# Patch 4: Append AWS mount compose file to _docker_compose_paths
old_compose_return = '''        if not self.task_env_config.allow_internet:
            paths.append(self._DOCKER_COMPOSE_NO_NETWORK_PATH)

        return paths'''

new_compose_return = '''        if not self.task_env_config.allow_internet:
            paths.append(self._DOCKER_COMPOSE_NO_NETWORK_PATH)

        # Mount ~/.aws into container for AWS credential access
        if self._env_vars.host_aws_dir and self._DOCKER_COMPOSE_AWS_MOUNT_PATH.exists():
            paths.append(self._DOCKER_COMPOSE_AWS_MOUNT_PATH)

        return paths'''

if old_compose_return not in source:
    print("ERROR: Could not find _docker_compose_paths return block to patch")
    raise SystemExit(1)

source = source.replace(old_compose_return, new_compose_return)
print("Patched _docker_compose_paths: appends AWS mount compose when HOST_AWS_DIR is set")

# Write
docker_py.write_text(source)
print(f"\nAll patches applied to {docker_py}")
PYEOF

# Step 3: Verify
echo
echo "=== Verification ==="
python3 -c "
import harbor.environments.docker.docker as d
import inspect

# Check env vars model
src = inspect.getsource(d.DockerEnvironmentEnvVars)
assert 'host_aws_dir' in src, 'host_aws_dir not found in DockerEnvironmentEnvVars'
print('✅ DockerEnvironmentEnvVars has host_aws_dir')

# Check compose paths
src = inspect.getsource(d.DockerEnvironment._docker_compose_paths.fget)
assert 'aws_mount' in src.lower() or 'host_aws_dir' in src, 'AWS mount not in compose paths'
print('✅ _docker_compose_paths includes AWS mount logic')

# Check class variable
assert hasattr(d.DockerEnvironment, '_DOCKER_COMPOSE_AWS_MOUNT_PATH'), 'Missing class var'
print('✅ _DOCKER_COMPOSE_AWS_MOUNT_PATH exists')

print()
print('All patches verified successfully.')
"

echo
echo "Patch complete. To use:"
echo "  export HOST_AWS_DIR=\$HOME/.aws"
echo "  AWS_PROFILE=claude-code AWS_REGION=us-east-1 MODEL=... ./run.sh"
