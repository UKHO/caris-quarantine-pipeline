# Implementation Plan: Deprecate legacy CARIS ACRs — quarantine pipeline slice

**Branch**: `289258-deprecate-caris-acrs` | **Date**: 2026-08-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/289258-deprecate-caris-acrs/spec.md`

**Source PBI**: Azure DevOps #289258 (multi-repo fan-out — this plan covers only the caris-quarantine-pipeline slice)

## Summary

Remove `carispreacr` and `carisliveacr` as promotion targets from the quarantine supply-chain pipeline so scanned images are delivered only to `globalpreacr`/`globalliveacr`. Concretely: delete the legacy registry variables and `*-docker` service connections from `templates/common-variables.yml`, and remove the legacy push stages (`PushToPreACR`, `PushToPrivateRepo`) from `templates/container-scan-template.yml`, preserving the existing global push stages (`PushToGlobalPreACR`, `PushToGlobalLiveACR`) and their `dependsOn` chains. Update the README to the global-only ingestion path.

## Technical Context

**Language/Version**: Azure DevOps Pipelines YAML; Helm/OCI helper scripts under `scripts/`
**Primary Dependencies**: Azure Pipelines, ACR service connections, the quarantine scan/promote templates
**Storage**: N/A (pipeline definitions)
**Testing**: A representative pipeline run against a test image — assert delivery only to the global registries and zero pushes to the legacy registries; YAML lint/validation of the templates
**Target Platform**: Azure DevOps hosted pipelines promoting into Azure Container Registries
**Project Type**: CI/CD pipeline repository
**Performance Goals**: N/A — correctness of promotion targets
**Constraints**: Removing a legacy stage MUST NOT break `dependsOn` of the retained global stages; the legacy registry variable and its `*-docker` service connection must be removed together; no dedicated rollback — forward validation via a pipeline run
**Scale/Scope**: `templates/common-variables.yml`, `templates/container-scan-template.yml`, `README.md`

## Constitution Check

*GATE: Must pass before implementation.*

- Change limited to caris-quarantine-pipeline; no cross-repo edits. PASS
- Global push stages already exist (PBI 288516 complete) — this is a removal, not an addition. PASS
- No secrets edited; service-connection *names* are removed, not credentials. PASS

## Repository Research

- `templates/common-variables.yml` defines both legacy (`destinationRegistry=carisliveacr.azurecr.io`, `preRegistry=carispreacr.azurecr.io`, service connections `carisliveacr-docker`/`carispreacr-docker`) and global (`globalpreacr`/`globalliveacr`) equivalents.
- `templates/container-scan-template.yml` has stages `PushToPreACR`, `PushToPrivateRepo` (legacy) alongside `PushToGlobalPreACR`, `PushToGlobalLiveACR` (retained).
- The retained global stages must keep working; verify their `dependsOn`/conditions do not reference removed legacy stages.

## Threat-Model Constraints (from PBI)

- **Pipeline Risk**: validate the pipeline end-to-end after removal so image delivery is not interrupted.
- **Supply Chain**: ensure every image STG/LIVE needs is still delivered to the global registries.
- **Access Control**: removing legacy service connections must not disturb global-registry auth.

## Phases

1. **Map** — enumerate every reference to the legacy registries/service connections/stages in the templates.
2. **Remove** — delete legacy variables, service connections, and push stages; fix any `dependsOn` on the retained global stages.
3. **Validate** — run the pipeline for a representative image; confirm delivery only to `globalpreacr`/`globalliveacr` and no legacy pushes.
4. **Document** — update `README.md` to the global-only ingestion path.

## Complexity Tracking

> No constitution violations; table intentionally empty.
