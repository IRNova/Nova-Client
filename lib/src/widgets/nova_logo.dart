import 'package:flutter/material.dart';

/// The official Nova mark, rendered from the real brand artwork
/// (`assets/brand/nova-mark.png`, the glossy gradient "N" in its ringed badge,
/// pulled from novaproxy.online). Earlier this was an approximated stroke path;
/// it now uses the genuine logo so the app matches the site and store listing.
///
/// The asset is circular with transparent corners, so it drops cleanly onto any
/// background (light or dark). [gradient] is accepted for source compatibility
/// but ignored — the artwork already carries the brand gradient; [color] tints
/// the mark for monochrome contexts.
class NovaLogo extends StatelessWidget {
  const NovaLogo({
    super.key,
    this.size = 40,
    this.gradient,
    this.color,
  });

  final double size;

  /// Accepted for compatibility with earlier call sites; the artwork already
  /// carries the brand gradient, so this is ignored.
  final Gradient? gradient;

  /// Tints the mark to a single colour (monochrome contexts).
  final Color? color;

  /// A single-colour mark — kept for source compatibility with the old API.
  const NovaLogo.mono({super.key, this.size = 40, required Color this.color})
      : gradient = null;

  static const String _asset = 'assets/brand/nova-mark.png';

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      _asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    if (color != null) {
      return SizedBox(
        width: size,
        height: size,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(color!, BlendMode.srcATop),
          child: image,
        ),
      );
    }
    return image;
  }
}

/// The mark on a rounded dark badge. The brand artwork is already a badge, so
/// this now just renders [NovaLogo] at the requested size (kept for source
/// compatibility with existing call sites).
class NovaLogoBadge extends StatelessWidget {
  const NovaLogoBadge({super.key, this.size = 56, this.tileColor});

  final double size;
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    return NovaLogo(size: size);
  }
}
