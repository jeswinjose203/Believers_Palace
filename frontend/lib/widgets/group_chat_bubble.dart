import 'package:flutter/material.dart';

enum ChatSendStatus { sent, sending, failed }

class GroupChatBubble extends StatelessWidget {
  final String content;
  final String authorName;
  final bool mine;
  final String timeLabel;
  final String? dateDivider;
  final ChatSendStatus status;
  final bool animate;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onLongPress;

  const GroupChatBubble({
    super.key,
    required this.content,
    required this.authorName,
    required this.mine,
    required this.timeLabel,
    this.dateDivider,
    this.status = ChatSendStatus.sent,
    this.animate = false,
    this.onRetry,
    this.onDelete,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = status == ChatSendStatus.failed
        ? scheme.errorContainer
        : mine
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: scheme.secondaryContainer,
              child: Text(
                authorName.isEmpty ? '?' : authorName[0].toUpperCase(),
                style: theme.textTheme.labelSmall,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: GestureDetector(
              onTap: status == ChatSendStatus.failed ? onRetry : null,
              onLongPress: onLongPress,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.76,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!mine && authorName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          authorName,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    Text(content),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          status == ChatSendStatus.failed
                              ? 'Not sent · tap to retry'
                              : timeLabel,
                          style: theme.textTheme.labelSmall,
                        ),
                        if (status == ChatSendStatus.sending) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: scheme.outline,
                            ),
                          ),
                        ] else if (status == ChatSendStatus.failed) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.error_outline,
                              size: 14, color: scheme.error),
                        ] else if (mine) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.check, size: 14, color: scheme.outline),
                        ],
                        if (onDelete != null) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: onDelete,
                            child: Icon(Icons.delete_outline,
                                size: 14, color: scheme.outline),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final message = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dateDivider != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Text(dateDivider!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ),
          ),
        bubble,
      ],
    );
    if (!animate) return message;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: message,
    );
  }
}
