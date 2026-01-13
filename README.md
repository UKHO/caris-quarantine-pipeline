# CARIS Quarantine Pipeline

This repository contains two Azure DevOps pipelines that quarantine artifacts pushed to a public Azure Container Registry (ACR). The Docker flow scans container images before promoting them; the OCI flow now focuses exclusively on Helm charts packaged in OCI format. Clean artifacts are promoted to Pre and Live ACRs under a `scanned/` namespace, while vulnerable artifacts are isolated in `vulnerable/` paths and trigger Teams alerts.

## Supported artifact flows
- **Docker pipeline** (`caris-quarantine-flow-pipeline-docker.yml`): handles `application/vnd.docker.distribution.manifest.v2+json` pushes, performs a Snyk container scan via `templates/container-scan-template.yml`, and promotes images when they pass.
- **OCI pipeline** (`caris-quarantine-flow-pipeline-oci.yml`): handles `application/vnd.oci.image.manifest.v1+json` pushes, treats the payload as a Helm chart, scans it with Snyk IaC using `templates/helm-scan-template.yml`, and publishes signed Helm charts to Pre and Live registries.

Both pipelines share the same webhook resource (`AcrWebhookTrigger`) but use manifest-type filters so only the relevant definition runs any stages.

## High-level behavior
- Listens for ACR webhook pushes (Docker and Helm/OCI) and extracts repository, tag, and registry host from the payload.
- Pulls the referenced artifact and runs the appropriate Snyk scan (container or IaC).
- On success: rewrites the tag/version with a `-snyk-scanned` suffix and pushes to Pre and Live quarantine registries.
- On failure: retags to `-vulnerable`, pushes to an isolated namespace, and posts to the configured Teams webhook.
- Helm stages authenticate to every registry interaction using `az acr login --expose-token` piped into `helm registry login --password-stdin` for short-lived credentials.

## Architecture overview

| File | Purpose |
| --- | --- |
| `caris-quarantine-flow-pipeline-docker.yml` | Root pipeline subscribed to Docker manifest webhook events; references the container template only. |
| `caris-quarantine-flow-pipeline-oci.yml` | Root pipeline subscribed to OCI manifest webhook events; references the dedicated Helm template only. |
| `templates/container-scan-template.yml` | Implements the container workflow (ScanContainer → PushToPreACR → PushToPrivateRepo → alert stages). |
| `templates/helm-scan-template.yml` | Implements the Helm workflow (ScanHelmChart → push scanned chart to Pre/Live → alerts, plus a vulnerable-rollback path).

### Webhook data flow
1. The ACR webhook calls the shared service URI with payload metadata.
2. Each pipeline filters on `target.mediaType` to ensure only the relevant manifest type executes stages.
3. `${{ parameters.AcrWebhookTrigger.target.repository }}`, `${{ parameters.AcrWebhookTrigger.target.tag }}`, and `${{ parameters.AcrWebhookTrigger.request.host }}` are captured at compile time and passed into the templates as `sourceRepository`, `sourceTag`, and `sourceHost`.

## Container pipeline (Docker manifest)
`templates/container-scan-template.yml` contains all Docker-specific logic:
- Authenticates against source/pre/live registries via Docker tasks bound to service connections.
- Pulls the pushed image, runs `UkhoSnykScanTask@0` in container mode, and tags clean artifacts with `-snyk-scanned`.
- Pushes clean images to `scanned/{repository}` namespaces in both Pre and Live ACRs, or to `vulnerable/{repository}` when the scan fails.
- Sends Teams notifications from the success/failure stages.

Required root variables/service connections (defined in `caris-quarantine-flow-pipeline-docker.yml`):
- `sourceRegistryServiceConnection`, `preRegistryServiceConnection`, `destinationRegistryServiceConnection`.
- `preRegistry`, `destinationRegistry` hostnames.
- `snykServiceConnection` (`SnykAuth`) and `snykOrganization`.
- `teamsWebhookEndpoint` secret (from `caris-quarantine` variable group).

## Helm pipeline (OCI manifest)
`templates/helm-scan-template.yml` was introduced to isolate Helm/OCI logic from the Docker template. Key behavior:
- Uses AzureCLI steps bound to three Azure subscriptions (`sourceAzureSubscription`, `preAzureSubscription`, `liveAzureSubscription`) so the Helm stages can interact with each registry independently.
- Pulls the OCI Helm chart referenced by the webhook, infers the semantic version from the chart manifest, and unpacks it for scanning.
- Runs `UkhoSnykScanTask@0` in IaC mode against the extracted chart contents.
- Repackages clean charts with a `-snyk-scanned` suffix, pushes to Pre (`oci://{preRegistry}/scanned/charts`), then strips the suffix and promotes to Live.
- On scan failure, republishes to `vulnerable/{sourceRepository}` inside the Pre registry for forensic use.
- Every Helm pull/push obtains an access token with `az acr login --expose-token`, feeds it into `helm registry login --password-stdin`, and ensures `helm registry logout` executes via `try/finally` blocks.

