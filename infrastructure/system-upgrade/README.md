# system-upgrade

Rancher [system-upgrade-controller] (SUC) and version-pinned K3s upgrade Plans,
deployed via ArgoCD. Git is the approval boundary for cluster upgrades.

[system-upgrade-controller]: https://github.com/rancher/system-upgrade-controller

## What is vendored

`templates/crd.yaml` and `templates/controller.yaml` are copied verbatim from
the pinned SUC release (see `Chart.yaml` `appVersion`). One local patch is
applied to `controller.yaml` on top of upstream:

- Add `resources` (requests/limits) and `readOnlyRootFilesystem: true` to the
  controller container so kube-linter passes.

When re-vendoring a new SUC release, re-download both files from the new
release tag and re-apply that patch.

## Plan schema note

The SUC CRD declares `version` and `channel` at the **spec top level**
(`spec.version`), not under `spec.upgrade`. The plan templates here place
`version` accordingly; a nested `spec.upgrade.version` is pruned by the API
server (undeclared in the CRD schema) and the Plan resolves invalid.

## Upgrading the cluster

1. Take/verify an etcd snapshot:

   ```sh
   ssh -t markis@10.0.0.10 'sudo k3s etcd-snapshot save'
   ssh markis@10.0.0.10 'sudo k3s etcd-snapshot ls | tail -3'
   ```

2. Bump `k3sVersion` in `values.yaml` (one minor at a time).
3. Commit and push to `main` — ArgoCD syncs, SUC begins the upgrade.
4. Watch:

   ```sh
   ssh markis@10.0.0.10 'kubectl -n system-upgrade get plans -o wide'
   ssh markis@10.0.0.10 'kubectl -n system-upgrade get jobs -w'
   ssh -t markis@10.0.0.10 'kubectl get nodes -w'
   ```

5. Servers roll one at a time (`concurrency: 1`); agents follow once the
   server plan completes (the agent plan's `prepare` gate waits on
   `k3s-server`).

## Failure modes

- **Failed upgrade job / stuck cordoned node:** diagnose with
  `kubectl -n system-upgrade logs job/<name>`, fix the cause, delete the
  failed job so SUC re-evaluates, and `kubectl uncordon <node>` if needed.
- **Wrong version pinned:** fix `k3sVersion` in Git, push; ArgoCD selfHeal
  applies the corrected Plan.
- **ArgoCD briefly loses API contact** while servers restart — SUC jobs run
  autonomously; reconciliation resumes after.
- **node3** (agent) may jump multiple minors directly to the pinned version —
  k3s binary replacement needs no intermediate steps.
