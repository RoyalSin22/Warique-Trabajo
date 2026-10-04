import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/dates.dart';
import '../../models/admin.dart';
import '../../state/session.dart';
import '../widgets/common.dart';

/// Opens a download URL. On the web the same tab is used: the file arrives as an attachment, so the
/// app stays on screen (a new tab opened after an `await` would be blocked as a popup). On Android
/// the browser downloads it to the phone's Downloads folder. Overridden in tests.
final downloadOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => kIsWeb
      ? launchUrl(uri, webOnlyWindowName: '_self')
      : launchUrl(uri, mode: LaunchMode.externalApplication),
);

enum _Range { thisMonth, lastMonth, custom }

Future<void> showExportSheet(BuildContext context, {DateTime? today}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ExportSheet(today: today ?? dateOnly(DateTime.now())),
);

/// CSV files for the accountant: they open in Excel or Google Sheets.
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key, required this.today});

  final DateTime today;

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  var _range = _Range.lastMonth;
  late DateTimeRange _custom = DateTimeRange(
    start: DateTime(widget.today.year, widget.today.month),
    end: widget.today,
  );
  ExportKind? _busy;

  DateTimeRange get _dates => switch (_range) {
    _Range.thisMonth => DateTimeRange(
      start: DateTime(widget.today.year, widget.today.month),
      end: widget.today,
    ),
    // Day 0 of this month = last day of the previous one (also across January)
    _Range.lastMonth => DateTimeRange(
      start: DateTime(widget.today.year, widget.today.month - 1),
      end: DateTime(widget.today.year, widget.today.month, 0),
    ),
    _Range.custom => _custom,
  };

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: widget.today,
      initialDateRange: _custom,
    );
    if (picked == null) return;
    if (picked.duration.inDays >= 366) {
      if (mounted) showErrorSnack(context, 'Elige como máximo un año.');
      return;
    }
    setState(() {
      _custom = DateTimeRange(start: dateOnly(picked.start), end: dateOnly(picked.end));
      _range = _Range.custom;
    });
  }

  Future<void> _download(ExportKind kind) async {
    setState(() => _busy = kind);
    try {
      final dates = _dates;
      final link = await ref
          .read(adminRepositoryProvider)
          .exportLink(kind, from: dayKey(dates.start), to: dayKey(dates.end));
      final server = ref.read(currentSessionProvider).serverUrl;
      final opened = await ref.read(downloadOpenerProvider)(Uri.parse('$server${link.url}'));
      if (!mounted) return;
      if (opened) {
        showInfoSnack(context, 'Descargando ${link.fileName}');
      } else {
        showErrorSnack(context, 'No se pudo abrir el navegador para descargar.');
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = _dates;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Exportar para el contador', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Archivos CSV: se abren en Excel o Google Sheets. Los montos van sin "S/" para poder sumarlos.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Mes anterior'),
                  selected: _range == _Range.lastMonth,
                  onSelected: (_) => setState(() => _range = _Range.lastMonth),
                ),
                ChoiceChip(
                  label: const Text('Este mes'),
                  selected: _range == _Range.thisMonth,
                  onSelected: (_) => setState(() => _range = _Range.thisMonth),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: const Text('Elegir fechas'),
                  selected: _range == _Range.custom,
                  onSelected: (_) => _pickCustom(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Del ${shortDayLabel(dates.start)} ${dates.start.year} al ${shortDayLabel(dates.end)} ${dates.end.year}',
              style: theme.textTheme.titleSmall,
            ),
            const Divider(height: 24),
            for (final kind in ExportKind.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_view_outlined),
                title: Text(kind.label),
                subtitle: Text(kind.description),
                trailing: _busy == kind
                    ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                enabled: _busy == null,
                onTap: () => _download(kind),
              ),
          ],
        ),
      ),
    );
  }
}
