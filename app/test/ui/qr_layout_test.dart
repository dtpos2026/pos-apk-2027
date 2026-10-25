import 'package:dt_food_pos/features/menu/share/menu_png.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR poster: cards never touch each other, stay on the poster and start below the title', () {
    for (final n in [1, 2, 3]) {
      final l = qrCardLayout(n);
      final total = n * l.size + (n - 1) * l.gap;
      final left = (1080 - total) / 2 - 24;
      expect(left, greaterThanOrEqualTo(20), reason: '$n codes fit the width');
      if (n > 1) expect(l.gap - 48, greaterThanOrEqualTo(16), reason: 'clear space between the cards');
      expect(l.top - 24, greaterThanOrEqualTo(388 + 70), reason: 'below "Order on WhatsApp"');
      expect(l.top + l.size + 160, lessThan(1294), reason: 'room for the number and the footer');
    }
  });
}
