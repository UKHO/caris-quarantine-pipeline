# CARIS Quarantine Pipeline

This repository contains Azure DevOps pipelines that quarantine artifacts pushed to a public Azure Container Registry (ACR). Artifacts are scanned with Snyk and, if clean, promoted to **six** private registries (Caris Pre, Caris Live, Global Pre, and Global Live). Vulnerable artifacts are **not** written to any destination — only a Teams alert is sent.

## Supported artifact flows
- **Docker pipeline** (`quarantine-docker-image.yml`): handles `application/vnd.docker.distribution.manifest.v2+json` pushes, performs a Snyk container scan via `templates/container-scan-template.yml`, and promotes images when they pass.
- **OCI image index pipeline** (`quarantine-oci-image-index.yml`): handles `application/vnd.oci.image.index.v1+json` pushes, uses the same container scan template as the Docker pipeline.
- **Helm pipeline** (`quarantine-helm-chart.yml`): handles `application/vnd.oci.image.manifest.v1+json` pushes, treats the payload as a Helm chart, scans it with Snyk IaC using `templates/helm-scan-template.yml`, and publishes scanned charts to all registries.

All pipelines share the same webhook resource (`AcrWebhookTrigger`) but use manifest-type filters so only the relevant definition runs any stages.

> **Note on hardened images:** The ACR webhook fires for every push to `publiccrlive`, including imports of hardened Docker images (e.g. `dhi/prometheus-operator`). The Helm pipeline guards against processing these by applying a **job-level condition** (`startsWith('caris/charts/', ...)`) in `helm-scan-template.yml` — the entire job is skipped for any repository that is not under `caris/charts/`.

## Registries

| Registry | Purpose | Service Connection (Docker) | Service Connection (Azure Sub) |
| --- | --- | --- | --- |
| `publiccrlive.azurecr.io` | Source — public registry where images/charts arrive | `publiccrlive-docker` | `quarantine-helm-publicacr` |
| `carispreacr.azurecr.io` | Caris Pre — pre-production scanned artifacts | `carispreacr-docker` | `quarantine-helm-preacr` |
| `carisliveacr.azurecr.io` | Caris Live — production scanned artifacts | `carisliveacr-docker` | `quarantine-helm-liveacr` |
| `globalpreacr.azurecr.io` | Global Pre — pre-production (shared platform) | `globalpreacr-docker` | `quarantine-helm-preacr` |
| `globalliveacr.azurecr.io` | Global Live — production (shared platform) | `globalliveacr-docker` | `quarantine-helm-liveacr` |

## High-level behavior
- Listens for ACR webhook pushes (Docker and Helm/OCI) and extracts repository, tag, and registry host from the payload.
- Pulls the referenced artifact and runs the appropriate Snyk scan (container or IaC).
- **On success:** rewrites the tag/version with a `-snyk-scanned` suffix and pushes to `scanned/` namespaces in all four destination registries (Caris Pre → Caris Live, Global Pre → Global Live).
- **On failure:** sends a Teams alert only. No vulnerable-tagged artifacts are written.
- Helm stages authenticate to every registry interaction using `az acr login --expose-token` piped into `helm registry login --password-stdin` for short-lived credentials.

## Architecture overview

| File | Purpose |
| --- | --- |
| `quarantine-docker-image.yml` | Root pipeline for Docker manifest webhook events; references the container template. |
| `quarantine-oci-image-index.yml` | Root pipeline for OCI image index webhook events; references the same container template. |
| `quarantine-helm-chart.yml` | Root pipeline for OCI manifest (Helm) webhook events; references the Helm template. Sets run name to include chart repository and tag. |
| `templates/container-scan-template.yml` | Container workflow: ScanContainer → PushToPreACR + PushToGlobalPreACR (parallel) → PushToPrivateRepo + PushToGlobalLiveACR → alerts. |
| `templates/helm-scan-template.yml` | Helm workflow: ScanHelmChart → PushHelmToPreACRs (both pre registries in one job) → PushHelmToLiveACRs (both live registries in one job) → alerts. |
| `templates/common-variables.yml` | Shared variable definitions for all pipelines (service connections, registry hosts, Snyk config, global registry details). |
| `scripts/helm/HelmPipeline.psm1` | PowerShell module: Helm/ACR helper functions used by the Helm pipeline. |
| `scripts/helm/HelmPipeline.psd1` | PowerShell module manifest. |
| `templates/steps/azurecli-pscore.yml` | Reusable step wrapping `AzureCLI@2` with PowerShell Core; supports optional step name and auto-import of `HelmPipeline`. |
| `templates/steps/helm-push-to-acr.yml` | Reusable step that pushes a packaged Helm chart `.tgz` to an ACR OCI repository. |
| `templates/steps/docker-copy-image.yml` | Reusable step that pulls, retags, and pushes a Docker image between registries. |

