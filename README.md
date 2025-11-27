# CARIS Quarantine Pipeline

An Azure DevOps pipeline that implements a quarantine flow for container images: it scans images pushed to a source registry with Snyk, notifies on failures, and promotes (pushes) clean images to a private Azure Container Registry (ACR) under a `scanned/` namespace.

This README documents the practical configuration details, variable and service-connection names the pipeline expects, and a few operational notes to avoid common runtime pitfalls.

## What the pipeline does
- Listens for ACR webhook pushes (supports both Docker and OCI image formats)
- Pulls the pushed image and runs a Snyk container scan
- If the scan passes, tags the image with `-snyk-scanned` and pushes it to both Pre and Live private ACRs
- If the scan fails, tags the image with `-vulnerable` and pushes it to vulnerable namespaces
- Sends Teams alerts on failure or success (based on configured webhook)

## Architecture
The pipeline uses a modular template-based structure:

### Key files
- `quarantine-flow-pipeline-docker.yml` — Pipeline for Docker manifest format images (filters on `application/vnd.docker.distribution.manifest.list.v2+json`)
- `quarantine-flow-pipeline-oci.yml` — Pipeline for OCI manifest format images (filters on `application/vnd.oci.image.index.v1+json`)
- `templates/container-scan-template.yml` — Shared template containing all stages (ScanContainer, PushToPreACR, PushToPrivateRepo, AlertOnSuccess, AlertOnFail)

### How it works
1. Both pipelines listen to the same webhook resource `AcrWebhookTrigger` but use different filters based on image manifest type
2. Webhook data (repository, tag, host) is extracted from `${{ parameters.AcrWebhookTrigger.*}}` and passed to the template
3. The shared template handles all scanning, pushing, and alerting logic
4. Create separate pipeline definitions in Azure DevOps pointing to each YAML file

## Important variables / service connection names (used by the pipeline)

These variables are defined in the root pipeline files and passed to the template:

- `sourceRegistryServiceConnection` — e.g. `publiccrlive-docker` (service connection for the source/public registry)
- `destinationRegistryServiceConnection` — e.g. `carisliveacr-docker` (service connection for the Live private ACR)
- `preRegistryServiceConnection` — e.g. `carispreacr-docker` (service connection for the Pre private ACR)
- `destinationRegistry` — e.g. `carisliveacr.azurecr.io` (Live ACR hostname)
- `preRegistry` — e.g. `carispreacr.azurecr.io` (Pre ACR hostname)
- `snykServiceConnection` — must match your Snyk service connection name (pipeline uses `SnykAuth` by default)
- `snykOrganization` — Snyk org (defaults to `caris-cloud`)
- `teamsWebhookEndpoint` — Power Automate / Teams incoming webhook URL

### Webhook data extraction
Webhook payload values are extracted at compile-time using:
- `${{ parameters.AcrWebhookTrigger.target.repository }}` → source repository name
- `${{ parameters.AcrWebhookTrigger.target.tag }}` → source image tag
- `${{ parameters.AcrWebhookTrigger.request.host }}` → source registry hostname

These are passed as template parameters and used throughout the pipeline stages.

## Recommended setup checklist

### Azure DevOps Configuration
1. **Create service connections** in Azure DevOps with names matching the YAML (or update the YAML to match your names):
   - `publiccrlive-docker` (source registry)
   - `carisliveacr-docker` (Live destination ACR)
   - `carispreacr-docker` (Pre destination ACR)
   - `SnykAuth` (Snyk authentication)
   - `AcrWebhookConnection` (incoming webhook connection)

2. **Create two pipeline definitions** in Azure DevOps:
   - Pipeline 1: Point to `quarantine-flow-pipeline-docker.yml`
   - Pipeline 2: Point to `quarantine-flow-pipeline-oci.yml`
   - Both pipelines should use the same default branch

3. **Grant ACR permissions**:
   - Give the destination service principals AcrPush permissions on both Pre and Live ACRs
   - Ensure source registry service principal has AcrPull permissions

4. **Install extensions**:
   - Install the UkhoSnykScanTask extension (or ensure your Snyk scanning task is available)

