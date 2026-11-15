import tempfile
from pathlib import Path
import unittest
from configure_example_android import configure, template_versions
from check_flutter_compatibility import configure_jdk_override


class ToolchainTests(unittest.TestCase):
    def android(self, root):
        root.mkdir()
        (root/'gradle/wrapper').mkdir(parents=True)
        (root/'app').mkdir()
        (root/'app/build.gradle.kts').write_text('plugins {\n    id("com.android.application")\n    id("org.jetbrains.kotlin.android")\n}\n')
        (root/'settings.gradle.kts').write_text('id("com.android.application") version "8.11.1" apply false\nid("org.jetbrains.kotlin.android") version "2.2.20" apply false\n')
        (root/'gradle/wrapper/gradle-wrapper.properties').write_text('distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14-all.zip\n')
        (root/'gradle.properties').write_text('android.useAndroidX=true\norg.gradle.java.home=/fixture/jdk\n')
        return root

    def test_agp9_flags_are_added_once_and_agp8_removes_them(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.android(Path(directory)/'android')
            newer = dict(gradle='9.5.0', agp='9.3.1', kotlin='2.4.20')
            configure(root, newer)
            configure(root, newer)
            text = (root/'gradle.properties').read_text()
            self.assertEqual(text.count('android.newDsl=false'), 1)
            self.assertEqual(text.count('android.builtInKotlin=false'), 1)
            self.assertNotIn('org.jetbrains.kotlin.android', (root/'app/build.gradle.kts').read_text())
            self.assertIn('org.gradle.java.home=/fixture/jdk', text)
            configure(root, dict(gradle='8.14', agp='8.11.1', kotlin='2.2.20'))
            self.assertNotIn('android.builtInKotlin', (root/'gradle.properties').read_text())
            self.assertEqual((root/'app/build.gradle.kts').read_text().count('org.jetbrains.kotlin.android'), 1)

    def test_unknown_wrapper_does_not_partially_mutate_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.android(Path(directory)/'android')
            original = (root/'settings.gradle.kts').read_text()
            (root/'gradle/wrapper/gradle-wrapper.properties').write_text('unknown-format')
            with self.assertRaises(ValueError):
                configure(root, dict(gradle='9.5.0', agp='9.3.1', kotlin='2.4.20'))
            self.assertEqual((root/'settings.gradle.kts').read_text(), original)

    def test_unknown_plugin_layout_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.android(Path(directory)/'android')
            (root/'settings.gradle.kts').write_text('unknown-format')
            with self.assertRaises(ValueError):
                configure(root, dict(gradle='9.5.0', agp='9.3.1', kotlin='2.4.20'))
            self.assertNotIn('builtInKotlin', (root/'gradle.properties').read_text())

    def test_explicit_jdk_override_removes_only_copied_daemon_criteria(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo/'example').mkdir()
            android = self.android(repo/'example/android')
            criteria = android/'gradle/gradle-daemon-jvm.properties'
            criteria.write_text('toolchainVersion=17\n')
            java_home = repo/'jdk21'
            (java_home/'bin').mkdir(parents=True)
            (java_home/'bin/java').touch()  # Configuration-only fixture; never executed.
            configure_jdk_override(repo, java_home)
            configure_jdk_override(repo, java_home)
            self.assertFalse(criteria.exists())
            text = (android/'gradle.properties').read_text()
            self.assertEqual(text.count('org.gradle.java.home='), 1)
            self.assertIn('org.gradle.java.home=' + str(java_home.resolve()), text)
            self.assertIn('android.useAndroidX=true', text)

    def test_invalid_jdk_keeps_project_criteria_and_properties(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo/'example').mkdir()
            android = self.android(repo/'example/android')
            criteria = android/'gradle/gradle-daemon-jvm.properties'
            criteria.write_text('toolchainVersion=17\n')
            before = (android/'gradle.properties').read_text()
            with self.assertRaises(ValueError):
                configure_jdk_override(repo, repo/'missing-jdk')
            self.assertEqual(criteria.read_text(), 'toolchainVersion=17\n')
            self.assertEqual((android/'gradle.properties').read_text(), before)

    def test_template_version_parser_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'bin').mkdir()
            source = root/'packages/flutter_tools/lib/src/android/gradle_utils.dart'
            source.parent.mkdir(parents=True)
            source.write_text("const templateDefaultGradleVersion = '8.14';\nconst templateAndroidGradlePluginVersion = '8.11.1';\nconst templateKotlinGradlePluginVersion = '2.2.20';")
            self.assertEqual(template_versions(root/'bin/flutter')['gradle'], '8.14')
            source.write_text(source.read_text().replace('8.14', 'future-format'))
            with self.assertRaises(ValueError): template_versions(root/'bin/flutter')


if __name__ == '__main__': unittest.main()
