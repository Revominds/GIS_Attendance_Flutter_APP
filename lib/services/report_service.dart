// Roster PDF report service — builds a clean, print-ready roster PDF
// from attendance rows (clock-in / clock-out) and saves/shares it.
//
// Data shape expected (from AdminService.allAttendance / todayAttendance):
//   officer_id, full_name, date, check_in_time, check_out_time,
//   duration_minutes, is_open, department, status ...
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class RosterReportFilter {
  final String? officerId;
  final String? date; // YYYY-MM-DD
  final String? from;
  final String? to;
  const RosterReportFilter({this.officerId, this.date, this.from, this.to});

  String get label {
    final parts = <String>[];
    if (date != null && date!.isNotEmpty) parts.add('Date: $date');
    if (from != null && from!.isNotEmpty) parts.add('From $from to ${to ?? '—'}');
    if (officerId != null && officerId!.isNotEmpty) parts.add('Officer: $officerId');
    return parts.isEmpty ? 'All records' : parts.join('  •  ');
  }
}

class RosterReportService {
  static String _s(dynamic v) => (v ?? '').toString();

  static String _time(dynamic iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      return DateFormat('HH:mm').format(d);
    } catch (_) {
      return iso.toString();
    }
  }

  static String _dur(dynamic m) {
    final mins = m is num ? m.round() : int.tryParse('$m');
    if (mins == null) return '—';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  /// Build the PDF document bytes (preview + save share this path).
  static Future<List<int>> buildPdf({
    required List<Map<String, dynamic>> rows,
    required RosterReportFilter filter,
    String title = 'Attendance Roster',
  }) async {
    final doc = pw.Document();
    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final olive = PdfColor.fromHex('#2E4D2A');
    final gold = PdfColor.fromHex('#E1B12C');
    final muted = PdfColor.fromHex('#6E7A6C');

    final openCount = rows
        .where((r) => r['is_open'] == true || r['check_out_time'] == null)
        .length;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Column(children: [
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('GIS ATTENDANCE',
                          style: pw.TextStyle(
                              fontSize: 10,
                              color: muted,
                              fontWeight: pw.FontWeight.bold)),
                      pw.Text(title,
                          style: pw.TextStyle(
                              fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(filter.label,
                          style: pw.TextStyle(fontSize: 9, color: muted)),
                    ]),
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Generated $now',
                          style: pw.TextStyle(fontSize: 9, color: muted)),
                      pw.Text(
                          '${rows.length} records  •  $openCount still clocked in',
                          style: pw.TextStyle(fontSize: 9, color: muted)),
                    ]),
              ]),
          pw.SizedBox(height: 6),
          pw.Container(height: 3, color: gold),
          pw.SizedBox(height: 10),
        ]),
        footer: (ctx) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('GIS Staff Attendance System',
                  style: pw.TextStyle(fontSize: 8, color: muted)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: muted)),
            ]),
        build: (ctx) => [
          if (rows.isEmpty)
            pw.Center(
                child: pw.Padding(
                    padding: const pw.EdgeInsets.all(40),
                    child: pw.Text('No attendance records for this filter.',
                        style: pw.TextStyle(fontSize: 12, color: muted)))),
          if (rows.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: olive),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              rowDecoration: const pw.BoxDecoration(),
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColor(0.96, 0.97, 0.96)),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              headers: const [
                '#', 'Officer', 'ID', 'Date', 'Clock-in', 'Clock-out',
                'Duration', 'Status'
              ],
              data: [
                for (var i = 0; i < rows.length; i++)
                  () {
                    final r = rows[i];
                    final open = r['is_open'] == true ||
                        r['check_out_time'] == null;
                    final name = _s(r['full_name']).isEmpty
                        ? _s(r['officer_id'])
                        : _s(r['full_name']);
                    return [
                      '${i + 1}',
                      name,
                      _s(r['officer_id']),
                      _s(r['date']),
                      _time(r['check_in_time']),
                      _time(r['check_out_time']),
                      _dur(r['duration_minutes']),
                      open ? 'OPEN' : 'CLOSED',
                    ];
                  }(),
              ],
            ),
        ],
      ),
    );
    return doc.save();
  }

  static String fileName(RosterReportFilter f) {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final scope = (f.date?.isNotEmpty == true)
        ? f.date!
        : (f.from?.isNotEmpty == true ? '${f.from}_to_${f.to ?? 'now'}' : 'all');
    return 'roster_${scope}_$stamp.pdf';
  }

  /// Save to temp dir and return the file (for download/share/open).
  static Future<File> saveToFile(List<int> bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Preview via system print preview sheet.
  static Future<void> preview(List<int> bytes) async {
    await Printing.layoutPdf(
        onLayout: (_) async => bytes as dynamic, name: 'Roster report');
  }

  /// Share / download via OS share sheet.
  static Future<void> share(File file) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'GIS attendance roster'),
    );
  }
}
