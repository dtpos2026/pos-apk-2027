import 'dart:io';

import 'package:flutter/material.dart';

/// A sensible icon for a category or item name when there is no picture (English and Urdu words).
IconData foodIconFor(String name) {
  final n = name.toLowerCase();
  bool has(List<String> w) => w.any(n.contains);
  if (has(['burger', 'برگر'])) return Icons.lunch_dining;
  if (has(['pizza', 'پیزا'])) return Icons.local_pizza;
  if (has(['drink', 'cola', 'juice', 'shake', 'beverage', 'water', 'soda', 'مشروب', 'جوس'])) return Icons.local_drink;
  if (has(['tea', 'chai', 'coffee', 'چائے', 'کافی'])) return Icons.coffee;
  if (has(['fries', 'side', 'snack'])) return Icons.fastfood;
  if (has(['biryani', 'rice', 'pulao', 'desi', 'karahi', 'curry', 'handi', 'بریانی', 'کڑاہی', 'دیسی'])) return Icons.rice_bowl;
  if (has(['bbq', 'grill', 'tikka', 'kabab', 'kebab', 'chicken', 'تکہ', 'کباب'])) return Icons.outdoor_grill;
  if (has(['roti', 'naan', 'bread', 'paratha', 'روٹی', 'نان'])) return Icons.bakery_dining;
  if (has(['dessert', 'sweet', 'ice', 'cake', 'kheer', 'میٹھا'])) return Icons.icecream;
  if (has(['soup', 'سوپ'])) return Icons.soup_kitchen;
  if (has(['deal', 'combo', 'ڈیل'])) return Icons.local_offer;
  return Icons.restaurant;
}

/// The item/category picture from the phone, or a tinted icon placeholder. Never throws for a missing file.
class MenuImage extends StatelessWidget {
  const MenuImage({super.key, required this.path, required this.name, this.radius = 12, this.iconSize = 34});
  final String? path;
  final String name;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.primary.withValues(alpha: 0.07),
      alignment: Alignment.center,
      child: Icon(foodIconFor(name), size: iconSize, color: scheme.primary),
    );
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: p == null
          ? placeholder
          : Image.file(File(p), fit: BoxFit.cover, cacheWidth: 480, errorBuilder: (_, _, _) => placeholder, gaplessPlayback: true),
    );
  }
}
