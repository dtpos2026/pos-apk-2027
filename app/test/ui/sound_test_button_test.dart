import 'package:dt_food_pos/app/device_channel.dart';
import 'package:dt_food_pos/app/feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('digital.target/device');
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

  test('the Settings test plays even on silent and reports what the phone said', () async {
    final calls = <Map<Object?, Object?>>[];
    String answer = 'ok';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
      if (c.method == 'tone') {
        calls.add(c.arguments as Map<Object?, Object?>);
        return answer;
      }
      return null;
    });
    const out = AndroidFeedback(DeviceChannel());
    expect(await out.test('success'), 'ok');
    expect(calls.single, {'kind': 'success', 'force': true});

    await out.tone('tap'); // a normal tap is not forced: silent phones stay quiet
    expect(calls.last['force'], false);

    answer = 'volume0';
    expect(await out.test('error'), 'volume0');
  });

  test('a broken channel answers "failed" instead of throwing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async => throw PlatformException(code: 'x'));
    expect(await const AndroidFeedback(DeviceChannel()).test('tap'), 'failed');
  });
}
