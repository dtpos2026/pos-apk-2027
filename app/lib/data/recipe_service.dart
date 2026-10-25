import 'db_helper.dart';

/// One line of the Recipes list: a menu item, or one size/variant of it, with what its recipe costs.
class RecipeRow {
  const RecipeRow({required this.productId, required this.name, this.variantId, this.variantName, this.category, required this.priceMinor, required this.ingredients, required this.costMinor});
  final String productId;
  final String name;
  final String? variantId;
  final String? variantName;
  final String? category;
  final int priceMinor;
  final int ingredients;

  /// What one portion costs from the average purchase price of its ingredients.
  final int costMinor;
  bool get hasRecipe => ingredients > 0;
  String get label => variantName == null ? name : '$name · $variantName';
  int? get marginPct => !hasRecipe || priceMinor <= 0 ? null : ((priceMinor - costMinor) * 100 / priceMinor).round();
}

/// One ingredient of a recipe, in the stock item's own unit.
class RecipeIngredient {
  const RecipeIngredient({required this.stockItemId, required this.name, required this.unit, required this.qtyMilli, required this.avgCostMinor});
  final String stockItemId;
  final String name;
  final String unit;
  final int qtyMilli;
  final int avgCostMinor;
  int get costMinor => (qtyMilli * avgCostMinor / 1000).round();
}

/// Recipes: which stock items one portion of a menu item (or of one of its sizes) uses. Selling the item takes exactly these from stock.
class RecipeService {
  RecipeService(this.h);
  final DbHelper h;

  /// Every sellable menu item, one row per size when it has sizes (deals are left out: they use what is inside them).
  Future<List<RecipeRow>> rows({String search = ''}) async {
    final like = '%${search.trim().toLowerCase()}%';
    final raw = await h.q(
        'SELECT p.id AS pid, p.name AS pname, c.name AS cat, p.base_price_minor AS price, v.id AS vid, v.name AS vname, v.price_minor AS vprice '
        'FROM product p LEFT JOIN category c ON c.id = p.category_id LEFT JOIN product_variant v ON v.product_id = p.id AND v.deleted_at IS NULL '
        "WHERE p.deleted_at IS NULL AND p.kind <> 'combo' AND (lower(p.name) LIKE ? OR lower(COALESCE(v.name,'')) LIKE ?) ORDER BY lower(p.name), v.price_minor, v.name",
        [like, like]);
    final out = <RecipeRow>[];
    for (final r in raw) {
      final vid = r['vid'] as String?;
      final agg = await h.one(
          'SELECT COUNT(*) AS n, COALESCE(SUM(l.qty_milli * s.avg_cost_minor_per_unit / 1000.0), 0) AS cost FROM recipe_line l JOIN stock_item s ON s.id = l.stock_item_id WHERE l.product_id = ? AND l.variant_id IS ?',
          [r['pid'], vid]);
      out.add(RecipeRow(
        productId: r['pid'] as String,
        name: r['pname'] as String,
        variantId: vid,
        variantName: r['vname'] as String?,
        category: r['cat'] as String?,
        priceMinor: (vid == null ? r['price'] : r['vprice']) as int,
        ingredients: agg!['n'] as int,
        costMinor: (agg['cost'] as num).round(),
      ));
    }
    return out;
  }

  Future<List<RecipeIngredient>> ingredients(String productId, String? variantId) async => [
        for (final r in await h.q(
            'SELECT l.stock_item_id AS id, s.name AS name, s.unit AS unit, l.qty_milli AS qty, s.avg_cost_minor_per_unit AS cost FROM recipe_line l JOIN stock_item s ON s.id = l.stock_item_id WHERE l.product_id = ? AND l.variant_id IS ? ORDER BY l.rowid',
            [productId, variantId]))
          RecipeIngredient(stockItemId: r['id'] as String, name: r['name'] as String, unit: r['unit'] as String, qtyMilli: r['qty'] as int, avgCostMinor: r['cost'] as int)
      ];
}

/// The units a recipe may be written in for a stock item kept in [stockUnit], with how many of them make one stock unit.
/// Flour kept in kg can be written in grams; oil kept in litres in millilitres.
List<({String unit, int perStockUnit})> recipeUnits(String stockUnit) => switch (stockUnit) {
      'kg' => const [(unit: 'kg', perStockUnit: 1), (unit: 'g', perStockUnit: 1000)],
      'l' => const [(unit: 'l', perStockUnit: 1), (unit: 'ml', perStockUnit: 1000)],
      _ => [(unit: stockUnit, perStockUnit: 1)],
    };
