import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../core/auth_provider.dart';
import '../services/chat_notification_service.dart';

class ChatNotificationButton extends ConsumerStatefulWidget {
  const ChatNotificationButton(
      {super.key, required this.kind, required this.id});

  final ChatKind kind;
  final String id;

  @override
  ConsumerState<ChatNotificationButton> createState() =>
      _ChatNotificationButtonState();
}

class _ChatNotificationButtonState
    extends ConsumerState<ChatNotificationButton> {
  bool? _muted;
  bool _saving = false;
  late final _notifications = ref.read(chatNotificationServiceProvider);

  @override
  void initState() {
    super.initState();
    _notifications.preferenceChanges.addListener(_preferenceChanged);
    _load();
  }

  @override
  void dispose() {
    _notifications.preferenceChanges.removeListener(_preferenceChanged);
    super.dispose();
  }

  void _preferenceChanged() => _load(refresh: false);

  Future<void> _load({bool refresh = true}) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    try {
      final muted = await _notifications.muted(user.id, widget.kind, widget.id,
          refresh: refresh);
      if (mounted) setState(() => _muted = muted);
    } catch (error) {
      debugPrint('Could not load notification setting: $error');
    }
  }

  Future<void> _toggle() async {
    final user = ref.read(authProvider).user;
    final muted = _muted;
    if (user == null || muted == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(chatNotificationServiceProvider).setMuted(
            user.id,
            widget.kind,
            widget.id,
            !muted,
          );
      if (mounted) setState(() => _muted = !muted);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Could not save notification setting.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: _muted == true
            ? context.tr('Enable chat notifications')
            : context.tr('Mute chat notifications'),
        onPressed: _muted == null || _saving ? null : _toggle,
        icon: Icon(_muted == true
            ? Icons.notifications_off_outlined
            : Icons.notifications_outlined),
      );
}
