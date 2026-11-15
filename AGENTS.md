# Repository rules

This is an independent public-package development repository.

- Keep security_core pure Dart; no Flutter, HTTP, storage or host-project imports.
- security_flutter depends only on Flutter and public core contracts. Supplier
  SDKs belong in separate opt-in packages, never in the core dependency tree.
- No automatic collection, global user state, backend URL or business verdict.
- Unsupported/error/cancelled/timeout must not become notDetected or success.
- Never log evidence material, tokens, personal identifiers or raw platform errors.
- Preserve ownership and disposal of instance/engine resources.
- Test meaningful lifecycle, parsing, protocol and error behavior.
- Use `sh tool/check.sh` for local validation. Native builds and real-device tests
  are additional checks; do not claim they ran when only Dart tests ran.
- Do not publish until real package names, publisher, license, metadata and release
  artifact review are complete. Keep public README free of host-project details.
