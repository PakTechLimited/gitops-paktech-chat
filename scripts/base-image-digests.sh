#!/usr/bin/env bash
# Compare the base images pinned in the chart (postgres, redis) with what their tags
# point to today. Needs Docker. Usage: bash scripts/base-image-digests.sh
set -euo pipefail
cd "$(dirname "$0")/.."

grep -E '^  image: (postgres|redis):' charts/paktech-chat/values.yaml | tr -d '\r' | while read -r _ ref; do
  tag="${ref%@*}"
  pinned="${ref#*@}"
  current="$(docker buildx imagetools inspect "$tag" 2>/dev/null | awk '/^Digest:/ && !seen {print $2; seen=1}' || true)"
  echo "$tag"
  echo "  pinned : $pinned"
  echo "  current: ${current:-lookup failed}"
  if [ -z "$current" ]; then echo "  -> could not check"
  elif [ "$pinned" = "$current" ]; then echo "  -> up to date"
  else echo "  -> NEWER DIGEST AVAILABLE (see docs/base-image-digests.md)"; fi
done
