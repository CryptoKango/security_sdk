import 'package:security_core/security_core.dart';
import 'package:test/test.dart';

void main() {
  final a = 'a' * 64;
  final b = 'b' * 64;
  AppIntegrityPolicy android(Iterable<Iterable<String>> sets) =>
      AppIntegrityPolicy(
        expectedApplicationId: 'example.app',
        androidSignerSha256Sets: sets,
      );
  test(
    'release baseline makes nested copies, normalizes hashes and redacts',
    () {
      final inner = [a.toUpperCase()];
      final outer = [inner];
      final files = {'assets/asset.bin': b.toUpperCase()};
      final policy = AppIntegrityPolicy(
        expectedApplicationId: 'private.bundle',
        androidSignerSha256Sets: outer,
        iosBundleFileSha256: files,
      );
      inner.add(b);
      outer.clear();
      files.clear();
      expect(policy.androidSignerSha256Sets, [
        [a],
      ]);
      expect(policy.iosBundleFileSha256, {'assets/asset.bin': b});
      expect(
        () => policy.androidSignerSha256Sets.single.add(b),
        throwsUnsupportedError,
      );
      expect(() => policy.iosBundleFileSha256.clear(), throwsUnsupportedError);
      expect(policy.toString(), 'AppIntegrityPolicy(redacted)');
    },
  );
  test(
    'missing, malformed, duplicated and oversized signer baselines fail',
    () {
      for (final sets in <List<List<String>>>[
        [],
        [[]],
        [
          ['x' * 64],
        ],
        [
          ['a' * 63],
        ],
        [
          ['$a\n'],
        ],
        [
          [a, a.toUpperCase()],
        ],
        [
          [a, b],
          [b, a],
        ],
        [List.generate(9, (i) => i.toString() * 64)],
        List.generate(9, (i) => [i.toString() * 64]),
      ]) {
        expect(() => android(sets), throwsA(isA<SecurityFailure>()));
      }
      expect(
        android([
          [a],
          [b],
        ]).androidSignerSha256Sets.length,
        2,
      );
    },
  );
  test('unsafe file paths and invalid resource hashes are rejected', () {
    for (final path in [
      '',
      '/absolute',
      '../escape',
      'a/../b',
      './a',
      'a//b',
      'a/',
      'a\\b',
      'a:b',
      'a\u0000b',
      'a\nb',
      'x' * 513,
    ]) {
      expect(
        () => AppIntegrityPolicy(
          expectedApplicationId: 'example.app',
          iosBundleFileSha256: {path: a},
        ),
        throwsA(isA<SecurityFailure>()),
      );
    }
    expect(
      () => AppIntegrityPolicy(
        expectedApplicationId: 'example.app',
        iosBundleFileSha256: {'a': 'not-a-hash'},
      ),
      throwsA(isA<SecurityFailure>()),
    );
    expect(
      AppIntegrityPolicy(
        expectedApplicationId: 'example.app',
        iosBundleFileSha256: {'Assets/中文 file.bin': a},
      ).iosBundleFileSha256.length,
      1,
    );
  });
  test('application identity and resource count have explicit bounds', () {
    for (final id in ['', 'a/b', 'a\n', 'a\nb', 'a' * 256]) {
      expect(
        () => AppIntegrityPolicy(
          expectedApplicationId: id,
          androidSignerSha256Sets: [
            [a],
          ],
        ),
        throwsA(isA<SecurityFailure>()),
      );
    }
    expect(
      () => AppIntegrityPolicy(
        expectedApplicationId: 'example.app',
        iosBundleFileSha256: {for (var i = 0; i < 33; i++) '$i.bin': a},
      ),
      throwsA(isA<SecurityFailure>()),
    );
  });
}
