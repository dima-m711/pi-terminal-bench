#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source .venv/bin/activate

HARBOR_DOCKER=$(python -c "import harbor.environments.docker.docker as m; print(m.__file__)")
echo "Patching Harbor docker module: $HARBOR_DOCKER"

cp "$HARBOR_DOCKER" "${HARBOR_DOCKER}.bak"

python - <<'PY'
from pathlib import Path
import harbor.environments.docker.docker as m

p = Path(m.__file__)
s = p.read_text()

old = '''    async def upload_dir(self, source_dir: Path | str, target_dir: str):
        await self._run_docker_compose_command(
            ["cp", str(source_dir), f"main:{target_dir}"],
            check=True,
        )
'''

new = '''    async def upload_dir(self, source_dir: Path | str, target_dir: str):
        # Append /. to source to copy contents, not the directory itself
        source = str(source_dir).rstrip("/") + "/."
        await self._run_docker_compose_command(
            ["cp", source, f"main:{target_dir}"],
            check=True,
        )
'''

if old not in s:
    raise SystemExit("Expected upload_dir block not found. Harbor version may differ; inspect file manually.")

p.write_text(s.replace(old, new))
print(f"Patched {p}")
PY

python - <<'PY'
import inspect
import harbor.environments.docker.docker as d
print("\nPatched function:\n")
print(inspect.getsource(d.DockerEnvironment.upload_dir))
PY

echo "Patch complete. Backup saved as: ${HARBOR_DOCKER}.bak"
