import 'package:flutter/material.dart';

import '../../l10n/nova_strings.dart';
import '../../theme/nova_radii.dart';
import '../../widgets/nova_button.dart';
import 'servers_body.dart';

/// The Servers tab: a header with an Add action over the shared [ServersBody].
class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = NovaStrings.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: NovaSpace.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: <Widget>[
                  Text(s.navServers,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const Spacer(),
                  NovaButton(
                    label: s.add,
                    icon: Icons.add,
                    onPressed: () => showAddConfigSheet(context),
                  ),
                ],
              ),
            ),
            const Expanded(child: ServersBody()),
          ],
        ),
      ),
    );
  }
}
