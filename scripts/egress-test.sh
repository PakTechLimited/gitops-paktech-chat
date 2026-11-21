#!/usr/bin/env bash
# Usage: bash scripts/egress-test.sh paktech-chat-dev
# Prints OPEN/BLOCKED for the paths that matter. Run once before enabling egress (all OPEN) and once after.
NS="${1:-paktech-chat-dev}"
export MSYS_NO_PATHCONV=1
echo "== api (expect after: postgres OPEN, redis OPEN, anthropic OPEN, 1.1.1.1:443 OPEN, the rest BLOCKED)"
kubectl exec -i -n "$NS" deploy/api -- python - <<'PY'
import os, socket
def c(h, p):
    try:
        socket.create_connection((h, p), timeout=3).close(); return "OPEN"
    except Exception as e:
        return "BLOCKED (%s)" % type(e).__name__
k8s = os.environ.get("KUBERNETES_SERVICE_HOST", "10.0.0.1")
for name, h, p in [("postgres:5432","postgres",5432),("redis:6379","redis",6379),
                   ("web:3000","web",3000),("api.anthropic.com:443","api.anthropic.com",443),
                   ("1.1.1.1:443","1.1.1.1",443),("1.1.1.1:80","1.1.1.1",80),
                   ("metadata 169.254.169.254:80","169.254.169.254",80),
                   ("kube-apiserver svc %s:443"%k8s,k8s,443)]:
    print("  %-34s %s" % (name, c(h, p)))
PY
echo "== web (expect after: api:8000 OPEN, everything else BLOCKED)"
kubectl exec -i -n "$NS" deploy/web -- node - <<'JS'
const net = require("net");
function c(name, h, p) {
  return new Promise(r => {
    const s = net.connect({host: h, port: p, timeout: 3000});
    s.on("connect", () => { s.destroy(); console.log("  " + name.padEnd(34) + " OPEN"); r(); });
    s.on("timeout", () => { s.destroy(); console.log("  " + name.padEnd(34) + " BLOCKED (timeout)"); r(); });
    s.on("error", e => { console.log("  " + name.padEnd(34) + " BLOCKED (" + e.code + ")"); r(); });
  });
}
(async () => {
  await c("api:8000", "api", 8000);
  await c("postgres:5432", "postgres", 5432);
  await c("redis:6379", "redis", 6379);
  await c("1.1.1.1:443", "1.1.1.1", 443);
})();
JS
echo "== redis (expect after: all BLOCKED)"
for t in "postgres 5432" "1.1.1.1 443"; do
  set -- $t
  if kubectl exec -n "$NS" deploy/redis -- nc -z -w 3 "$1" "$2" >/dev/null 2>&1; then r=OPEN; else r=BLOCKED; fi
  printf "  %-34s %s\n" "$1:$2" "$r"
done
echo "== postgres (expect after: all BLOCKED)"
for t in "redis 6379" "1.1.1.1 443"; do
  set -- $t
  if kubectl exec -n "$NS" postgres-0 -- nc -z -w 3 "$1" "$2" >/dev/null 2>&1; then r=OPEN; else r=BLOCKED; fi
  printf "  %-34s %s\n" "$1:$2" "$r"
done