### Webhook data flow
1. The ACR webhook calls the shared service URI with payload metadata.
2. Each pipeline filters on `target.mediaType` to ensure only the relevant manifest type executes stages.
3. `${{ parameters.AcrWebhookTrigger.target.repository }}`, `${{ parameters.AcrWebhookTrigger.target.tag }}`, and `${{ parameters.AcrWebhookTrigger.request.host }}` are captured at compile time and passed into the templates as `sourceRepository`, `sourceTag`, and `sourceHost`.

## Container pipeline (Docker / OCI image index)
`templates/container-scan-template.yml` handles both Docker and OCI image index artifacts:
- Authenticates against source and all destination registries via Docker service connections.
- Pulls the pushed image, runs `UkhoSnykScanTask@0` in container mode.
- On success, pushes the scanned image (tagged `-snyk-scanned`) to all four registries in parallel chains:
  - **Caris path:** PushToPreACR (ENG) → PushToPrivateRepo (BUS)
  - **Global path:** PushToGlobalPreACR (ENG) → PushToGlobalLiveACR (BUS)
- On failure, sends a Teams notification only.

Required service connections (defined via `templates/common-variables.yml`):
- Docker: `publiccrlive-docker`, `carispreacr-docker`, `carisliveacr-docker`, `globalpreacr-docker`, `globalliveacr-docker`
- `SnykAuth` for Snyk scanning.
- `teamsWebhookEndpoint` secret (from `caris-quarantine` variable group).

## Helm pipeline (OCI manifest)
`templates/helm-scan-template.yml` handles Helm charts packaged as OCI artifacts:
- Uses AzureCLI steps bound to Azure subscriptions (`sourceAzureSubscription`, `preAzureSubscription`, `liveAzureSubscription`) for registry interactions.
- Pulls the OCI Helm chart, infers the semantic version from the chart manifest, and unpacks it for scanning.
- Runs `UkhoSnykScanTask@0` in IaC mode against the extracted chart contents.
- On success, repackages with a `-snyk-scanned` version suffix and pushes to both pre ACRs in a single job, then pulls from source again and pushes original version to both live ACRs in a single job.
- On failure, sends a Teams notification only.

The Helm pipeline is simplified to avoid unnecessary round-trips:
- Source is pulled only twice (once for pre, once for live) — no intermediate pull from pre ACRs.
- Both pre registries and both live registries are pushed to within a single job each, eliminating code duplication.


### Helm pipeline module and step templates
The Helm pipeline keeps orchestration (stage flow, conditions) in YAML and moves mechanics into a PowerShell module.

- The PowerShell module lives in [scripts/helm/HelmPipeline.psm1](scripts/helm/HelmPipeline.psm1) and is imported via [scripts/helm/HelmPipeline.psd1](scripts/helm/HelmPipeline.psd1).
- Common operations: `Get-AcrAccessToken`, `Invoke-HelmRegistryPull`, `Invoke-HelmRegistryPush`, `Get-AcrLatestTag`, `Get-HelmChartArchiveFromRegistry`, `Invoke-HelmRepackageWithVersion`.
- Step templates (`azurecli-pscore.yml`, `helm-push-to-acr.yml`) avoid repeating AzureCLI boilerplate.

