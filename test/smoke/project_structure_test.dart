import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

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
        'src/transport',
        'src/protocol',
        'src/client',
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

    test('.agent-test-config.json should exist with valid JSON', () {
      final file = File('.agent-test-config.json');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('"framework"'));
      expect(content, contains('"tiers"'));
      expect(content, contains('"smoke"'));
      expect(content, contains('"unit"'));
      expect(content, contains('"integration"'));
    });

    test('dart_test.yaml should exist and have tag configuration', () {
      final dartTestFile = File('dart_test.yaml');
      expect(dartTestFile.existsSync(), isTrue);

      final content = dartTestFile.readAsStringSync();
      expect(content, contains('tags:'));
      expect(content, contains('smoke:'));
      expect(content, contains('unit:'));
      expect(content, contains('integration:'));
      expect(content, contains('e2e:'));
      expect(content, contains('slow:'));
      expect(content, contains('presubmit:'));
    });
  });
}
