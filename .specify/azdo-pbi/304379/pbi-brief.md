# PBI 304379: Quarantine pipeline fails on caris images because Notary signature referrer tags are pulled as container images

Source: Azure DevOps work item #304379 (Bug)

## Repro Steps

The `UKHO.caris-quarantine-pipeline - oci-image-index` pipeline fails whenever a Notary v2 (notation) signature is pushed for a caris multi-arch image in `ukhoacr.azurecr.io`.

Observed in build [20260813.5](https://dev.azure.com/ukhydro/CARIS%20Collaboration/_build/results?buildId=901828) (buildId 901828), source `refs/heads/main` @ `3817dc6` (PR #22 `289258-deprecate-caris-acrs`):

1. An image is signed with notation; the signature is stored as an OCI referrer under the fallback tag `sha256-6b4eed9be656...5d15e` on `caris/bridgepointmonitor` in `ukhoacr.azurecr.io`.
2. That fallback tag is itself an **OCI image index** (`application/vnd.oci.image.index.v1+json`), so the ACR push webhook matches the filter in `quarantine-oci-image-index.yml` and triggers the pipeline.
3. `Detect image platform` cannot find a real platform in the referrer index and logs `Unable to determine OS, defaulting to linux`, so the Linux scan job runs.
4. The `Pull Published Image` step runs `docker pull ukhoacr.azurecr.io/caris/bridgepointmonitor:sha256-6b4eed...` and fails:

```
Pulling image: ***/caris/bridgepointmonitor:sha256-6b4eed9be656334974387abdb3dea8dbd61b5edef442606e6e0c40c74fc5d15e
unsupported media type application/vnd.cncf.notary.signature
##[error]PowerShell exited with code '1'.
```

5. The `ScanContainer` stage fails and a **"Container Scan Failed"** alert is sent to Teams, even though no real image was scanned and nothing is actually vulnerable.

**Frequency / pattern:** Occurs for every notation-signed caris image - i.e. every `sha256-*` signature referrer push to `ukhoacr.azurecr.io`. Correlates with the move to the central ACR in PR #22 (`289258-deprecate-caris-acrs`), which routed signature-referrer pushes into the quarantine webhook.

### Suggested Cause & Fix

**Cause:** The quarantine pipeline treats *any* pushed OCI index as a runnable container image. Notary signature artifacts are published as referrers whose fallback tag (`sha256-`) is an OCI image index, so they satisfy the `target.mediaType == application/vnd.oci.image.index.v1+json` webhook filter. When `templates/steps/scan-container.yml` does a plain `docker pull` of that tag, Docker rejects the signature blob with `unsupported media type application/vnd.cncf.notary.signature`.

**Fix (in `UKHO/caris-quarantine-pipeline`):** Detect and skip signature/attestation/referrer artifacts before scanning, so they don't produce failed runs or false Teams alerts. Options, in preference order:

- In `templates/steps/detect-platform.yml`, when inspecting the manifest, detect referrer/signature indexes - e.g. entries carrying `artifactType` / `annotations` for `application/vnd.cncf.notary.signature`, a `subject` field, or all-`unknown` platforms - and emit an output variable (e.g. `platform.skip=true`).
- Gate the scan jobs in `templates/container-scan-template.yml` on that variable (extend the existing `condition`), and/or short-circuit the `Set pipeline run name` step to a clean success so no failure alert fires.
- As a guard, also skip tags matching the `sha256-*` referrers fallback pattern in `templates/steps/scan-container.yml` before `docker pull`, exiting `0` when the artifact is not a scannable image.

**Investigated, no change required:** `UKHO/public-container-registry` (notation signing behaves as designed) and `UKHO/caris-infra` (the ACR webhook filters on `target.mediaType`, which cannot distinguish a referrer index from a real image, so the fix must live in the pipeline logic).

## System Info

- **Affected pipeline:** `UKHO.caris-quarantine-pipeline - oci-image-index` (definition source: `UKHO/caris-quarantine-pipeline`, `quarantine-oci-image-index.yml`); failing job `Scan Pushed Image (Linux)`, step `Pull Published Image`.
- **Affected service/image (example):** `caris/bridgepointmonitor` (any caris image that gets notation-signed).
- **Source registry:** `ukhoacr.azurecr.io` (central ACR, subscription `Public Container Registry Live` / promotion flow).
- **Agent pool:** Tiberius (`ENVIRONMENT=BUS`), Linux; agents `htfsbusuag01`, Docker/Snyk scan (`UkhoSnykScanTask@0`).
- **Trigger:** ACR push webhook `AcrWebhookTrigger` via service connection `AcrWebhookConnection`, filter `target.mediaType == application/vnd.oci.image.index.v1+json`.
- **Environment:** Live/production container promotion path.
- **Related repos investigated:** `UKHO/caris-quarantine-pipeline` (fix target), `UKHO/caris-infra` (ACR/webhook IaC - no change), `UKHO/public-container-registry` (signing - no change).
- **Reference build:** buildId 901828, run `20260813.5`, completed 2026-08-13 20:30 UTC, ran 91s, commit `3817dc6`.

## Acceptance Criteria

- Given a notation signature referrer tag (`sha256-*`, an OCI image index) is pushed to `ukhoacr.azurecr.io`, when the `caris-quarantine-pipeline` oci-image-index pipeline is triggered, then it recognises the artifact as a non-scannable signature/referrer and does not attempt to `docker pull` or scan it.
- Given a signature/referrer artifact is processed, when the pipeline completes, then the run ends in a non-failed state and **no** "Container Scan Failed" Teams alert is sent.
- Given a genuine multi-arch caris image is pushed, when the pipeline runs, then it still detects the platform, pulls, scans, and promotes the image exactly as before (no regression).
- Given the reference scenario (`caris/bridgepointmonitor` signature `sha256-6b4eed...`), when re-run against the fixed pipeline, then the `Pull Published Image` step no longer fails with `unsupported media type application/vnd.cncf.notary.signature`.

## Child Tasks

1. Reproduce and confirm the signature-referrer trigger path - Re-run buildId 901828 / push a notation signature for a test caris image and confirm the `sha256-*` index triggers the oci-image-index pipeline and fails at `Pull Published Image`.
2. Detect signature/referrer artifacts in detect-platform.yml - Extend `templates/steps/detect-platform.yml` to identify referrer/signature indexes (via `artifactType`, `subject`, notation annotations, or all-`unknown` platforms) and emit a skip output variable.
3. Skip scan/alert for non-scannable artifacts - Gate the scan jobs in `templates/container-scan-template.yml` on the skip variable and short-circuit to a clean success so no failure alert fires. Add a defensive `sha256-*` tag guard in `templates/steps/scan-container.yml` before `docker pull`.
4. Regression-test the real-image path - Verify a genuine multi-arch caris image still detects platform, scans, and promotes to Global Pre/Live ACRs with no behaviour change.
5. Validate Teams alerting - Confirm signature pushes produce no false "Container Scan Failed" alerts, and real vulnerabilities still alert as expected.

## Linked Repositories

- UKHO/caris-quarantine-pipeline (fix target)
- UKHO/caris-infra (investigated - no change)
- UKHO/public-container-registry (investigated - no change)
