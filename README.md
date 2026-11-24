# gitops-paktech-chat

Desired state of the **PakTech Chat** platform on AKS. Argo CD reads this repository and makes the cluster match it.
No secrets live here: runtime secrets come from Azure Key Vault through Workload Identity.

Application, Terraform and CI live in [app-paktech-chat](https://github.com/PakTechLimited/app-paktech-chat).
A guided, phase-by-phase walkthrough is at
[alihaidry-devops.website/tech-series/paktech-chat](https://alihaidry-devops.website/tech-series/paktech-chat).

## Layout

```
bootstrap/                 one-time Argo CD install values and the root Application
platform/apps/             Argo CD Applications, AppProjects and the ApplicationSet (numbered by sync order)
platform/edge/             Gateway API, Envoy proxy settings, certificate issuers, redirects, Grafana route
platform/policies/         Gatekeeper constraint templates and the 7 constraints (all enforced with deny)
platform/monitoring/       PrometheusRules, PodMonitors and Grafana dashboards stored as ConfigMaps
charts/paktech-chat/       Helm chart: API, web, PostgreSQL, Redis, migrate Job, HPA, network policies, metrics
environments/<env>/        values per environment (dev, staging, prod)
scripts/                   render-check, egress-test, base-image-digests, fetch-policies helpers
docs/                      operating notes (base-image digests)
.github/workflows/         render check for pull requests
```

## How it works

```
app repo CI builds and scans an image  ->  commits the new digest to environments/<env>/values.yaml here
Argo CD (root app of apps) detects the commit  ->  renders the Helm chart  ->  syncs in wave order
dev and staging sync automatically; prod shows OutOfSync until a person reads the diff and syncs
```

- **Promotion:** `main` is the source of truth. Environment changes arrive by pull request; promotions use merge commits so history shows what moved.
- **Rollback:** `rollback.yml` in the app repo restores the previous values file with one commit.
- **Images are referenced by digest** (`repo@sha256:...`). The render check fails any change that renders an image line without one.

## Platform components

| Order | Application | Purpose |
|-------|-------------|---------|
| 00 | projects | Argo CD AppProjects |
| 10 | Envoy Gateway | Gateway API implementation, the only entry point |
| 20 | cert-manager | Let's Encrypt certificates (HTTP-01) |
| 30 | edge | Gateway, routes, issuers, HTTP-to-HTTPS redirect |
| 40 | paktech-chat ApplicationSet | one application per environment: dev, staging, prod |
| 50 / 60 | Gatekeeper and policies | admission control, 7 constraints enforcing `deny` |
| 70 | Falco | runtime detection (eBPF) |
| 80 | Trivy Operator | vulnerability reports for running workloads |
| 90 / 95 | kube-prometheus-stack and monitoring config | Prometheus, Grafana, AlertManager (Slack), rules, dashboards |

## Chart features worth knowing

- One chart, three values files. Controls roll out behind flags that are off by default (for example `metrics.enabled`), so merging changes nothing until a flag is enabled for one environment.
- The migrate Job is an Argo CD sync hook with a `wait-for-postgres` init container (digest-pinned image, `pg_isready`, up to 120 s).
- Default-deny network policies in both directions, per-workload egress rules, and no mounted Kubernetes API token.
- Read-only root filesystems with writable `emptyDir` volumes only where needed.

## Checks on pull requests

`.github/workflows/render.yml` runs `scripts/render-check.sh` in about 20 seconds: `helm lint` and `helm template` for dev, staging and prod,
a failure on any image without `@sha256`, and a parse of every platform YAML file and dashboard ConfigMap.
Run it locally before you push:

```bash
pip install pyyaml && bash scripts/render-check.sh
```

## Operating notes

- Base-image digests never move on their own. [docs/base-image-digests.md](docs/base-image-digests.md) describes the rule: adopt a new digest only if its Trivy scan is not worse. `scripts/base-image-digests.sh` compares each pin with the current tag.
- `scripts/egress-test.sh <namespace>` runs a before-and-after egress check from inside the pods.
- Refresh order in Argo CD: refresh `root` first, then the child application.
- The lab cluster was decommissioned in November 2026. To rebuild it, apply the Terraform in `app-paktech-chat`, then bootstrap Argo CD so it syncs the `root` application from this repository.
