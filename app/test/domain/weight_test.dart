import 'package:dt_food_pos/features/pos/weight_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('grams and kilograms become the right quantity for a per-kg, per-gram, per-litre or per-ml price', () {
    expect(weightToMilli('kg', 750, big: false), 750, reason: '750 g of a per-kg item = 0.75');
    expect(weightToMilli('kg', 1.25, big: true), 1250);
    expect(weightToMilli('g', 750, big: false), 750000, reason: 'a per-gram price: 750 units');
    expect(weightToMilli('g', 1, big: true), 1000000);
    expect(weightToMilli('l', 300, big: false), 300, reason: '300 ml of a per-litre item');
    expect(weightToMilli('ml', 2, big: true), 2000000);
  });

  test('a quantity reads the way a cashier says it', () {
    expect(weightLabel('kg', 750), '750 g');
    expect(weightLabel('kg', 1000), '1 kg');
    expect(weightLabel('kg', 1250), '1.25 kg');
    expect(weightLabel('g', 750000), '750 g');
    expect(weightLabel('l', 300), '300 ml');
    expect(weightLabel('l', 1500), '1.5 l');
  });
}
