import 'package:flutter/material.dart';

class BriskersLogo extends StatelessWidget {
  const BriskersLogo({
    super.key,
    this.height = 38,
    this.maxWidth = 116,
  });

  final double height;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: maxWidth,
      child: Image.asset(
        'assets/briskers_header_logo.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class BriskersPageTitle extends StatelessWidget {
  const BriskersPageTitle({
    super.key,
    required this.title,
    this.logoHeight = 38,
    this.logoWidth = 116,
  });

  final String title;
  final double logoHeight;
  final double logoWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BriskersLogo(
          height: logoHeight,
          maxWidth: logoWidth,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
