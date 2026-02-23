import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Smoke: project structure', () {
    test('pubspec.yaml should exist and have valid name', () {
      final file = File('pubspec.yaml');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('name:'));
      expect(content, contains('nats_dart'));
    });

    test('lib/ directory should exist and contain required subdirs', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final requiredDirs = [
        'transport',
        'protocol',
        'client',
        // jetstream and kv are Phase 2/3, not Phase 1
      ];

      for (final dirName in requiredDirs) {
        final dir = Directory('${libDir.path}/$dirName');
        expect(dir.existsSync(), isTrue,
            reason: 'Required lib subdirectory $dirName missing');
      }
    });

    test('test/ directory should have tiered structure', () {
      final testDir = Directory('test');
      expect(testDir.existsSync(), isTrue);

      final requiredTiers = ['smoke', 'unit', 'integration'];
      for (final tier in requiredTiers) {
        final tierDir = Directory('${testDir.path}/$tier');
        expect(tierDir.existsSync(), isTrue,
            reason: 'Test tier $tier directory missing');
      }
    });

    test('Agent test config should exist with valid JSON', () {
      final file = File('.agent-test-config.json');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('"framework": "dart"'));
      expect(content, contains('"tiers"'));
      expect(content, contains('"smoke"'));
      expect(content, contains('"unit"'));
      expect(content, contains('"integration"'));
    });

    test('dart_test.yaml should exist and have tag configuration', () {
      final file = File('dart_test.yaml');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('tags:'));
      expect(content, contains('smoke:'));
    });

    test('Example Flutter example files should exist', () {
      final basicExample = File('example/basic.dart');
      final nativeExample = File('example/flutter_native_example.dart');
      final webExample = File('example/flutter_web_example.dart');

      expect(basicExample.existsSync(), isTrue);
      expect(nativeExample.existsSync(), isTrue);
      expect(webExample.existsSync(), isTrue);
    });
  });
}
