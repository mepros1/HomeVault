import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../core/router.dart';
import '../../data/analysis/analysis_runner.dart';
import '../../data/db/database.dart';
import '../../data/ocr/label_parser.dart';
import '../../data/settings/settings.dart';
import '../../l10n/app_localizations.dart';
import '../review/review_providers.dart';
import 'attachments_section.dart';

/// Item detail card (spec §3.5). Saving marks the item `user_edited` and
/// accepted. Attachments and on-device OCR are the next increment.
class ItemScreen extends ConsumerStatefulWidget {
  const ItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends ConsumerState<ItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _qty = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _estLow = TextEditingController();
  final _estHigh = TextEditingController();
  final _note = TextEditingController();
  ItemCategory _category = ItemCategory.other;
  ItemCondition? _condition;
  DateTime? _purchaseDate;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _brand, _model, _serial, _qty, _purchasePrice, _estLow, _estHigh, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(Item item) {
    _name.text = item.name;
    _brand.text = item.brand ?? '';
    _model.text = item.model ?? '';
    _serial.text = item.serial ?? '';
    _qty.text = '${item.qty}';
    _purchasePrice.text = _num(item.purchasePrice);
    _estLow.text = _num(item.estLow);
    _estHigh.text = _num(item.estHigh);
    _note.text = item.note ?? '';
    _category = item.category;
    _condition = item.condition;
    _purchaseDate = item.purchaseDate;
    _loaded = true;
  }

  static String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : '$v');

  static double? _parse(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());

  static String? _nullIfBlank(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _save(Item item) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final estHigh = _parse(_estHigh.text);
      await ref.read(reviewRepositoryProvider).saveEdits(
            item,
            ItemsCompanion(
              name: Value(_name.text.trim()),
              category: Value(_category),
              brand: Value(_nullIfBlank(_brand.text)),
              model: Value(_nullIfBlank(_model.text)),
              serial: Value(_nullIfBlank(_serial.text)),
              qty: Value(int.tryParse(_qty.text.trim()) ?? 1),
              condition: Value(_condition),
              purchaseDate: Value(_purchaseDate),
              purchasePrice: Value(_parse(_purchasePrice.text)),
              estLow: Value(_parse(_estLow.text)),
              estHigh: Value(estHigh),
              note: Value(_nullIfBlank(_note.text)),
              isHighValue: Value(AnalysisRunner.isHighValue(
                _category,
                estHigh ?? 0,
                ref.read(highValueThresholdProvider),
              )),
            ),
          );
      if (mounted) _close();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Item item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteItem),
        content: Text(l10n.deleteItemConfirm(item.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(reviewRepositoryProvider).delete(item);
    if (mounted) _close();
  }

  /// Back to the caller, or to the room list when opened via deep link.
  void _close() => context.canPop() ? context.pop() : context.go(Routes.home);

  /// OCR result from a label photo: offer the candidates, fill the fields.
  /// Nothing is saved until the user taps Save.
  Future<void> _applyLabel(LabelInfo info) async {
    final l10n = AppLocalizations.of(context)!;
    if (info.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.ocrNothingFound)));
      return;
    }
    final serial = info.serials.isEmpty
        ? null
        : await _chooseCandidate(l10n.ocrSerialTitle, info.serials.take(5).toList());
    if (!mounted) return;
    final model = info.models.isEmpty
        ? null
        : await _chooseCandidate(l10n.ocrModelTitle, info.models.take(5).toList());
    if (!mounted) return;
    setState(() {
      if (serial != null) _serial.text = serial;
      if (model != null) _model.text = model;
    });
  }

  Future<String?> _chooseCandidate(String title, List<String> candidates) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final c in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(c),
              child: Text(c, style: const TextStyle(fontFamily: 'monospace')),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ocrSkip),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final item = ref.watch(itemProvider(widget.itemId)).value;
    if (item == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (!_loaded) _load(item);

    final money = NumberFormat.simpleCurrency(name: item.currency, decimalDigits: 0);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.itemTitle),
        actions: [
          IconButton(
            onPressed: () => _delete(item),
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.deleteItem,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (item.isHighValue)
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.star_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.highValueExplainer(money.format(ref.watch(highValueThresholdProvider))),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (item.isHighValue) const SizedBox(height: 16),
            _field(_name, l10n.fieldName, validator: (v) => v!.trim().isEmpty ? l10n.nameRequired : null),
            DropdownButtonFormField<ItemCategory>(
              initialValue: _category,
              decoration: InputDecoration(labelText: l10n.fieldCategory, border: const OutlineInputBorder()),
              items: [
                for (final c in ItemCategory.values)
                  DropdownMenuItem(value: c, child: Text(l10n.categoryName(c.name))),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(_brand, l10n.fieldBrand)),
                const SizedBox(width: 12),
                Expanded(child: _field(_model, l10n.fieldModel)),
              ],
            ),
            _field(_serial, l10n.fieldSerial),
            Row(
              children: [
                Expanded(
                  child: _field(_qty, l10n.fieldQty, keyboard: TextInputType.number, validator: (v) {
                    final n = int.tryParse(v!.trim());
                    return n == null || n < 1 ? l10n.quantityInvalid : null;
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<ItemCondition?>(
                    initialValue: _condition,
                    decoration: InputDecoration(labelText: l10n.fieldCondition, border: const OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(value: null, child: Text(l10n.notSet)),
                      for (final c in ItemCondition.values)
                        DropdownMenuItem(value: c, child: Text(l10n.conditionName(c.name))),
                    ],
                    onChanged: (v) => setState(() => _condition = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(_estLow, l10n.fieldEstLow, keyboard: const TextInputType.numberWithOptions(decimal: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(_estHigh, l10n.fieldEstHigh,
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                    final low = _parse(_estLow.text);
                    final high = _parse(v!);
                    return low != null && high != null && high < low ? l10n.estimateInvalid : null;
                  }),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _field(_purchasePrice, l10n.fieldPurchasePrice,
                      keyboard: const TextInputType.numberWithOptions(decimal: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _purchaseDate ?? DateTime.now(),
                          firstDate: DateTime(1970),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => _purchaseDate = picked);
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _purchaseDate == null ? l10n.fieldPurchaseDate : dateFormat.format(_purchaseDate!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            _field(_note, l10n.fieldNote, maxLines: 3),
            const SizedBox(height: 8),
            AttachmentsSection(itemId: item.id, onLabelParsed: _applyLabel),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : () => _save(item),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: validator,
      ),
    );
  }
}
