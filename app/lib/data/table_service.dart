import 'db_helper.dart';
import 'pos_service.dart' show PosException;

class AreaRow {
  const AreaRow(this.id, this.name);
  final String id;
  final String name;
}

class TableInfo {
  const TableInfo({required this.id, required this.areaId, required this.label, required this.seats, required this.status, this.waiterName, this.orderId, this.orderTotalMinor});
  final String id;
  final String areaId;
  final String label;
  final int seats;

  /// free | occupied | reserved | cleaning
  final String status;
  final String? waiterName;

  /// The unsettled order sitting on this table, if any.
  final String? orderId;
  final int? orderTotalMinor;
}

/// Floors, tables and who is serving them.
class TableService {
  TableService(this.h);
  final DbHelper h;

  Future<String> saveArea({String? id, required String name}) async {
    if (name.trim().isEmpty) throw PosException('name_required', 'Name is required');
    final aid = id ?? h.id;
    if (id == null) {
      await h.exec('INSERT INTO area(id, name, sort, updated_at) VALUES (?,?,(SELECT COALESCE(MAX(sort),0)+1 FROM area),?)', [aid, name.trim(), h.ts]);
    } else {
      await h.exec('UPDATE area SET name=?, updated_at=?, version=version+1 WHERE id=?', [name.trim(), h.ts, id]);
    }
    return aid;
  }

  Future<List<AreaRow>> areas() async => [for (final r in await h.q('SELECT id, name FROM area WHERE deleted_at IS NULL ORDER BY sort, name')) AreaRow(r['id'] as String, r['name'] as String)];

  Future<String> saveTable({String? id, required String areaId, required String label, int seats = 4}) async {
    if (label.trim().isEmpty) throw PosException('name_required', 'Label is required');
    if (seats < 1) throw PosException('bad_amount', 'Seats must be at least 1');
    final dup = await h.one('SELECT id FROM dining_table WHERE area_id = ? AND lower(label) = lower(?) AND deleted_at IS NULL AND id <> ?', [areaId, label.trim(), id ?? '']);
    if (dup != null) throw PosException('duplicate', 'This area already has a table called ${label.trim()}');
    final tid = id ?? h.id;
    if (id == null) {
      await h.exec('INSERT INTO dining_table(id, area_id, label, seats, updated_at) VALUES (?,?,?,?,?)', [tid, areaId, label.trim(), seats, h.ts]);
    } else {
      await h.exec('UPDATE dining_table SET area_id=?, label=?, seats=?, updated_at=?, version=version+1 WHERE id=?', [areaId, label.trim(), seats, h.ts, id]);
    }
    return tid;
  }

  Future<void> deleteTable(String id) async {
    if ((await h.one("SELECT id FROM \"order\" WHERE table_id = ? AND status IN ('draft','held','new','preparing','ready','served')", [id])) != null) {
      throw PosException('in_use', 'This table has an open order');
    }
    await h.exec('UPDATE dining_table SET deleted_at=?, updated_at=?, version=version+1 WHERE id=?', [h.ts, h.ts, id]);
  }

  Future<List<TableInfo>> tables({String? areaId}) async {
    final rows = await h.q(
        'SELECT t.id, t.area_id, t.label, t.seats, t.status, COALESCE(m.name, s.name) AS waiter, '
        '(SELECT o.id FROM "order" o WHERE o.table_id = t.id AND o.status IN (\'draft\',\'held\',\'new\',\'preparing\',\'ready\',\'served\') ORDER BY o.updated_at DESC LIMIT 1) AS order_id, '
        '(SELECT o.total_minor FROM "order" o WHERE o.table_id = t.id AND o.status IN (\'draft\',\'held\',\'new\',\'preparing\',\'ready\',\'served\') ORDER BY o.updated_at DESC LIMIT 1) AS order_total '
        'FROM dining_table t LEFT JOIN staff s ON s.id = t.waiter_id LEFT JOIN team_member m ON m.id = t.waiter_member_id WHERE t.deleted_at IS NULL ${areaId == null ? '' : 'AND t.area_id = ?'} ORDER BY t.label',
        areaId == null ? [] : [areaId]);
    return [
      for (final r in rows)
        TableInfo(id: r['id'] as String, areaId: r['area_id'] as String, label: r['label'] as String, seats: r['seats'] as int, status: r['status'] as String, waiterName: r['waiter'] as String?, orderId: r['order_id'] as String?, orderTotalMinor: r['order_total'] as int?)
    ];
  }

  Future<void> setStatus(String tableId, String status) async {
    if (!const {'free', 'reserved', 'cleaning'}.contains(status)) throw PosException('bad_status', 'Status can be set to free, reserved or cleaning');
    final open = await h.one("SELECT id FROM \"order\" WHERE table_id = ? AND status IN ('draft','held','new','preparing','ready','served')", [tableId]);
    if (open != null) throw PosException('in_use', 'The table has an open order');
    await h.exec('UPDATE dining_table SET status=?, updated_at=?, version=version+1 WHERE id=?', [status, h.ts, tableId]);
  }

  Future<void> assignWaiter(String tableId, String? waiterId) => h.exec('UPDATE dining_table SET waiter_id=?, updated_at=?, version=version+1 WHERE id=?', [waiterId, h.ts, tableId]);

  /// Moves an unsettled order to another free table.
  Future<void> transfer({required String orderId, required String toTableId, required String staffId}) => h.db.transaction(() async {
        final o = await h.one("SELECT table_id, status FROM \"order\" WHERE id = ?", [orderId]);
        if (o == null) throw PosException('not_found', 'Order not found');
        if (!const {'draft', 'held', 'new', 'preparing', 'ready', 'served'}.contains(o['status'])) throw PosException('not_editable', 'The order is already settled');
        final target = await h.one('SELECT status FROM dining_table WHERE id = ? AND deleted_at IS NULL', [toTableId]);
        if (target == null) throw PosException('not_found', 'Table not found');
        if (target['status'] != 'free') throw PosException('table_busy', 'The target table is not free');
        final from = o['table_id'] as String?;
        await h.exec('UPDATE "order" SET table_id=?, updated_at=?, version=version+1 WHERE id=?', [toTableId, h.ts, orderId]);
        await h.exec("UPDATE dining_table SET status='occupied', updated_at=?, version=version+1 WHERE id=?", [h.ts, toTableId]);
        if (from != null) await h.exec("UPDATE dining_table SET status='free', updated_at=?, version=version+1 WHERE id=?", [h.ts, from]);
        await h.audit('table.transfer', staffId: staffId, entity: 'order', entityId: orderId, before: {'table': from}, after: {'table': toTableId});
      });
}