### ACR Webhook Configuration
5. **Configure ACR webhook**:
   - Service URI: `https://dev.azure.com/{org}/_apis/public/distributedtask/webhooks/AcrWebhookTrigger?api-version=6.0-preview`
   - Ensure the webhook payload contains `target.repository`, `target.tag`, `target.mediaType`, and `request.host`
   - Both Docker and OCI pushes will call the same webhook endpoint; filters in the pipelines determine which runs

6. **Teams notifications** (optional):
   - The Teams webhook URL is hardcoded in the YAML files
   - For better security, consider storing this as a secret variable in a variable group and referencing it instead

## Agents and networking
- The pipeline can run on Microsoft-hosted agents (`ubuntu-latest`) or on your self-hosted VMSS (for example `Mare Nectaris`).
- If you need access to a private ACR over a private endpoint or restricted network, use a self-hosted agent that has the correct network path. Microsoft-hosted agents will not be able to reach private endpoints.

## Troubleshooting tips

### Pipeline not triggering
- Verify the ACR webhook is configured with the correct URL: `https://dev.azure.com/{org}/_apis/public/distributedtask/webhooks/AcrWebhookTrigger?api-version=6.0-preview`
- Ensure both pipeline definitions exist in Azure DevOps and point to the correct YAML files
- Check that `trigger: none` and `pr: none` are set in the YAML (prevents CI/PR triggers)
- Run each pipeline manually once after creation to register the webhook endpoint
- Verify the service connection `AcrWebhookConnection` is authorized for both pipelines

### Both pipelines triggering simultaneously
- This is expected behavior - both pipelines listen to the same webhook but use filters
- The filter should cause the wrong pipeline to skip, but Azure DevOps may still show it as triggered
- If you need completely separate webhooks, change the webhook names to `AcrWebhookTriggerDocker` and `AcrWebhookTriggerOCI` and create two ACR webhooks

### Empty webhook variables
- Webhook data must be accessed via `${{ parameters.AcrWebhookTrigger.* }}` (compile-time)
- Variables defined at root level store these values and pass them to the template
- Check the first step output to verify `sourceRepository`, `sourceTag`, and `sourceHost` are populated

### Wrong registry or naming issues
- Verify variables in the pipeline YAML match your service connection names
- Check that the template receives the correct parameters from the root pipeline file

## Image naming convention

### Successful scan (clean images)
- Source: `{source-registry}/{repository}:{tag}`
- Pre ACR: `{preRegistry}/scanned/{repository}:{tag}-snyk-scanned`
- Live ACR: `{destinationRegistry}/scanned/{repository}:{tag}-snyk-scanned`

Example:
- Source: `publiccrlive.azurecr.io/myapp:v1.0.0`
- Pre: `carispreacr.azurecr.io/scanned/myapp:v1.0.0-snyk-scanned`
- Live: `carisliveacr.azurecr.io/scanned/myapp:v1.0.0-snyk-scanned`

### Failed scan (vulnerable images)
- Source: `{source-registry}/{repository}:{tag}`
- Pre ACR: `{preRegistry}/vulnerable/{repository}:{tag}-vulnerable`
- Live ACR: `{destinationRegistry}/vulnerable/{repository}:{tag}-vulnerable`

Example:
- Source: `publiccrlive.azurecr.io/myapp:v1.0.0`
- Pre: `carispreacr.azurecr.io/vulnerable/myapp:v1.0.0-vulnerable`
- Live: `carisliveacr.azurecr.io/vulnerable/myapp:v1.0.0-vulnerable`

## Security and hygiene
- Store the Teams webhook and any secrets in Azure DevOps variable groups or library as secret variables, not in the repo.
- Limit permissions for the service principal used by `destinationRegistryServiceConnection` to only what it needs (AcrPush / reader on the source).

## Running and testing
- To validate changes, push a test Docker or OCI image to the source registry and check the pipeline run logs:
  - Verify the correct pipeline triggers based on manifest type (Docker vs OCI)
  - Check that webhook parameters are populated: `sourceRepository`, `sourceTag`, `sourceHost`
  - Verify Snyk task runs and produces a pass/fail result
  - For successful scans: verify images are pushed to both Pre and Live ACRs under the `scanned/` namespace
  - For failed scans: verify images are pushed to both Pre and Live ACRs under the `vulnerable/` namespace
  - Check that Teams notifications are sent with correct status and image details

