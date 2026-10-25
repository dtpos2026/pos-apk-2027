import 'dart:io';

import 'package:flutter/material.dart';

/// A person's round picture (or the first letter of the name) with a soft ring, the same everywhere: staff list, sign-in, riders, waiters, menu drawer.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.imagePath, this.radius = 22, this.icon});
  final String name;
  final String? imagePath;
  final double radius;

  /// Shown instead of the letter when there is no picture (for example a rider icon).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final has = imagePath != null && File(imagePath!).existsSync();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary.withValues(alpha: 0.35), width: 1.5)),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.primary,
        backgroundImage: has ? FileImage(File(imagePath!)) : null,
        child: has ? null : (icon != null ? Icon(icon, size: radius) : Text(name.trim().isEmpty ? '?' : name.characters.first.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
      ),
    );
  }
}
