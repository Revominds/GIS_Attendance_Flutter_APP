// Broadcast SMS screen — compose one message and send it to all staff,
// only active officers, or one department. Shows per-recipient results.
import 'package:flutter/material.dart';
import 'package:gis_attendance/services/admin_service.dart';
import 'package:gis_attendance/services/broadcast_service.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:gis_attendance/theme/app_theme.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});
  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _admin = AdminService();
  final _broadcast = BroadcastService();
  final _msgCtrl = TextEditingController();

  List<Map<String, dynamic>> _officers = []; //dynamic officers
  bool _loadingOfficers = true;
  String _audience = 'all';
  bool _sending = false;
  int _done = 0;
  int _total = 0;
  BroadcastSummary? _last;

  @override
  void initState() {
    super.initState();
    _loadOfficers();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOfficers() async {
    setState(() => _loadingOfficers = true);
    final res = await _admin.listOfficers();
    if (!mounted) return;
    setState(() {
      _loadingOfficers = false;
      if (res.ok) _officers = res.data ?? [];
    });
    if (!res.ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  List<Map<String, dynamic>> get _recipients =>
      BroadcastService.resolveRecipients(_officers, _audience);

  Future<void> _send() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Type a message first')));
      return;
    }
    if (_recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No recipients in this audience')));
      return;
    }
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Send broadcast?'),
              content: Text(
                  'Send to ${_recipients.length} officer(s)?\n\n"$msg"'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Send')),
              ],
            ));
    if (ok != true) return;
    setState(() { _sending = true; _done = 0; _total = _recipients.length; _last = null; });
    final summary = await _broadcast.sendBroadcast(
      recipients: _recipients,
      message: msg,
      onProgress: (d, t) { if (mounted) setState(() { _done = d; _total = t; }); },
    );
    if (!mounted) return;
    setState(() { _sending = false; _last = summary; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sent ${summary.sent}/${summary.results.length}'),
        backgroundColor:
            summary.failed == 0 ? AppColors.success : AppColors.danger));
    NotificationService.logActivity(
      'Broadcast sent',
      'Broadcast delivered to ${summary.sent}/${summary.results.length} officer(s).',
      category: 'Broadcast',
    );
  }

  Widget _buildAudienceCard(List<String> depts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Audience',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_loadingOfficers)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in ['all', 'active', ...depts])
                ChoiceChip(
                  label: Text(a == 'all'
                      ? 'All staff (${_officers.length})'
                      : a == 'active'
                          ? 'Active only'
                          : a),
                  selected: _audience == a,
                  onSelected: (_) => setState(() => _audience = a),
                ),
            ]),
          const SizedBox(height: 6),
          Text('${_recipients.length} recipient(s) selected',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
    );
  }

  Widget _buildMessageCard(int chars) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _msgCtrl,
            maxLines: 5,
            maxLength: 1000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'e.g. All officers report to HQ by 08:00 tomorrow.',
                alignLabelWithHint: true),
          ),
          Text('$chars / 1000  •  ~${(chars / 160).ceil()} SMS segment(s)',
              style:
                  const TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 10),
          if (_sending)
            Column(children: [
              LinearProgressIndicator(
                  value: _total == 0 ? 0 : _done / _total),
              const SizedBox(height: 6),
              Text('Sending $_done / $_total…',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.muted)),
            ])
          else
            ElevatedButton.icon(
                onPressed: _send,
                icon: const Icon(Icons.sms_outlined, size: 18),
                label: Text(
                    'Send to ${_recipients.length} officer(s)')),
          const SizedBox(height: 6),
          const Text(
            'Note: backend POST /notification/send-sms is stubbed server-side (see doc/API.md). '
            'This client sends the correct {to, message} payload per officer, so delivery lights up '
            'as soon as the backend is fixed or a gateway (Hubtel/Twilio) is wired.',
            style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final depts = BroadcastService.distinctDepartments(_officers);
    final chars = _msgCtrl.text.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        const PremiumHeader(
            title: 'Broadcast SMS',
            subtitle: 'One message to all staff, active officers, or a department.'),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (ctx, c) {
          final audience = _buildAudienceCard(depts);
          final message = _buildMessageCard(chars);
          if (c.maxWidth < 720) {
            return Column(
                children: [audience, const SizedBox(height: 12), message]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: audience),
              const SizedBox(width: 12),
              Expanded(child: message),
            ],
          );
        }),
        if (_last != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Last broadcast: ${_last!.sent} sent, ${_last!.failed} failed',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final r in _last!.results.take(50))
                  ListTile(
                    dense: true,
                    leading: Icon(
                        r.ok ? Icons.check_circle : Icons.error,
                        color: r.ok
                            ? AppColors.success
                            : AppColors.danger,
                        size: 20),
                    title: Text('${r.officerId} • ${r.phone}',
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(r.detail,
                        style: const TextStyle(fontSize: 11)),
                  ),
                if (_last!.results.length > 50)
                  Text('…and ${_last!.results.length - 50} more',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
