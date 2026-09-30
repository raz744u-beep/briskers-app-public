import 'package:flutter/material.dart';

class BriskersLogo extends StatelessWidget {
  const BriskersLogo({super.key, this.height = 42});

  final double height;

  @override
  Widget build(BuildContext context) {
    final width = height * 3.1;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _BriskersLogoPainter(),
      ),
    );
  }
}

class BriskersPageTitle extends StatelessWidget {
  const BriskersPageTitle({
    super.key,
    required this.title,
    this.logoHeight = 38,
  });

  final String title;
  final double logoHeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BriskersLogo(height: logoHeight),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _BriskersLogoPainter extends CustomPainter {
  static const blue = Color(0xFF005BCE);

  @override
  void paint(Canvas canvas, Size size) {
    final carPaint = Paint()
      ..color = blue
      ..style = PaintingStyle.fill;

    final car = Path()
      ..moveTo(size.width * .02, size.height * .58)
      ..quadraticBezierTo(
        size.width * .10, size.height * .25,
        size.width * .28, size.height * .21,
      )
      ..lineTo(size.width * .45, size.height * .20)
      ..quadraticBezierTo(
        size.width * .58, size.height * .22,
        size.width * .69, size.height * .43,
      )
      ..quadraticBezierTo(
        size.width * .89, size.height * .45,
        size.width * .98, size.height * .62,
      )
      ..lineTo(size.width * .91, size.height * .69)
      ..lineTo(size.width * .12, size.height * .69)
      ..close();
    canvas.drawPath(car, carPaint);

    final cutPaint = Paint()..color = Colors.white;
    final windshield = Path()
      ..moveTo(size.width * .29, size.height * .29)
      ..lineTo(size.width * .45, size.height * .27)
      ..lineTo(size.width * .57, size.height * .43)
      ..lineTo(size.width * .35, size.height * .43)
      ..close();
    canvas.drawPath(windshield, cutPaint);

    final rearWindow = Path()
      ..moveTo(size.width * .47, size.height * .27)
      ..lineTo(size.width * .56, size.height * .30)
      ..lineTo(size.width * .66, size.height * .43)
      ..lineTo(size.width * .59, size.height * .43)
      ..close();
    canvas.drawPath(rearWindow, cutPaint);

    final wheelPaint = Paint()
      ..color = const Color(0xFF20242B)
      ..style = PaintingStyle.fill;
    final rimPaint = Paint()
      ..color = const Color(0xFFBBC3CD)
      ..style = PaintingStyle.fill;
    for (final x in [size.width * .23, size.width * .76]) {
      canvas.drawCircle(
        Offset(x, size.height * .68),
        size.height * .13,
        wheelPaint,
      );
      canvas.drawCircle(
        Offset(x, size.height * .68),
        size.height * .065,
        rimPaint,
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        text: 'BRISKERS',
        style: TextStyle(
          color: blue,
          fontWeight: FontWeight.w900,
          fontSize: size.height * .28,
          letterSpacing: .7,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width);
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        size.height * .72,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
