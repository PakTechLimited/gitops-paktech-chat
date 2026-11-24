#!/usr/bin/env bash
# Render every environment of the chart and check the platform manifests, so mistakes
# show up in a pull request and not when Argo CD syncs. Runs locally and in CI:
#   pip install pyyaml && bash scripts/render-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

chart=charts/paktech-chat
status=0

for env in dev staging prod; do
  vals="environments/$env/values.yaml"
  echo "== $env"
  helm lint "$chart" -f "$vals" > /dev/null
  out="$(helm template pc "$chart" -f "$vals" --namespace "paktech-chat-$env")"
  echo "   objects rendered: $(grep -c '^kind:' <<< "$out" || true)"
  unpinned="$(grep -E '^[[:space:]]*-?[[:space:]]*image:' <<< "$out" | grep -v '@sha256:' || true)"
  if [ -n "$unpinned" ]; then
    echo "   FAIL: image not pinned by digest:"
    sed 's/^/     /' <<< "$unpinned"
    status=1
  fi
done

echo "== platform manifests and dashboards"
python3 - <<'PY' || status=1
import glob, json, sys
import yaml

bad = 0
files = sorted(glob.glob("platform/**/*.yaml", recursive=True))
dashboards = 0
for path in files:
    try:
        docs = [d for d in yaml.safe_load_all(open(path, encoding="utf-8")) if d]
    except yaml.YAMLError as err:
        print("   FAIL: invalid YAML:", path, str(err).splitlines()[0]); bad += 1; continue
    for d in docs:
        labels = (d.get("metadata") or {}).get("labels") or {}
        if d.get("kind") == "ConfigMap" and "grafana_dashboard" in labels:
            for key, val in (d.get("data") or {}).items():
                dashboards += 1
                try:
                    dash = json.loads(val)
                except ValueError as err:
                    print("   FAIL: dashboard JSON invalid:", path, key, err); bad += 1; continue
                if "${DS_" in val:
                    print("   FAIL: datasource placeholder left in", path, key); bad += 1
                if not dash.get("uid"):
                    print("   FAIL: dashboard has no uid:", path, key); bad += 1
print("   %d YAML files parsed, %d dashboards checked" % (len(files), dashboards))
sys.exit(1 if bad else 0)
PY

[ "$status" -eq 0 ] && echo "render-check OK" || { echo "render-check FAILED"; exit 1; }
