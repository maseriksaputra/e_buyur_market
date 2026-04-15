// lib/app/common/ui/category_theme.dart
import 'package:flutter/material.dart';
import '../models/product_category.dart';

/// Visual theme mapping for each [ProductCategory].
class CategoryTheme {
  final IconData icon;
  final Color fg; // foreground (text/icon)
  final Color bg; // background
  const CategoryTheme({required this.icon, required this.fg, required this.bg});
}

const _neutral = CategoryTheme(
  icon: Icons.category,
  fg: Color(0xFF37474F),
  bg: Color(0xFFECEFF1),
);
const _buah = CategoryTheme(
  icon: Icons.local_florist, // fruity vibe
  fg: Color(0xFFEF6C00), // deep orange
  bg: Color(0xFFFFF3E0), // light orange bg
);
const _sayur = CategoryTheme(
  icon: Icons.eco,
  fg: Color(0xFF2E7D32), // green 800
  bg: Color(0xFFE8F5E9), // green 50
);

CategoryTheme themeFor(ProductCategory? c) {
  switch (c) {
    case ProductCategory.buah:
      return _buah;
    case ProductCategory.sayur:
      return _sayur;
    default:
      return _neutral;
  }
}

/// 🔌 Extension untuk akses cepat properti visual dari enum
extension ProductCategoryTheme on ProductCategory {
  Color get color {
    switch (this) {
      case ProductCategory.buah:
        return const Color(0xFFEF6C00);
      case ProductCategory.sayur:
        return const Color(0xFF2E7D32);
    }
  }

  IconData get icon {
    switch (this) {
      case ProductCategory.buah:
        return Icons.local_florist;
      case ProductCategory.sayur:
        return Icons.eco;
    }
  }

  Color get bg {
    switch (this) {
      case ProductCategory.buah:
        return const Color(0xFFFFF3E0);
      case ProductCategory.sayur:
        return const Color(0xFFE8F5E9);
    }
  }
}

/// Small, reusable chip to display product category consistently.
class CategoryChip extends StatelessWidget {
  final ProductCategory? category;
  final bool dense; // smaller padding/label
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const CategoryChip({
    super.key,
    required this.category,
    this.dense = true,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final th = themeFor(category);
    final label = category?.label ?? 'Kategori';

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(th.icon, size: dense ? 14 : 18, color: th.fg),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: th.fg,
            fontSize: dense ? 12 : 14,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ],
    );

    final chip = Container(
      padding: padding ??
          EdgeInsets.symmetric(
              horizontal: dense ? 8 : 12, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: th.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: th.fg.withOpacity(0.2)),
      ),
      child: child,
    );

    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: chip,
    );
  }
}

/// Category selector chips (Semua/Buah/Sayur) for buyer pages.
class CategoryFilterBar extends StatelessWidget {
  final ProductCategory? selected; // null = Semua
  final ValueChanged<ProductCategory?> onChanged;
  final bool includeAll;

  const CategoryFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
    this.includeAll = true,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (includeAll) {
      final th = _neutral;
      items.add(_buildChoice(
        context,
        label: 'Semua',
        icon: th.icon,
        selected: selected == null,
        fg: th.fg,
        bg: th.bg,
        onTap: () => onChanged(null),
      ));
    }

    for (final c in ProductCategory.values) {
      final th = themeFor(c);
      items.add(_buildChoice(
        context,
        label: c.label,
        icon: th.icon,
        selected: selected == c,
        fg: th.fg,
        bg: th.bg,
        onTap: () => onChanged(c),
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          items[i],
        ]
      ]),
    );
  }

  Widget _buildChoice(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required Color fg,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      backgroundColor: bg,
      selectedColor: fg.withOpacity(0.12),
      checkmarkColor: fg,
      labelStyle: TextStyle(color: fg),
      shape: StadiumBorder(side: BorderSide(color: fg.withOpacity(0.25))),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
    );
  }
}
