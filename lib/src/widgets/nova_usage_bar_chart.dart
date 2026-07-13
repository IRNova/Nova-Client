import 'package:flutter/material.dart';

import '../theme/nova_semantics.dart';
import '../theme/nova_theme.dart';

/// A compact bar chart of recent values with the tallest bar highlighted by a
/// full-accent gradient, mirroring the native `NovaUsageBarChart`. Empty or
/// all-zero input renders flat baseline stubs.
class NovaUsageBarChart extends StatelessWidget {
  const NovaUsageBarChart({
    super.key,
    required this.values,
    this.accent,
    this.height = 120,
    this.labels,
  });

  final List<double> values;
  final Color? accent;
  final double height;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final Color a = accent ?? nova.cyan;
    final double max =
        values.isEmpty ? 0 : values.reduce((x, y) => x > y ? x : y);
    final int peak = _peakIndex(values);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Container(
                      height: _barHeight(values[i], max),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: i == peak
                              ? <Color>[a, a.withValues(alpha: 0.7)]
                              : <Color>[
                                  a.withValues(alpha: 0.55),
                                  NovaSemantics.teal.withValues(alpha: 0.4),
                                ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ),
                    if (labels != null && i < labels!.length) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(labels![i],
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: nova.muted, fontSize: 9)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _barHeight(double v, double max) {
    final double track = height - 16;
    if (max <= 0) return 3;
    return (3 + (v / max) * (track - 3)).clamp(3, track);
  }

  int _peakIndex(List<double> v) {
    int idx = 0;
    double best = -1;
    for (int i = 0; i < v.length; i++) {
      if (v[i] > best) {
        best = v[i];
        idx = i;
      }
    }
    return idx;
  }
}
