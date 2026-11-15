# 0.1.0-dev.1

- Initial development contracts and bootstrap. Not published.

- Added local environment signal contracts, guarded time/location inputs, and explicit screenshot observation. See repository detection matrix for platform-specific coverage.

- Added explicit release integrity baselines and local runtime detection. Platform
  coverage and iOS Release debugger limitations are documented in runtime_security.md.

- Added per-request iOS Release process-trace opt-in and capability prerequisites,
  with response-size/PID validation and explicit unknown/error handling.

- Added closed reasons for root mount / loaded-image artifacts, known memfd and
  injection origins, and corroborated container identity; native rules are local-v2.
  Root/Hook/container coverage and false-positive boundaries are documented.

- Native local-v3: add bounded iOS main-executable Mach-O/container identity
  signals, preserve unknown executable formats, and gate Android profile APIs
  by public availability. Unresolved OEM/private profiles remain unsupported;
  new reason codes are validated at the bridge. No supplier fingerprinting.

Native local-v4 tightens active tunnel matching and invalid location metadata
handling. Low-OS framework regressions and an iOS 13 availability check are now
provided; see `docs/compatibility_review.md` in the repository. Unknown location
sources stay unknown. No third-party fingerprinting was added.

- Add closed `cloneProfile` reason for an OS-reported clone profile, with no
  maliciousness or concurrent-instance implication. Upgrade core and the Flutter
  plugin together; unknown reasons continue to fail validation.
