// lib/app/common/ui/category_filter_modern.dart
import 'package:flutter/material.dart';
import '../models/product_category.dart';
import 'category_theme.dart' show ProductCategoryTheme; // for .color/.icon

/// A modern, high-contrast category filter bar (Semua / Buah / Sayur)
/// with clear selected/unselected states and accessible contrast.
class ModernCategoryBar extends StatelessWidget {
  final ProductCategory? selected; // null = Semua
  final ValueChanged<ProductCategory?> onChanged;
  final EdgeInsetsGeometry padding;
  final double spacing;

  const ModernCategoryBar({
    super.key,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.spacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _CategoryPill.nullable(
        label: 'Semua',
        icon: Icons.verified_rounded,
        selected: selected == null,
        onTap: () => onChanged(null),
        // neutral/brand style
        normalFg: const Color(0xFF1F2937), // gray-800
        normalBg: const Color(0xFFF3F4F6), // gray-100
        normalBorder: const Color(0xFFD1D5DB), // gray-300
        selectedFg: Colors.white,
        selectedBg: const Color(0xFF059669), // emerald-600
      ),
    ];

    for (final c in ProductCategory.values) {
      final normalFg = switch (c) {
        ProductCategory.buah => const Color(0xFFB45309), // orange-700
        ProductCategory.sayur => const Color(0xFF166534), // green-800
      };
      final normalBg = switch (c) {
        ProductCategory.buah => const Color(0xFFFFF7ED), // orange-50
        ProductCategory.sayur => const Color(0xFFECFDF5), // emerald-50
      };
      final normalBorder = switch (c) {
        ProductCategory.buah =>
          const Color(0xFFF59E0B).withOpacity(.35), // orange-500 35%
        ProductCategory.sayur =>
          const Color(0xFF10B981).withOpacity(.35), // emerald-500 35%
      };
      final selectedBg = switch (c) {
        ProductCategory.buah => const Color(0xFFF59E0B), // orange-500
        ProductCategory.sayur => const Color(0xFF10B981), // emerald-500
      };

      items.add(_CategoryPill(
        label: c.label,
        icon: c.icon,
        selected: selected == c,
        onTap: () => onChanged(c),
        normalFg: normalFg,
        normalBg: normalBg,
        normalBorder: normalBorder,
        selectedFg: Colors.white,
        selectedBg: selectedBg,
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            items[i],
          ],
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color normalFg;
  final Color normalBg;
  final Color normalBorder;
  final Color selectedFg;
  final Color selectedBg;

  const _CategoryPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.normalFg,
    required this.normalBg,
    required this.normalBorder,
    required this.selectedFg,
    required this.selectedBg,
  });

  factory _CategoryPill.nullable({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required Color normalFg,
    required Color normalBg,
    required Color normalBorder,
    required Color selectedFg,
    required Color selectedBg,
  }) =>
      _CategoryPill(
        label: label,
        icon: icon,
        selected: selected,
        onTap: onTap,
        normalFg: normalFg,
        normalBg: normalBg,
        normalBorder: normalBorder,
        selectedFg: selectedFg,
        selectedBg: selectedBg,
      );

  @override
  Widget build(BuildContext context) {
    final bg = selected ? selectedBg : normalBg;
    final fg = selected ? selectedFg : normalFg;
    final border = selected ? selectedBg : normalBorder;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: selectedBg.withOpacity(.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
