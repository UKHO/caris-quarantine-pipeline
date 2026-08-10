# PBI 289258: Deprecate carispreacr and carisliveacr Container Registries

Source: Azure DevOps work item #289258

## Description

### What

Deprecate the **carispreacr** and **carisliveacr** Azure Container Registries and transition all platform workloads to use the **globalpreacr** and **globalliveacr** registries as the authoritative internal image sources.

This includes:

- Updating all **GitOps references** in:
  - caris-bootstrap
  - caris-services
  - ukho-backstage
- Ensuring all HelmReleases and Kustomizations reference images from:
  - globalpreacr
  - globalliveacr
- Validating that no STG or LIVE workloads use images from legacy registries.
- Updating the **quarantine pipeline** to remove promotion targets for legacy registries.
- Removing legacy registries from:
  - caris-infra Terraform
  - Infrastructure deployment pipeline
- Validating platform health via the caris-infra smoke test pipeline.

### Why

The current model uses multiple internal registries (carispreacr, carisliveacr, globalpreacr, globalliveacr), which creates:

- Duplication of images across registries
- Increased operational overhead
- Inconsistent deployment sources
- Reduced clarity on authoritative image sources

Deprecating the legacy registries enables:

- **Platform Simplification** — single authoritative registries per environment: PRE -> globalpreacr, LIVE -> globalliveacr.
- **Supply Chain Consistency** — standard pipeline publiccrlive -> quarantine -> global ACRs; eliminates parallel registry usage.
- **Operational Efficiency** — reduced registry management overhead, simplified pipeline configuration, clear separation of environments.
- **Governance & Security** — reduced attack surface, easier audit and traceability, enforced standard ingestion path.

### How

- **GitOps Transition** — update all image and chart references in caris-bootstrap, caris-services and ukho-backstage so only globalpreacr and globalliveacr are referenced.
- **Workload Validation** — inspect STG and LIVE workloads; validate no usage of carispreacr or carisliveacr and confirm all workloads pull from global registries.
- **Quarantine Pipeline Update** — remove carispreacr and carisliveacr from promotion targets; ensure only global registries receive scanned images.
- **Terraform Cleanup (caris-infra)** — remove carispreacr and carisliveacr resources; apply changes via infrastructure pipeline.
- **Validation** — execute the caris-infra smoke test pipeline; validate all workloads healthy, no image pull failures, no regression.
- **Final Decommission** — confirm no dependencies on legacy registries; decommission carispreacr and carisliveacr.

## Acceptance Criteria

- All image references in caris-bootstrap, caris-services and ukho-backstage use only globalpreacr and globalliveacr.
- No workloads in STG or LIVE use images from carispreacr or carisliveacr.
- All required images are present in the global registries.
- Quarantine pipeline no longer pushes to legacy registries.
- Terraform configuration no longer includes legacy registries.
- Infrastructure pipeline successfully applies changes.
- caris-infra smoke test pipeline passes successfully.
- No image pull or deployment failures occur.
- Platform operates normally post-transition.
- Legacy registries are fully decommissioned.

## Threat Model

| Category | Threat | Mitigation |
| --- | --- | --- |
| Availability | Workloads fail to start due to incorrect image references | Validate updates in lower environments before rollout |
| Misconfiguration | Residual references to deprecated registries remain | Perform full search and validation across repos |
| Supply Chain | Images not available in global registries | Ensure all required images are promoted before cutover |
| Drift | Inconsistent use of registries across environments | Enforce GitOps configuration standards |
| Deployment Risk | Incorrect Helm/Kustomize updates break deployments | Test changes incrementally and validate in STG |
| Pipeline Risk | Quarantine pipeline stops delivering images correctly | Validate pipeline after removing legacy registries |
| Access Control | Incorrect permissions to global registries | Verify ACR permissions for all consuming workloads |
| Auditability | Loss of traceability during transition | Maintain logs of all migration steps |
| Rollback Risk | Inability to revert if failure occurs | Maintain rollback path until validation complete |
| Dependency Risk | Hidden dependencies on legacy registries | Identify all references before removal |

## Things To Consider

Blocked By:

- Product Backlog Item 288516 - Update Quarantine Pipeline to Deliver Images to New Global ACRs
- Product Backlog Item 289224 - Transition Teledyne to publiccrlive Azure Container Registry (BLOCKED)

## Child Tasks

1. Discovery - Identify all references to carispreacr and carisliveacr; confirm image availability in global registries.
2. GitOps Update - Update image references in caris-bootstrap, caris-services and ukho-backstage.
3. Validation (Pre-Cleanup) - Validate workloads in STG use globalpreacr; validate workloads in LIVE use globalliveacr.
4. Pipeline Update - Remove legacy registries from quarantine pipeline; validate image promotion to global registries only.
5. Terraform Cleanup - Remove ACR resources for carispreacr and carisliveacr; apply changes via infrastructure pipeline.
6. Testing & Validation - Run caris-infra smoke test pipeline; validate application health; validate image pull success across all services.
7. Decommission - Verify no remaining dependencies; decommission legacy registries.
8. Documentation - Update platform documentation to reflect new registry model; document deprecation and migration approach; provide guidance for future image usage.

## Linked Repositories

- UKHO/caris-infra
- UKHO/caris-bootstrap
- UKHO/caris-services
