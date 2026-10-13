import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums.dart';
import '../../l10n/app_localizations.dart';
import 'home_providers.dart';

class CreateHomeScreen extends ConsumerStatefulWidget {
  const CreateHomeScreen({super.key});

  @override
  ConsumerState<CreateHomeScreen> createState() => _CreateHomeScreenState();
}

class _CreateHomeScreenState extends ConsumerState<CreateHomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  PropertyType _type = PropertyType.house;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(homeRepositoryProvider).createHome(
            name: _name.text,
            address: _address.text,
            propertyType: _type,
          );
      // HomeScreen switches to the room list once the stream emits the home.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l10n.createHomeTitle, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(l10n.createHomeIntro, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.homeNameLabel,
                  hintText: l10n.homeNameHint,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? l10n.nameRequired : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _address,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.homeAddressLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PropertyType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: l10n.propertyTypeLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final t in PropertyType.values)
                    DropdownMenuItem(value: t, child: Text(l10n.propertyTypeName(t.name))),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(l10n.createHomeButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
