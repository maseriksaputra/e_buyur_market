// lib/app/common/widgets/warning_stripe.dart
import 'package:flutter/material.dart';

class WarningStripe extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final Color stripeColor;
  final double height;

  const WarningStripe({
    Key? key,
    required this.text,
    this.backgroundColor = Colors.black87,
    this.stripeColor = Colors.yellow,
    this.height = 24,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: StripePainter(
          backgroundColor: backgroundColor,
          stripeColor: stripeColor,
        ),
        child: Center(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontSize: height * 0.4,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.5),
                  offset: const Offset(1, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StripePainter extends CustomPainter {
  final Color backgroundColor;
  final Color stripeColor;

  StripePainter({
    required this.backgroundColor,
    required this.stripeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // Draw diagonal stripes
    final stripePaint = Paint()
      ..color = stripeColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    const stripeWidth = 10.0;
    const spacing = 10.0;
    final totalStripeWidth = stripeWidth + spacing;

    // Calculate how many stripes we need
    final diagonalLength = size.width + size.height;
    final stripeCount = (diagonalLength / totalStripeWidth).ceil();

    for (int i = 0; i < stripeCount; i++) {
      final offset = i * totalStripeWidth;

      final path = Path()
        ..moveTo(offset, 0)
        ..lineTo(offset + stripeWidth, 0)
        ..lineTo(offset + stripeWidth - size.height, size.height)
        ..lineTo(offset - size.height, size.height)
        ..close();

      canvas.drawPath(path, stripePaint);
    }
  }

  @override
  bool shouldRepaint(StripePainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.stripeColor != stripeColor;
  }
}

// Alternative simple stripe widget using gradient
class SimpleWarningStripe extends StatelessWidget {
  final String text;
  final double height;

  const SimpleWarningStripe({
    Key? key,
    required this.text,
    this.height = 24,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: List.generate(20, (index) {
            return index % 2 == 0 ? Colors.yellow.shade700 : Colors.black87;
          }),
          stops: List.generate(20, (index) => index / 19),
          tileMode: TileMode.repeated,
        ),
      ),
      child: Container(
        color: Colors.black87.withOpacity(0.7),
        child: Center(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              color: Colors.yellow,
              fontSize: height * 0.4,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
