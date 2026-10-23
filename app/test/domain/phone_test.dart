import 'package:dt_food_pos/domain/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pakistani and UAE numbers become WhatsApp digits', () {
    expect(internationalPhone('0300-1234567', countryCode: '92'), '923001234567');
    expect(internationalPhone('+92 300 1234567', countryCode: '92'), '923001234567');
    expect(internationalPhone('0092 300 1234567', countryCode: '92'), '923001234567');
    expect(internationalPhone('3001234567', countryCode: '92'), '923001234567');
    expect(internationalPhone('050 123 4567', countryCode: '971'), '971501234567');
    expect(internationalPhone('12', countryCode: '92'), isNull);
    expect(callingCodeFor('AED'), '971');
    expect(callingCodeFor('PKR'), '92');
  });
}
