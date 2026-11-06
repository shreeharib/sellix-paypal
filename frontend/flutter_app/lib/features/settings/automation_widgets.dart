import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../stock/stock_providers.dart';
import 'automations_store.dart';
import 'settings_providers.dart';

/// The "not active yet" line on anything that shows an automation.
class AutomationLocalTag extends StatelessWidget {
  const AutomationLocalTag({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Row(
      spacing: SxSpace.s4,
      children: [
        Icon(TablerIcons.device_mobile, size: 14, color: p.textSecondary),
        Expanded(child: Text(automationLocalNote, style: SxText.micro.copyWith(color: p.textSecondary))),
      ],
    );
  }
}

/// Switches on the phone, with the prototype's Undo. It says what really happened: nothing runs.
Future<void> toggleAutomation(BuildContext context, Automation automation, bool on) async {
  final container = containerOf(context);
  await container.read(automationsProvider.notifier).setOn(automation.id, on);
  if (!context.mounted) return;
  showSxSnack(
    context,
    on ? '${automation.title} saved as on. Not active yet.' : '${automation.title} is off.',
    icon: on ? TablerIcons.bolt : TablerIcons.player_pause,
    sellix: false,
    action: 'Undo',
    onAction: () => container.read(automationsProvider.notifier).setOn(automation.id, !on),
    duration: const Duration(milliseconds: 2600),
  );
}

/// A sample chat. Fills in today's first real stock item when there is one; otherwise it shows the
/// {placeholders}, because a made-up product would read as real.
class AutomationMiniChat extends ConsumerWidget {
  const AutomationMiniChat({super.key, required this.lines});

  final List<ChatLine> lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final fill = automationFiller(ref);
    return Container(
      padding: const EdgeInsets.all(SxSpace.s12),
      decoration: BoxDecoration(color: p.page, borderRadius: BorderRadius.circular(18)),
      child: Column(
        spacing: 6,
        children: [
          for (final line in lines)
            _MiniChatLine(line: line, text: fill(line.text)),
        ],
      ),
    );
  }
}

class _MiniChatLine extends StatelessWidget {
  const _MiniChatLine({required this.line, required this.text});

  final ChatLine line;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final fromCustomer = line.kind == ChatLineKind.customer || line.kind == ChatLineKind.event;
    final side = fromCustomer ? Alignment.centerLeft : Alignment.centerRight;
    return FractionallySizedBox(
      alignment: side,
      widthFactor: 0.82,
      child: Align(
        alignment: side,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: line.kind == ChatLineKind.sellix ? p.bubbleAi : p.card,
            borderRadius: BorderRadius.circular(14),
            border: line.kind == ChatLineKind.button ? Border.all(color: p.lineStrong) : null,
          ),
          child: Text(
            text,
            style: SxText.caption.copyWith(
              color: line.kind == ChatLineKind.sellix ? p.onBubbleAi : p.textPrimary,
              fontStyle: line.kind == ChatLineKind.event ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces {product}, {price} and {left} from today's first stock row. {name} is left generic.
String Function(String) automationFiller(WidgetRef ref) {
  final rows = ref.watch(todayProvider).value?.stock;
  final row = rows == null || rows.isEmpty ? null : rows.first;
  return (text) {
    var out = text.replaceAll('{name}', 'Customer');
    if (row != null) {
      out = out
          .replaceAll('{product}', row.product)
          .replaceAll('{price}', money(row.priceMinor, row.currency))
          .replaceAll('{left}', '${row.available}');
    }
    return out;
  };
}

/// One automation on the list (`.au-card`): a visible switch on the card and its honest state.
class AutomationCard extends ConsumerWidget {
  const AutomationCard({super.key, required this.automation});

  final Automation automation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = automation;
    final p = context.sx;
    final agentOn = ref.watch(meProvider).value?.merchant.agentEnabled ?? true;
    void open() => context.push(Routes.automation(a.id));
    return Container(
      padding: const EdgeInsets.all(SxSpace.card),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(SxRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SxSpace.s12,
            children: [
              SxPressable(
                onTap: open,
                semanticLabel: 'Open ${a.title}',
                small: true,
                child: SxIconTile(icon: a.icon, foreground: a.on ? null : p.textSecondary),
              ),
              Expanded(
                child: SxPressable(
                  onTap: open,
                  haptic: false,
                  small: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: SxSpace.s4,
                    children: [
                      Text(a.title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                      Text(a.description, style: SxText.caption.copyWith(color: p.textSecondary)),
                    ],
                  ),
                ),
              ),
              if (a.locked)
                const SxChip(label: 'On', icon: TablerIcons.lock)
              else
                SxToggle(
                  value: a.on,
                  semanticLabel: a.title,
                  onChanged: (v) => toggleAutomation(context, a, v),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: SxSpace.s12),
            child: Divider(height: 1, thickness: 1, color: p.line),
          ),
          const SizedBox(height: SxSpace.s12),
          Row(
            spacing: SxSpace.s8,
            children: [
              for (final brand in a.channels) SxBrandIcon(brand, size: 16, color: p.textSecondary),
              SxChip(
                label: a.mode == AutomationMode.auto ? 'Autopilot' : 'Draft first',
                icon: a.mode == AutomationMode.auto ? TablerIcons.bolt : TablerIcons.pencil,
              ),
              const Spacer(),
              Text(
                a.locked ? (agentOn ? 'Running' : 'Agent paused') : (a.on ? 'On' : 'Off'),
                style: SxText.micro.copyWith(color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: SxSpace.s8),
          if (a.locked)
            // Not the local note: these two are the agent itself and really do run.
            Text('Built into sellix. Follows the agent switch in Profile.',
                style: SxText.micro.copyWith(color: p.textSecondary))
          else
            const AutomationLocalTag(),
        ],
      ),
    );
  }
}
