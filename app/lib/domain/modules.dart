import 'package:flutter/material.dart' show IconData, Icons;

/// Optional parts of the app. Selling, bills, menu, reports and settings are always on.
/// Switching a module off only hides it; its data is never deleted and comes back when switched on again.
const allModules = ['tables', 'kitchen', 'inventory', 'customers', 'expenses', 'staff', 'tokens', 'online'];

class BusinessType {
  const BusinessType(this.id, this.icon, this.modules);
  final String id;
  final IconData icon;

  /// Starting point only; the owner can change modules any time in Settings.
  final List<String> modules;
}

const businessTypes = <BusinessType>[
  BusinessType('stall', Icons.storefront_outlined, ['customers', 'expenses', 'tokens']),
  BusinessType('cafe', Icons.local_cafe_outlined, ['kitchen', 'inventory', 'customers', 'expenses']),
  BusinessType('fastfood', Icons.lunch_dining_outlined, ['kitchen', 'inventory', 'customers', 'expenses', 'staff', 'tokens', 'online']),
  BusinessType('pizza', Icons.local_pizza_outlined, ['kitchen', 'inventory', 'customers', 'expenses', 'staff', 'online']),
  BusinessType('desi', Icons.rice_bowl_outlined, ['tables', 'kitchen', 'inventory', 'customers', 'expenses', 'staff', 'tokens', 'online']),
  BusinessType('bakery', Icons.bakery_dining_outlined, ['inventory', 'customers', 'expenses', 'staff']),
  BusinessType('enterprise', Icons.apartment_outlined, allModules),
];

BusinessType businessTypeById(String? id) => businessTypes.firstWhere((b) => b.id == id, orElse: () => businessTypes.last);

/// What is actually on: the owner's choice minus anything Digital Target switched off for this account.
Set<String> effectiveModules(Set<String> local, Iterable<String> disabledByAdmin) => local.difference(disabledByAdmin.toSet());