Additional variables this pipeline expects (see `caris-quarantine-flow-pipeline-oci.yml`):
- `sourceAzureSubscription`, `preAzureSubscription`, `liveAzureSubscription` (match Azure service connections that have ACR RBAC).
- The same registry service connections, hostnames, Snyk settings, and Teams webhook variables used by the Docker pipeline.

## Setup checklist
1. **Service connections**
   - `publiccrlive-docker`, `carispreacr-docker`, `carisliveacr-docker` for Docker tasks.
   - Azure subscriptions for Helm interactions (`quarantine-helm-publicacr`, `quarantine-helm-preacr`, `quarantine-helm-liveacr` in our environment).
   - `SnykAuth` for Snyk scanning.
   - `AcrWebhookConnection` for the shared webhook resource.
2. **Pipelines**
   - Create two Azure DevOps pipeline definitions pointing to `caris-quarantine-flow-pipeline-docker.yml` and `caris-quarantine-flow-pipeline-oci.yml` on the same branch.
3. **Permissions**
   - Ensure the Docker service principals have AcrPull (source) and AcrPush (Pre/Live) as appropriate.
   - Grant the Helm Azure subscriptions AcrPull/AcrPush on their respective registries.
4. **Extensions**
   - Install UkhoSnykScanTask (or equivalent) in your organization.
5. **Webhook**
   - Configure the ACR webhook to call `https://dev.azure.com/{org}/_apis/public/distributedtask/webhooks/AcrWebhookTrigger?api-version=6.0-preview` and include `target.repository`, `target.tag`, `target.mediaType`, and `request.host`.

## Agents and networking
- Both templates currently target the `Tiberius` and `Mare Nectaris` self-hosted pools because they reside on the private network that can reach the ACRs. Update the `pool` definitions if you need Microsoft-hosted agents (ensure network egress is allowed).
- For private endpoints, the agent must sit inside the same VNet/subnet as the registries.

## Artifact naming conventions
### Containers
- Successful scan: `{destinationRegistry}/scanned/{repository}:{tag}-snyk-scanned` (and equivalent Pre path).
- Failed scan: `{destinationRegistry}/vulnerable/{repository}:{tag}-vulnerable` (mirrored to Pre).

### Helm charts
- Successful scan stored in Pre: `oci://{preRegistry}/scanned/charts/{chartName}:{chartVersion}-snyk-scanned`.
- Live promotion restores the original version (without suffix) before pushing to `oci://{destinationRegistry}/scanned/charts/{chartName}:{chartVersion}`.
- Failed scan: `oci://{preRegistry}/vulnerable/{sourceRepository}:{chartVersion}-vulnerable`.

## Security considerations
- Helm interactions never persist Docker credentials; each push/pull uses `az acr login --expose-token` plus `helm registry login --password-stdin` and immediately logs out.
- Store `teamsWebhookEndpoint` and any sensitive values inside a variable group (`caris-quarantine`).
- Scope service connections to the minimum required registries and limit RBAC roles (AcrPull/AcrPush) to the required namespaces.

## Troubleshooting
- **Pipeline not triggering**: confirm the webhook filters (`target.mediaType`) match the manifest type you are pushing.
- **Wrong pipeline triggered**: Azure DevOps will still start both pipeline definitions, but the manifest filter ensures only the matching one runs any jobs. Non-matching pipelines should skip at the stage level.
- **Empty webhook parameters**: ensure you reference `${{ parameters.AcrWebhookTrigger.* }}` inside the YAML; runtime variables will be empty.
- **Helm auth failures**: verify the Azure subscription has AcrPull/AcrPush rights and that the agent has Helm 3 installed; check logs for the `helm registry login` step to confirm tokens are being issued.

## Validation tips
- Push a Docker image with media type `application/vnd.docker.distribution.manifest.v2+json` and confirm only the Docker pipeline executes the container template.
- Push a Helm chart (OCI artifact) and confirm the OCI pipeline runs the Helm template, rewrites the chart version, and pushes to both Pre and Live.
- Review the Teams alerts to ensure they reference the correct registry hostnames and repositories.

