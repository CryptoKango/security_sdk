# security_core

Pure Dart contracts, immutable snapshots, closed finding reasons, cancellation,
redacted failures and host-input signal evaluation. No Flutter or runtime package
dependency, network, storage, provider SDK or business authorization policy.

`TrustedTimeReference` compares local wall time against a host-authenticated time
anchor advanced by monotonic elapsed time. `LocationRiskSample` evaluates the mock
source flag from an already-authorized business location flow, with explicit
permission/authorization and sample-age constraints. Neither verifies a host's
assertions or acquires its inputs. Unknown, absent and stale inputs never become
clean results. `testing.dart` exposes an explicit fake, not a runtime fallback.

Development package; publishing remains disabled pending release review.

Minimum Dart 3.10.9 (<4.0.0); no Flutter runtime requirement.

`DeviceSecurityReport.toJson()` serializes the complete report using public schema
version 1. All nested result models also support `toJson()` and `jsonEncode()`.
See [JSON_FORMAT.md](JSON_FORMAT.md) for the shared Android/iOS wire contract.
Serialization does not collect, log, persist or upload information.
