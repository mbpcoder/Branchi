import 'package:branchi/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('compares major.minor.patch numerically', () {
      expect(UpdateService.isNewer('0.8.0', '0.7.0'), isTrue);
      expect(UpdateService.isNewer('0.10.0', '0.9.9'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '0.99.99'), isTrue);
      expect(UpdateService.isNewer('0.7.0', '0.7.0'), isFalse);
      expect(UpdateService.isNewer('0.6.9', '0.7.0'), isFalse);
    });

    test('ignores a leading v, suffixes and missing parts', () {
      expect(UpdateService.isNewer('v0.8.0', '0.7.0'), isTrue);
      expect(UpdateService.isNewer('0.8', '0.7.9'), isTrue);
      expect(UpdateService.isNewer('0.7.0+5', '0.7.0'), isFalse);
      expect(UpdateService.isNewer('0.7.1-rc1', '0.7.0'), isTrue);
    });
  });
}
