import 'package:flutter/material.dart';
import '../theme.dart';

/// PixShift logo mark, drawn from the same shapes as the website's logo.svg (no image file needed).
class PixLogo extends StatelessWidget {
  final double size;
  const PixLogo({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter()));
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    canvas.drawRRect(RRect.fromRectXY(const Rect.fromLTWH(0, 0, 64, 64), 16, 16), Paint()..color = C.pine);
    canvas.drawRRect(RRect.fromRectXY(const Rect.fromLTWH(12, 14, 40, 36), 6, 6), Paint()..color = C.zest);
    final hill = Path()
      ..moveTo(12, 38)
      ..lineTo(26, 26)
      ..lineTo(36, 35)
      ..lineTo(42, 30)
      ..lineTo(52, 40)
      ..lineTo(52, 44)
      ..arcToPoint(const Offset(46, 50), radius: const Radius.circular(6), clockwise: true)
      ..lineTo(18, 50)
      ..arcToPoint(const Offset(12, 44), radius: const Radius.circular(6), clockwise: true)
      ..close();
    canvas.drawPath(hill, Paint()..color = C.pine);
    canvas.drawCircle(const Offset(42, 22), 4, Paint()..color = C.pine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}