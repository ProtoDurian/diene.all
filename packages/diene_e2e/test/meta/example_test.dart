import 'package:flutter_test/flutter_test.dart';

import '../../example/diene_e2e_example.dart' as example;

void main() {
  test('the shipped example runs to completion', () async {
    // Arrange
    final Future<void> Function() run = example.main;

    // Act
    final Future<void> done = run();

    // Assert
    await expectLater(done, completes);
  });
}
