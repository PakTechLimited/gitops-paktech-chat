# gitops-paktech-chat

Desired state of the PakTech Chat platform on AKS. Argo CD reads this repository and makes the cluster match it.
No secrets live here: runtime secrets come from Azure Key Vault through Workload Identity.

```
bootstrap/                 one-time Argo CD install values and the root Application
platform/apps/             Argo CD Applications, AppProjects and the ApplicationSet
platform/edge/             Gateway API, Envoy proxy settings, certificate issuers, redirects
charts/paktech-chat/       Helm chart: API, web, PostgreSQL, Redis, migration Job, HPA, network policies
environments/<env>/        values per environment (dev, staging, prod)
```

Stack: Argo CD, Envoy Gateway (Gateway API), cert-manager (Let's Encrypt HTTP-01), Helm.
Changes go through pull requests. dev and staging sync automatically; prod requires a manual sync.
Replace every `REPLACE_WITH_*` placeholder before the first push (`grep -rn REPLACE_WITH .`).
See Section 12 of the PakTech Chat DevSecOps Knowledge Guide for the full runbook.
