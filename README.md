# CARIS Quarantine Pipeline

An Azure DevOps pipeline that implements a quarantine flow for container images: it scans images pushed to a source registry with Snyk, notifies on failures, and promotes (pushes) clean images to a private Azure Container Registry (ACR) under a `scanned/` namespace.

This README documents the practical configuration details, variable and service-connection names the pipeline expects, and a few operational notes to avoid common runtime pitfalls.

## What the pipeline does
- Listens for ACR webhook pushes
- Pulls the pushed image and runs a Snyk container scan
- If the scan passes, tags the image with `-snyk-scanned` and pushes it to the private ACR
- Sends Teams alerts on failure or success (based on configured webhook)

## Key files
- `quarantine-flow-pipeline.yml` — main pipeline YAML (webhook resource, stages: ScanContainer, PushToPrivateRepo, AlertOnSuccess, AlertOnFail)

## Important variables / service connection names (used by the pipeline)
- `sourceRegistryServiceConnection` — e.g. `publiccrlive-docker` (service connection for the source/public registry)
- `destinationRegistryServiceConnection` — e.g. `carisliveacr-docker` (service connection for the private ACR)
- `destinationRegistry` — e.g. `carisliveacr.azurecr.io`
- `snykServiceConnection` — must match your Snyk service connection name (pipeline uses `SnykAuth` by default)
- `snykOrganization` — Snyk org (defaults to `caris-cloud`)
- `teamsWebhookEndpoint` — Power Automate / Teams incoming webhook URL (recommend storing this as a secret variable)

Note: the pipeline also includes a `SetWebhookVars` step that extracts webhook payload values and sets runtime variables like `sourceRepository`, `sourceTag`, `sourceHost` (this avoids relying on compile-time expansions which can be empty for webhooks).

## Recommended setup checklist
1. Create the Docker/ACR service connections in Azure DevOps with names above (or update the YAML to match your names).
2. Give the destination service principal AcrPush permissions on the destination ACR.
3. Install the UkhoSnykScanTask extension (or ensure the Snyk scanning task you use is available).
4. Add the Teams webhook URL as a secret pipeline variable (do NOT commit it in the repo). Example variable name: `teamsWebhookEndpoint` (set its value in the pipeline variable group and mark as secret).
5. Configure the ACR webhook to call the DevOps webhook connection `AcrWebhookTrigger` and ensure the webhook payload contains `target.repository`, `target.tag`, and `request.host`.

## Agents and networking
- The pipeline can run on Microsoft-hosted agents (`ubuntu-latest`) or on your self-hosted VMSS (for example `Mare Nectaris`).
- If you need access to a private ACR over a private endpoint or restricted network, use a self-hosted agent that has the correct network path. Microsoft-hosted agents will not be able to reach private endpoints.

## Troubleshooting tips
- If a stage pushes to the wrong registry, add a debug echo step before tagging/pushing to show the expanded values:

  - echo "Destination service connection: $(destinationRegistryServiceConnection)"
  - echo "Full destination image: $(fullDestinationImageName)"

- If the Teams notification shows the wrong status, verify the job output variables. The pipeline uses per-condition output steps to set `scanStatus` (Succeeded/Failed). Check that the notifier reads the dependency outputs from the `ContainerScan` job.

- If webhook-derived variables are empty, ensure the webhook resource is configured correctly and that the pipeline extracts them at runtime (the `SetWebhookVars` step uses `resources.webhooks.AcrWebhookTrigger` to populate runtime variables).

## Image naming convention
- Source: `{source-registry}/{repository}:{tag}`
- Destination: `{destinationRegistry}/scanned/{repository}:{tag}-snyk-scanned`

Example:
- Source: `publiccrlive.azurecr.io/myapp:v1.0.0`
- Destination: `carisliveacr.azurecr.io/scanned/myapp:v1.0.0-snyk-scanned`

## Security and hygiene
- Store the Teams webhook and any secrets in Azure DevOps variable groups or library as secret variables, not in the repo.
- Limit permissions for the service principal used by `destinationRegistryServiceConnection` to only what it needs (AcrPush / reader on the source).

## Running and testing
- To validate changes, push a test image to the source registry and check the pipeline run logs:
  - Verify `SetWebhookVars` sets `sourceRepository` / `sourceTag` / `sourceHost`
  - Verify Snyk task runs and produces a pass/fail result
  - Verify the push stage (if run) uses the correct `fullDestinationImageName`

