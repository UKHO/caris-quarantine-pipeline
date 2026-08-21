# Feature Specification: Skip Notary signature referrer artifacts in the caris quarantine pipeline

**Feature Branch**: `304379-quarantine-pipeline-notary-signature-referrer`  
**Created**: 2026-08-20  
**Status**: Draft  
**Source PBI**: Azure DevOps #304379  
**Input**: Bug #304379 - "Quarantine pipeline fails on caris images because Notary signature referrer tags are pulled as container images"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Signature referrer pushes do not fail the quarantine pipeline (Priority: P1)

When a Notary v2 (notation) signature is pushed for a caris image, the signature is stored as an OCI referrer whose fallback tag (`sha256-*`) is itself an OCI image index. Today this satisfies the ACR push webhook filter (`target.mediaType == application/vnd.oci.image.index.v1+json`) and triggers the oci-image-index quarantine pipeline, which then tries to `docker pull` and scan a non-image artifact and fails. A platform engineer needs these signature/referrer pushes to be recognised as non-scannable and skipped cleanly.

**Why this priority**: This is the core defect. Every notation-signed caris image currently produces a failed pipeline run, blocking clean signal on the promotion path and eroding trust in the quarantine gate.

**Independent Test**: Push (or re-run against) a notation signature referrer tag such as `caris/bridgepointmonitor:sha256-6b4eed...` in `ukhoacr.azurecr.io` and confirm the pipeline recognises it as a signature/referrer artifact and does not attempt to pull or scan it, ending in a non-failed state.

**Acceptance Scenarios**:

1. **Given** a notation signature referrer tag (`sha256-*`, an OCI image index) is pushed to `ukhoacr.azurecr.io`, **When** the oci-image-index quarantine pipeline is triggered, **Then** it identifies the artifact as a non-scannable signature/referrer and does not attempt to `docker pull` or scan it.
2. **Given** the reference scenario (`caris/bridgepointmonitor` signature `sha256-6b4eed...`), **When** re-run against the fixed pipeline, **Then** the pull/scan step no longer fails with `unsupported media type application/vnd.cncf.notary.signature`.

---

### User Story 2 - No false "Container Scan Failed" alerts for signature artifacts (Priority: P1)

Because signature pushes currently fail the scan stage, a "Container Scan Failed" alert is sent to Teams even though no real image was scanned and nothing is vulnerable. Platform engineers need these false alerts to stop so real alerts remain meaningful.

**Why this priority**: False alerts create noise, cause alert fatigue, and undermine the credibility of the quarantine gate - as damaging operationally as the failed run itself.

**Independent Test**: Trigger the pipeline with a signature/referrer push and confirm no "Container Scan Failed" Teams alert is raised.

**Acceptance Scenarios**:

1. **Given** a signature/referrer artifact is processed, **When** the pipeline completes, **Then** the run ends in a non-failed state and no "Container Scan Failed" Teams alert is sent.

---

### User Story 3 - Genuine caris images continue to be scanned and promoted (Priority: P1)

The fix must not regress the happy path: real multi-arch caris images must still be detected, pulled, scanned, and promoted exactly as before, and genuine vulnerabilities must still raise alerts.

**Why this priority**: The quarantine gate is a security control on the production promotion path. Any regression that lets a real image bypass scanning would be a serious security gap.

**Independent Test**: Push a genuine multi-arch caris image and confirm it still detects the platform, pulls, scans, promotes to the Global Pre/Live ACRs, and that a seeded vulnerability still raises an alert.

**Acceptance Scenarios**:

1. **Given** a genuine multi-arch caris image is pushed, **When** the pipeline runs, **Then** it still detects the platform, pulls, scans, and promotes the image exactly as before (no regression).
2. **Given** a genuine image with a known vulnerability is scanned, **When** the scan completes, **Then** the existing "Container Scan Failed" alerting still fires as expected.

---

### Edge Cases

- What happens for a referrer index that carries a `subject` field but no recognised notation `artifactType`/annotations (e.g. a future attestation/SBOM referrer)? It should also be treated as non-scannable rather than pulled.
- What happens if the manifest inspection reports all platforms as `unknown`/`unknown`? This should be treated as a signal that the artifact is not a runnable image.
- What happens if manifest inspection itself fails or is ambiguous? The pipeline must fail safe - it must not silently skip a genuine image without scanning.
- What happens if a real image tag coincidentally matches the `sha256-*` fallback pattern? The `sha256-*` tag guard is defensive only; primary detection must be based on artifact/media-type inspection.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pipeline MUST inspect each triggering OCI index artifact and determine whether it is a scannable container image or a non-scannable signature/referrer/attestation artifact before attempting to pull it.
- **FR-002**: The pipeline MUST classify an artifact as non-scannable when it exhibits notation-signature characteristics - e.g. an `artifactType`/annotations of `application/vnd.cncf.notary.signature`, the presence of a `subject` (referrer) field, or all platforms reported as `unknown`.
- **FR-003**: When an artifact is classified as non-scannable, the pipeline MUST skip the `docker pull` and scan steps for that artifact.
- **FR-004**: When a non-scannable artifact is skipped, the pipeline run MUST end in a non-failed state.
- **FR-005**: When a non-scannable artifact is skipped, the pipeline MUST NOT send a "Container Scan Failed" Teams alert.
- **FR-006**: The pipeline MUST provide a defensive guard that skips tags matching the `sha256-*` referrers fallback pattern before `docker pull`, exiting successfully when the artifact is not a scannable image.
- **FR-007**: The pipeline MUST continue to detect platform, pull, scan, and promote genuine multi-arch caris images with no behavioural change.
- **FR-008**: The pipeline MUST continue to raise the existing failure/alerting behaviour for genuine images that fail scanning.
- **FR-009**: The pipeline MUST fail safe: if artifact classification is ambiguous or manifest inspection errors, it MUST NOT skip scanning of what could be a genuine image.

### Key Entities *(include if feature involves data)*

- **OCI image index**: The multi-arch manifest list (`application/vnd.oci.image.index.v1+json`) that the ACR webhook filters on; the type shared by both genuine multi-arch images and notation signature referrer fallback tags.
- **Notation signature referrer**: An OCI artifact published as a referrer to a signed image, stored under a `sha256-*` fallback tag, carrying `application/vnd.cncf.notary.signature` and a `subject` reference - not a runnable image.
- **Scannable container image**: A genuine caris image with real platform entries that must be pulled, scanned, and promoted.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of notation signature referrer pushes to `ukhoacr.azurecr.io` result in a non-failed pipeline run (0 failures caused by signature artifacts).
- **SC-002**: 0 false "Container Scan Failed" Teams alerts are raised for signature/referrer pushes.
- **SC-003**: 100% of genuine multi-arch caris images continue to be detected, scanned, and promoted with no change in outcome versus before the fix.
- **SC-004**: Genuine images with known vulnerabilities still raise the expected scan-failure alert (no reduction in true-positive alerting).

## Assumptions

- The fix lives entirely in `UKHO/caris-quarantine-pipeline`; `UKHO/caris-infra` (ACR/webhook IaC) and `UKHO/public-container-registry` (notation signing) require no change.
- The ACR push webhook filter on `target.mediaType` cannot distinguish a referrer index from a real image, so classification must happen inside the pipeline after manifest inspection.
- Manifest/artifact inspection tooling available on the Tiberius Linux agents can read `artifactType`, `subject`, annotations, and platform entries from the pushed index.
- Notation signature referrers use the `sha256-*` fallback tag convention.
