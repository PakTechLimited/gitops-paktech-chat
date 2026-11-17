#!/usr/bin/env bash
# Copies the Gatekeeper library ConstraintTemplates we use into platform/policies/templates and records the commit.
# Run once from anywhere: bash scripts/fetch-policies.sh   (needs git; kubectl is optional for the dry-run check)
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 -q https://github.com/open-policy-agent/gatekeeper-library "$TMP/lib"
COMMIT=$(git -C "$TMP/lib" rev-parse HEAD)
OUT=platform/policies/templates
mkdir -p "$OUT"
# folder name in the library -> constraint kind the template must define
declare -A WANT=(
  [allowedrepos]=K8sAllowedRepos
  [containerresources]=K8sRequiredResources
  [imagedigests]=K8sImageDigests
  [privileged-containers]=K8sPSPPrivilegedContainer
  [read-only-root-filesystem]=K8sPSPReadOnlyRootFilesystem
  [allow-privilege-escalation]=K8sPSPAllowPrivilegeEscalationContainer
  [capabilities]=K8sPSPCapabilities
)
for dir in "${!WANT[@]}"; do
  want=${WANT[$dir]}
  src=$(find "$TMP/lib/library" -type f -path "*/$dir/template.yaml" | head -1)
  [ -n "$src" ] || { echo "ERROR: no template.yaml found for '$dir' in the library"; exit 1; }
  kind=$(grep -m1 -E '^[[:space:]]+kind: K8s' "$src" | sed -E 's/.*kind:[[:space:]]*//' | tr -d '\r')
  [ "$kind" = "$want" ] || { echo "ERROR: $dir defines kind '$kind', expected '$want'"; exit 1; }
  tr -d '\r' < "$src" > "$OUT/$want.yaml"
  echo "ok  $want  <-  ${src#$TMP/lib/}"
done
printf 'Source: https://github.com/open-policy-agent/gatekeeper-library\nCommit: %s\nFetched: %s\n' "$COMMIT" "$(date -u +%F)" > "$OUT/SOURCE.txt"
echo "library commit: $COMMIT"
if command -v kubectl >/dev/null 2>&1; then
  echo "--- server-side dry run of the templates (Gatekeeper compiles the policy code) ---"
  kubectl apply --dry-run=server -f "$OUT" 2>&1 | tail -20 || true
fi
