import 'package:flutter/material.dart';

import '../theme/nova_radii.dart';
import '../theme/nova_theme.dart';

/// One segment in a [NovaSegmentedTabs] control.
class NovaSegment {
  const NovaSegment({required this.label, this.icon, this.badge});
  final String label;
  final IconData? icon;

  /// Optional count badge (e.g. config count on the "Configs" tab).
  final int? badge;
}

/// A pill/segmented control matching the native `NovaHomeTabs` and the Stats
/// range tabs: a rounded surface track with an animated accent-tinted selected
/// segment. Used for Summary/Configs and Daily/Weekly/Monthly/Yearly.
class NovaSegmentedTabs extends StatelessWidget {
  const NovaSegmentedTabs({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final List<NovaSegment> segments;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Smaller paddings/sizes (used by the Stats range tabs).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: nova.surface,
        borderRadius: NovaRadii.tabR,
        border: Border.all(color: nova.border),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < segments.length; i++)
            Expanded(
              child: _Segment(
                segment: segments[i],
                selected: i == selected,
                compact: compact,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final NovaSegment segment;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final text = Theme.of(context).textTheme;
    final Color fg = selected ? nova.cyan : nova.muted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
        decoration: BoxDecoration(
          color: selected ? nova.cyan.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 10 : 11),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (segment.icon != null) ...<Widget>[
              Icon(segment.icon, size: compact ? 15 : 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                segment.label,
                overflow: TextOverflow.ellipsis,
                style: (compact ? text.labelMedium : text.titleSmall)?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            if ((segment.badge ?? 0) > 0) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: nova.cyan,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${segment.badge}',
                  style: text.labelSmall?.copyWith(
                    color: nova.onAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
