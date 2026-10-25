import 'package:dt_food_pos/cloud/cloud_gateway.dart';
import 'package:dt_food_pos/features/cloud/background_notices.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotice n(String id, int ms) => AppNotice(id: id, title: id, body: '', kind: 'info', at: DateTime.fromMillisecondsSinceEpoch(ms));

void main() {
  test('closed-app check: first look is only a baseline, later only newer notices, oldest first', () {
    final all = [n('c', 300), n('b', 200), n('a', 100)];
    expect(freshNotices(all, null), isEmpty);
    expect(freshNotices(all, 200).map((x) => x.id), ['c']);
    expect(freshNotices(all, 50).map((x) => x.id), ['a', 'b', 'c']);
    expect(freshNotices(all, 300), isEmpty);
  });

  test('marker survives save and load; garbage means off', () {
    final m = NoticeMarker.decode(const NoticeMarker(enabled: true, pushed: 42).encode());
    expect(m.enabled, isTrue);
    expect(m.pushed, 42);
    expect(NoticeMarker.decode('nope').enabled, isFalse);
    expect(NoticeMarker.decode(null).pushed, isNull);
  });

  test('without the Android plugins the helpers never throw', () async {
    await BackgroundNotices.sync(enabled: true);
    await BackgroundNotices.markPushed(5);
  });
}
