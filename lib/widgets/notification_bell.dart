import 'package:flutter/material.dart';
import 'package:gis_attendance/models/notification_model.dart';
import 'package:gis_attendance/screens/notifications_screen.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:gis_attendance/widgets/notification_ui.dart';

/// App-bar notification bell with an unread badge and a dropdown panel.
///
/// Tapping the bell opens a small overlay under it with the latest
/// notifications, a "mark all read" action and a "View all" link into
/// [NotificationsScreen]. Tapping outside closes the dropdown.
class NotificationBell extends StatefulWidget {
  final Color iconColor;
  const NotificationBell({super.key, this.iconColor = const Color(0xFF2E4D2A)});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  OverlayEntry? _entry;

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _toggle() {
    if (_entry != null) {
      _close();
    } else {
      _open();
    }
  }

  void _close() {
    NotificationService.notificationsNotifier
        .removeListener(_rebuildOverlay);
    _entry?.remove();
    _entry = null;
  }

  void _rebuildOverlay() => _entry?.markNeedsBuild();

  void _open() {
    NotificationService.notificationsNotifier.addListener(_rebuildOverlay);
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (ctx) {
        final width = MediaQuery.of(ctx).size.width;
        final panelWidth = (width - 24).clamp(0.0, 360.0);
        return Stack(
          children: [
            // tap-outside-to-close
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
              ),
            ),
            Positioned(
              top: kToolbarHeight + 6,
              right: 12,
              width: panelWidth,
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(18),
                shadowColor: Colors.black.withValues(alpha: 0.2),
                child: _DropdownPanel(onClose: _close),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<NotificationItem>>(
      valueListenable: NotificationService.notificationsNotifier,
      builder: (context, items, _) {
        final unread = items.where((n) => !n.isRead).length;
        return IconButton(
          tooltip: 'Notifications',
          onPressed: _toggle,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications_outlined,
                  color: widget.iconColor, size: 23),
              if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD63031),
                      borderRadius: BorderRadius.circular(9),
                      border:
                          Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DropdownPanel extends StatelessWidget {
  final VoidCallback onClose;
  const _DropdownPanel({required this.onClose});

  @override
  Widget build(BuildContext context) {
    const olive = Color(0xFF2E4D2A);
    const muted = Color(0xFF6E7A6C);
    return ValueListenableBuilder<List<NotificationItem>>(
      valueListenable: NotificationService.notificationsNotifier,
      builder: (context, items, _) {
        final unread = items.where((n) => !n.isRead).length;
        final recent = items.take(6).toList();
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF1A2519)),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1F9EC),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$unread new',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF14663A),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      tooltip: 'Mark all read',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          NotificationService.markAllRead(),
                      icon: const Icon(Icons.done_all_rounded,
                          size: 19, color: olive),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                    'You are all caught up.',
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: recent.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 58),
                    itemBuilder: (_, i) {
                      final n = recent[i];
                      return InkWell(
                        onTap: () {
                          onClose();
                          NotificationService.markAsRead(n.id);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const NotificationsScreen(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: NotificationUi.tintFor(
                                      n.category),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  NotificationUi.iconFor(
                                      n.category),
                                  size: 17,
                                  color: NotificationUi.colorFor(
                                      n.category),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n.title,
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: n.isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.w800,
                                              color: const Color(
                                                  0xFF1A2519),
                                            ),
                                          ),
                                        ),
                                        if (!n.isRead)
                                          Container(
                                            width: 7,
                                            height: 7,
                                            margin:
                                                const EdgeInsets.only(
                                                    left: 6),
                                            decoration:
                                                const BoxDecoration(
                                              color: Color(0xFFD63031),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      n.message,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: muted),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      NotificationUi.relativeTime(
                                          n.timestamp),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9AA39A)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const Divider(height: 1),
              InkWell(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(18)),
                onTap: () {
                  onClose();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const NotificationsScreen(),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'View all notifications',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: olive,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
