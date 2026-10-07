import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../widgets/notification_ui.dart';

/// Premium notifications inbox — every app event (sign-ins, clock in/out,
/// broadcasts, roster exports) lands here via [NotificationService], next
/// to server staff announcements.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const gisDeepOlive = Color(0xFF2E4D2A);
  static const darkCharcoal = Color(0xFF1A2519);
  static const lightGrayBg = Color(0xFFF5F6F5);
  static const mutedText = Color(0xFF6E7A6C);
  static const hairline = Color(0xFFE7E9E4);

  String _filter = 'All';
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    NotificationService.refreshNotifications();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<NotificationItem> _applyFilters(List<NotificationItem> all) {
    var out = all;
    if (_filter == 'Unread') {
      out = out.where((n) => !n.isRead).toList();
    } else if (_filter != 'All') {
      out = out.where((n) => n.category == _filter).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.message.toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGrayBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: darkCharcoal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            onPressed: () => NotificationService.markAllRead(),
            icon: const Icon(Icons.done_all_rounded,
                color: gisDeepOlive, size: 22),
          ),
          IconButton(
            tooltip: 'Clear all',
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined,
                color: gisDeepOlive, size: 22),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: hairline),
        ),
      ),
      body: ValueListenableBuilder<List<NotificationItem>>(
        valueListenable: NotificationService.notificationsNotifier,
        builder: (context, all, _) {
          final unread = all.where((n) => !n.isRead).length;
          final categories = <String>{
            for (final n in all) n.category,
          }.toList()
            ..sort();
          final chips = ['All', 'Unread', ...categories];
          if (!chips.contains(_filter)) _filter = 'All';
          final shown = _applyFilters(all);

          return RefreshIndicator(
            color: gisDeepOlive,
            onRefresh: () => NotificationService.refreshNotifications(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              unread == 0
                                  ? 'You are all caught up'
                                  : '$unread unread',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: darkCharcoal,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Refresh',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => NotificationService
                                  .refreshNotifications(),
                              icon: const Icon(Icons.refresh_rounded,
                                  color: gisDeepOlive),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (v) =>
                              setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: 'Search notifications',
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: mutedText),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear_rounded,
                                        size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _query = '');
                                    },
                                  ),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: hairline),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: hairline),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: chips.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final c = chips[i];
                              final active = _filter == c;
                              return ChoiceChip(
                                label: Text(c),
                                selected: active,
                                onSelected: (_) =>
                                    setState(() => _filter = c),
                                selectedColor: gisDeepOlive,
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? Colors.white
                                      : darkCharcoal,
                                ),
                                side: BorderSide(
                                  color: active
                                      ? gisDeepOlive
                                      : hairline,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(18),
                                ),
                                showCheckmark: false,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
                if (shown.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(all.isEmpty),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = shown[index];
                        return Dismissible(
                          key: ValueKey(
                              'notif_${item.id}_${item.timestamp.millisecondsSinceEpoch}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD63031),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: Colors.white),
                          ),
                          onDismissed: (_) =>
                              NotificationService.deleteNotification(
                                  item.id),
                          child: GestureDetector(
                            onTap: () => _openDetails(item),
                            child: _buildNotificationCard(item),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmClear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Clear History",
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
            "Delete all notifications on this device? Server announcements will reappear on refresh."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel",
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete",
                style: TextStyle(
                    color: Color(0xFFD63031),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await NotificationService.clearNotifications();
    }
  }

  void _openDetails(NotificationItem item) {
    NotificationService.markAsRead(item.id);
    _showNotificationDetails(context, item);
  }

  // ============================================================================
  // NOTIFICATION DETAILS MODAL
  // ============================================================================

  void _showNotificationDetails(
      BuildContext context, NotificationItem item) {
    final dateStr =
        DateFormat('MMMM d, yyyy • hh:mm a').format(item.timestamp);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(24),
                      children: [
                        Row(
                          children: [
                            _buildBadge(item),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Delete',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                Navigator.pop(context);
                                NotificationService.deleteNotification(
                                    item.id);
                              },
                              icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFD63031)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: NotificationUi.tintFor(item.category),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            NotificationUi.iconFor(item.category),
                            color: NotificationUi.colorFor(item.category),
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: darkCharcoal,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 14, color: mutedText),
                            const SizedBox(width: 6),
                            Text(dateStr,
                                style: const TextStyle(
                                    color: mutedText, fontSize: 13)),
                            const SizedBox(width: 8),
                            Text(
                              '•  ${NotificationUi.relativeTime(item.timestamp)}',
                              style: const TextStyle(
                                  color: mutedText, fontSize: 13),
                            ),
                          ],
                        ),
                        const Divider(height: 32, color: hairline),
                        Text(
                          item.message,
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.6,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================================
  // NOTIFICATION CARD
  // ============================================================================

  Widget _buildNotificationCard(NotificationItem item) {
    final color = NotificationUi.colorFor(item.category);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: NotificationUi.tintFor(item.category),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          NotificationUi.iconFor(item.category),
                          size: 19,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.category.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                      color: color,
                                    ),
                                  ),
                                ),
                                Text(
                                  NotificationUi.relativeTime(
                                      item.timestamp),
                                  style: const TextStyle(
                                      fontSize: 10.5, color: mutedText),
                                ),
                                if (!item.isRead) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFD63031),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: item.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                  fontSize: 14.5,
                                  color: darkCharcoal),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // EMPTY STATE
  // ============================================================================

  Widget _buildEmptyState(bool totallyEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: Color(0xFFE3EAE1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_outlined,
                  size: 40, color: gisDeepOlive),
            ),
            const SizedBox(height: 18),
            Text(
                totallyEmpty
                    ? "No notifications yet"
                    : "Nothing matches",
                style: const TextStyle(
                    color: darkCharcoal,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                totallyEmpty
                    ? "Sign-ins, clock in/out, broadcasts and announcements will appear here"
                    : "Try a different search or filter",
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: mutedText, fontSize: 13)),
            if (totallyEmpty) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => NotificationService.TestNotification(),
                icon: const Icon(Icons.notification_add_outlined,
                    size: 18),
                label: const Text('Send test notification'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: gisDeepOlive,
                  side: const BorderSide(color: gisDeepOlive),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // BADGE WIDGET
  // ============================================================================

  Widget _buildBadge(NotificationItem item) {
    final color = NotificationUi.colorFor(item.category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: NotificationUi.tintFor(item.category),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        item.category,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
