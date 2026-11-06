import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import 'sx_header.dart';
import 'sx_scaffold.dart';
import 'sx_states.dart';

/// Placeholder used until a feature replaces the screen. Delete with the last stub.
class SxStubScreen extends StatelessWidget {
  const SxStubScreen({super.key, required this.title, this.meta, this.root = false});

  final String title;
  final String? meta;
  final bool root;

  @override
  Widget build(BuildContext context) {
    return SxScaffold(
      body: Column(
        children: [
          if (!root) SxDetailHeader(title: title, meta: meta),
          Expanded(
            child: SxEmptyState(icon: TablerIcons.tools, title: root ? title : 'Not built yet', body: meta),
          ),
        ],
      ),
    );
  }
}
