import 'package:flutter/material.dart';

class SuitabilityBadge extends StatelessWidget {
  final int percent;
  final bool dense;
  const SuitabilityBadge({super.key, required this.percent, this.dense=false});

  @override
  Widget build(BuildContext context) {
    final label = percent < 60
        ? 'Tidak Layak'
        : (percent < 75 ? 'Layak' : (percent < 88 ? 'Cukup Layak' : 'Sangat Layak'));

    Color bg;
    if (percent < 60)      bg = Colors.red.shade100;
    else if (percent < 75) bg = Colors.orange.shade100;
    else if (percent < 88) bg = Colors.amber.shade100;
    else                   bg = Colors.green.shade100;

    Color fg;
    if (percent < 60)      fg = Colors.red.shade800;
    else if (percent < 75) fg = Colors.orange.shade800;
    else if (percent < 88) fg = Colors.amber.shade900;
    else                   fg = Colors.green.shade800;

    final pad = dense ? const EdgeInsets.symmetric(horizontal:8, vertical:2)
                      : const EdgeInsets.symmetric(horizontal:12, vertical:6);

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label • $percent%', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}
