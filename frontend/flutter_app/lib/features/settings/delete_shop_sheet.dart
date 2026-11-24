/// "Delete my shop" (owner only): type the shop's name to confirm, then `DELETE /v1/shop`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../design/design.dart';

/// Returns once the shop is deleted and the merchant signed out, or the sheet was closed.
Future<void> showDeleteShopSheet(BuildContext context, String shopName) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final deleted = await showSxSheet<bool>(
    context,
    title: 'Delete your shop?',
    subtitle:
        'This deletes $shopName from sellix: products, orders, chats and settings. It can’t be '
        'undone. Everyone signed in to the shop is signed out.',
    builder: (_) => _DeleteShopSheet(shopName: shopName),
  );
  if (deleted != true) return;
  // The server already ended every session; this clears the one on this phone.
  await container.read(authControllerProvider.notifier).signOut();
}

class _DeleteShopSheet extends ConsumerStatefulWidget {
  const _DeleteShopSheet({required this.shopName});

  final String shopName;

  @override
  ConsumerState<_DeleteShopSheet> createState() => _DeleteShopSheetState();
}

class _DeleteShopSheetState extends ConsumerState<_DeleteShopSheet> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _matches => _name.text.trim() == widget.shopName;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sellixApiProvider).deleteShop(_name.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          SxField(
            controller: _name,
            label: 'Type ${widget.shopName} to confirm',
            hint: widget.shopName,
            enabled: !_busy,
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: SxText.caption.copyWith(color: p.errorText)),
            ),
          SxButtonRow(
            children: [
              SxButton(
                label: 'Keep my shop',
                kind: SxButtonKind.secondary,
                onTap: _busy ? null : () => Navigator.of(context).pop(),
              ),
              SxButton(
                label: 'Delete shop',
                icon: TablerIcons.trash,
                loading: _busy,
                onTap: _busy || !_matches ? null : _delete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
