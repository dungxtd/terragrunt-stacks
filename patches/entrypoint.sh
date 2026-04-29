#!/usr/bin/env bash
# Entrypoint wrapper: patches eks.py in-place, then starts MiniStack.
# Fixes k3s cgroup v2 crash on macOS (OrbStack, Colima, Docker Desktop).
set -e

EKS_PY="/opt/ministack/ministack/services/eks.py"
K3S_VERSION="${EKS_K3S_VERSION:-}"

# ── Patch: privileged mode for k3s (cgroup v2 fix) ───────
if [ -f "$EKS_PY" ] && ! grep -q "privileged=True" "$EKS_PY"; then
  python3 - "$EKS_PY" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
pattern = r'cap_add=\[.*?\],\s*security_opt=\[.*?\],\s*devices=\[.*?\],'
content = re.sub(pattern, 'privileged=True,', content, flags=re.DOTALL)
with open(path, 'w') as f:
    f.write(content)
PYEOF
  echo "[patch] eks.py: cap_add → privileged=True"
fi

# ── Patch: k3s host network (macOS Docker IP unreachable) ──────
if [ -f "$EKS_PY" ] && ! grep -q "FORCE_HOST_NETWORK" "$EKS_PY"; then
  python3 - "$EKS_PY" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

# 1. k3s listens on the allocated port directly on the host
content = content.replace(
    'f"--https-listen-port=6443"',
    'f"--https-listen-port={port}"'
)

# 2. Host network instead of port mapping
content = content.replace(
    'ports={"6443/tcp": port},',
    'network_mode="host",  # FORCE_HOST_NETWORK'
)

# 3. Skip Docker-network assignment (incompatible with host network)
content = content.replace(
    'if ms_network:\n                run_kwargs["network"] = ms_network',
    'if False:  # FORCE_HOST_NETWORK\n                run_kwargs["network"] = ms_network'
)

# 4. Skip container-IP endpoint detection
content = content.replace(
    'if ms_network:\n                container.reload()',
    'if False:  # FORCE_HOST_NETWORK\n                container.reload()'
)

# 5. Readiness check: container → host via host.docker.internal
content = content.replace(
    '_wait_for_port("127.0.0.1", port)',
    '_wait_for_port("host.docker.internal", port)'
)

with open(path, 'w') as f:
    f.write(content)
PYEOF
  echo "[patch] eks.py: k3s host network mode"
fi

# ── Patch: k3s image version (optional) ──────────────────
if [ -n "$K3S_VERSION" ] && [ -f "$EKS_PY" ]; then
  sed -i "s|rancher/k3s:[^\"']*|rancher/k3s:${K3S_VERSION}|" "$EKS_PY"
  echo "[patch] eks.py: k3s image → rancher/k3s:${K3S_VERSION}"
fi

# ── Start MiniStack ──────────────────────────────────────
exec python -m hypercorn ministack.app:app --bind 0.0.0.0:4566 --keep-alive 75
