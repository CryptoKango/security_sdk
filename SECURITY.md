# Security boundaries

This development SDK is not an authorization service or tamper-resistant proof.
`notDetected` describes only the implemented checks. Accessibility, work profiles,
VPN, simulators and test tools all have legitimate uses; observations alone must
not become an abuse verdict. Some checks are deliberately heuristic and can be
spoofed. See docs/detection_coverage.md for exact limits and unsupported cases.

Scanning makes no network requests. The SDK does not collect coordinates,
installed-app identities, proof payloads or device IDs. It does not automatically
request permissions. Closed reason codes replace raw native errors; no evidence,
provider key or personal identifier should be logged by a host. Host inputs to
location/time assessment are assertions, not authenticated server-side proofs.

Native screenshot listeners begin only on explicit start, are scoped to an SDK
owner, and are removed on stop/disposal/engine teardown. Background or view
lifecycle interruptions invalidate the observation window. Cancellation suppresses
result delivery, not necessarily native work. Screenshot-start deadline failures
attempt cleanup; hosts must await stop/dispose and handle failures. No general
background event monitor or third-party fingerprint provider is implemented.

A private vulnerability reporting contact and response process must be configured
before public release. Do not put real credentials or personal data into issues.

Runtime detectors are bounded local heuristics. Do not learn trust baselines from
the installation being inspected. Android signature metadata and iOS selected
resource hashes are not remote attestation. iOS Release process-trace checks are
explicitly opt-in and depend on an unstable process-info ABI; failures remain
unknown/error. Response size and PID guards are not a future compatibility proof. Hook/root may be hidden; OS and local APIs can be tampered with.
Bundle file reads reject path traversal, symlinks and non-regular files, use size
limits, and return no file contents or observed hashes.
