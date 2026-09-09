import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GardenBackground extends StatelessWidget {
  const GardenBackground({
    super.key,
    required this.child,
    this.showFlowers = true,
  });

  final Widget child;
  final bool showFlowers;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.mistBlue, AppColors.cream, Color(0xFFF1EDFA)],
          stops: [0, .55, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -75,
            right: -55,
            child: _Glow(color: AppColors.lavender.withValues(alpha: .42)),
          ),
          Positioned(
            bottom: 70,
            left: -95,
            child: _Glow(color: AppColors.softBlue.withValues(alpha: .28)),
          ),
          if (showFlowers)
            const Positioned(
              right: -38,
              top: 72,
              child: Opacity(opacity: .48, child: HydrangeaCluster(size: 145)),
            ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      height: 210,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class HydrangeaCluster extends StatelessWidget {
  const HydrangeaCluster({super.key, this.size = 180});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _HydrangeaPainter());
  }
}

class _HydrangeaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final leaf = Paint()..color = AppColors.leaf.withValues(alpha: .55);
    final stem = Paint()
      ..color = AppColors.leaf.withValues(alpha: .75)
      ..strokeWidth = size.width * .018
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * .52, size.height * .52),
      Offset(size.width * .46, size.height * .98),
      stem,
    );
    canvas.save();
    canvas.translate(size.width * .26, size.height * .66);
    canvas.rotate(-.52);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * .35,
        height: size.height * .16,
      ),
      leaf,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(size.width * .68, size.height * .73);
    canvas.rotate(.58);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * .33,
        height: size.height * .15,
      ),
      leaf,
    );
    canvas.restore();

    const centers = [
      Offset(.50, .17),
      Offset(.34, .24),
      Offset(.65, .26),
      Offset(.20, .38),
      Offset(.48, .38),
      Offset(.77, .40),
      Offset(.31, .53),
      Offset(.61, .55),
      Offset(.48, .68),
    ];
    final colors = [
      AppColors.softBlue,
      AppColors.hydrangea,
      AppColors.lavender,
      const Color(0xFFA8BCE7),
    ];
    for (var i = 0; i < centers.length; i++) {
      _flower(
        canvas,
        Offset(centers[i].dx * size.width, centers[i].dy * size.height),
        size.width * (.105 + (i % 3) * .008),
        colors[i % colors.length].withValues(alpha: .88),
      );
    }
  }

  void _flower(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()..color = color;
    for (var i = 0; i < 4; i++) {
      final angle = math.pi * i / 2;
      final offset = Offset(math.cos(angle), math.sin(angle)) * radius * .58;
      canvas.drawCircle(center + offset, radius * .62, paint);
    }
    canvas.drawCircle(
      center,
      radius * .18,
      Paint()..color = Colors.white.withValues(alpha: .82),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Butterfly extends StatelessWidget {
  const Butterfly({super.key, this.size = 34, this.color = AppColors.deepBlue});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * .75),
      painter: _ButterflyPainter(color),
    );
  }
}

class _ButterflyPainter extends CustomPainter {
  _ButterflyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final wing = Paint()..color = color.withValues(alpha: .72);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .27, size.height * .37),
        width: size.width * .48,
        height: size.height * .62,
      ),
      wing,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .73, size.height * .37),
        width: size.width * .48,
        height: size.height * .62,
      ),
      wing,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .36, size.height * .66),
        width: size.width * .28,
        height: size.height * .38,
      ),
      wing,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .64, size.height * .66),
        width: size.width * .28,
        height: size.height * .38,
      ),
      wing,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .5, size.height * .5),
          width: size.width * .08,
          height: size.height * .62,
        ),
        const Radius.circular(8),
      ),
      Paint()..color = AppColors.ink.withValues(alpha: .75),
    );
  }

  @override
  bool shouldRepaint(covariant _ButterflyPainter oldDelegate) =>
      oldDelegate.color != color;
}
