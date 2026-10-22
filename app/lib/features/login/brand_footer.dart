import 'package:flutter/material.dart';

import '../../app/strings.dart';

/// "Powered by Digital Target": always shown in Digital Target branding, never overridden by a business theme.
class BrandFooter extends StatelessWidget {
  const BrandFooter({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Image.asset('assets/brand/dt_mark_white.png', width: 18, height: 18, color: c),
      const SizedBox(width: 8),
      Text(Strings.of(context)['powered_by'], style: TextStyle(color: c, fontWeight: FontWeight.w600, letterSpacing: 0.4, fontSize: 13)),
    ]);
  }
}