Additional variables the Helm pipeline expects (see `quarantine-helm-chart.yml`):
- `sourceAzureSubscription`, `preAzureSubscription`, `liveAzureSubscription` (Azure service connections with ACR RBAC).
- The same registry hostnames, Snyk settings, and Teams webhook variables used by the container pipelines.

## Setup checklist
1. **Service connections**
   - Docker: `publiccrlive-docker`, `carispreacr-docker`, `carisliveacr-docker`, `globalpreacr-docker`, `globalliveacr-docker`.
   - Azure subscriptions for Helm: `quarantine-helm-publicacr`, `quarantine-helm-preacr`, `quarantine-helm-liveacr`.
   - `SnykAuth` for Snyk scanning.
   - `AcrWebhookConnection` for the shared webhook resource.
   - Docker registry service connections are configured as **Azure Container Registry - Workload Identity Federation** connections.
2. **Pipelines**
   - Create three Azure DevOps pipeline definitions pointing to `quarantine-docker-image.yml`, `quarantine-oci-image-index.yml`, and `quarantine-helm-chart.yml`.
3. **Permissions**
   - Docker service principals: AcrPull on source, AcrPush on all destination registries (carispreacr, carisliveacr, globalpreacr, globalliveacr).
   - Helm Azure subscription SPs: AcrPush + Reader on globalpreacr/globalliveacr (managed via `acr_manager_sp_names` in `caris-infra/terraform/global`).
   - Workload identity federation connections: AcrPull (source) and AcrPush (destinations).
4. **Extensions**
   - Install UkhoSnykScanTask (or equivalent) in your organization.
5. **Webhook**
   - Configure the ACR webhook to call `https://dev.azure.com/{org}/_apis/public/distributedtask/webhooks/AcrWebhookTrigger?api-version=6.0-preview` and include `target.repository`, `target.tag`, `target.mediaType`, and `request.host`.

## Agents and networking
- Both templates target the `Tiberius` and `Mare Nectaris` self-hosted pools because they reside on the private network that can reach the ACRs. Update the `pool` definitions if you need Microsoft-hosted agents (ensure network egress is allowed).
- For private endpoints, the agent must sit inside the same VNet/subnet as the registries.

## Artifact naming conventions
### Containers
- Successful scan: `{registry}/scanned/{repository}:{tag}-snyk-scanned` - pushed to all four destination registries.
- Failed scan: no artifacts written; Teams alert sent only.

### Helm charts
- Successful scan in Pre ACRs: `oci://{preRegistry}/scanned/charts/{chartName}:{chartVersion}-snyk-scanned`.
- Successful scan in Live ACRs: `oci://{liveRegistry}/scanned/charts/{chartName}:{chartVersion}` (original version, no suffix).
- Failed scan: no artifacts written; Teams alert sent only.

## Security considerations
- Helm interactions never persist Docker credentials; each push/pull uses `az acr login --expose-token` plus `helm registry login --password-stdin` and immediately logs out.
- Store `teamsWebhookEndpoint` and any sensitive values inside a variable group (`caris-quarantine`).
- Scope service connections to the minimum required registries and limit RBAC roles (AcrPull/AcrPush) to the required namespaces.

## Troubleshooting
- **Pipeline not triggering**: confirm the webhook filters (`target.mediaType`) match the manifest type you are pushing.
- **Wrong pipeline triggered**: Azure DevOps will still start all pipeline definitions, but the manifest filter ensures only the matching one runs any jobs.
- **Empty webhook parameters**: ensure you reference `${{ parameters.AcrWebhookTrigger.* }}` inside the YAML; runtime variables will be empty.
- **Helm auth failures**: verify the Azure subscription has AcrPush + Reader rights on the target registry and that the agent has Helm 3 installed.

## Validation tips
- Push a Docker image and confirm the container pipelines push scanned images to all four registries.
- Push a Helm chart (OCI artifact) and confirm the Helm pipeline rewrites the chart version and pushes to all registries.
- Push a hardened image and confirm the Helm quarantine pipeline shows `HelmChartScan` as **Skipped**.
