import 'models.dart';

/// Host-supplied release baseline. Never derive it from the installation under
/// inspection. This is a local comparison, not platform attestation.
final class AppIntegrityPolicy {
  AppIntegrityPolicy({
    required this.expectedApplicationId,
    Iterable<Iterable<String>> androidSignerSha256Sets = const [],
    Map<String, String> iosBundleFileSha256 = const {},
  }) : androidSignerSha256Sets = List.unmodifiable(
         androidSignerSha256Sets.map(
           (set) =>
               List<String>.unmodifiable(set.map((hash) => hash.toLowerCase())),
         ),
       ),
       iosBundleFileSha256 = Map.unmodifiable(
         iosBundleFileSha256.map(
           (path, hash) => MapEntry(path, hash.toLowerCase()),
         ),
       ) {
    if (expectedApplicationId.isEmpty ||
        expectedApplicationId.length > 255 ||
        RegExp(r'^[A-Za-z0-9_.-]+$').stringMatch(expectedApplicationId) !=
            expectedApplicationId ||
        (this.androidSignerSha256Sets.isEmpty &&
            this.iosBundleFileSha256.isEmpty) ||
        this.androidSignerSha256Sets.length > 8 ||
        this.iosBundleFileSha256.length > 32) {
      _invalid();
    }
    final sets = <String>{};
    for (final set in this.androidSignerSha256Sets) {
      if (set.isEmpty ||
          set.length > 8 ||
          set.any((s) => !_validHash(s)) ||
          set.toSet().length != set.length) {
        _invalid();
      }
      final sorted = set.toList()..sort();
      if (!sets.add(sorted.join(','))) _invalid();
    }
    for (final entry in this.iosBundleFileSha256.entries) {
      if (!isValidBundlePath(entry.key) || !_validHash(entry.value)) {
        _invalid();
      }
    }
  }

  final String expectedApplicationId;

  /// Exact current signer sets, not a flat OR allowlist. Rotations require an
  /// explicit new allowed set. An unexpected additional signer is a mismatch.
  final List<List<String>> androidSignerSha256Sets;

  /// Paths relative to the main iOS app bundle. Use stable shipped resources;
  /// not encrypted executables or files rewritten by signing/app thinning.
  final Map<String, String> iosBundleFileSha256;
  static final _hash = RegExp(r'^[0-9a-f]{64}$');
  static bool _validHash(String hash) =>
      hash.length == 64 && _hash.hasMatch(hash);

  static bool isValidBundlePath(String path) =>
      path.isNotEmpty &&
      path.length <= 512 &&
      !path.contains(RegExp(r'[\\:\x00-\x1f\x7f]')) &&
      path
          .split('/')
          .every((part) => part.isNotEmpty && part != '.' && part != '..');

  static Never _invalid() =>
      throw const SecurityFailure(SecurityErrorCode.invalidConfiguration);
  @override
  String toString() => 'AppIntegrityPolicy(redacted)';
}
