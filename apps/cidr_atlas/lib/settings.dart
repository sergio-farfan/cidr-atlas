// CIDR Atlas
// Settings dialog with the appearance preference.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'theme.dart';

/// Opens Settings. The appearance choice applies as soon as it is selected.
Future<void> showAtlasSettings(
  BuildContext context,
  AppearanceController appearance,
) => showDialog<void>(
  context: context,
  builder: (_) => SettingsDialog(appearance: appearance),
);

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.appearance});
  final AppearanceController appearance;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  String? _saveError;

  Future<void> _select(AppearanceMode mode) async {
    setState(() => _saveError = null);
    try {
      await widget.appearance.setMode(mode);
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError =
              'Applied for this session, but the preference could not be '
              'saved: $error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      key: const ValueKey('settings-dialog'),
      title: const Text('Settings'),
      content: SizedBox(
        width: 420,
        child: ListenableBuilder(
          listenable: widget.appearance,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Appearance',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SegmentedButton<AppearanceMode>(
                key: const ValueKey('appearance-selector'),
                showSelectedIcon: false,
                segments: [
                  for (final mode in AppearanceMode.values)
                    ButtonSegment(
                      value: mode,
                      label: Text(mode.label),
                      icon: Icon(switch (mode) {
                        AppearanceMode.system => Icons.desktop_mac_outlined,
                        AppearanceMode.light => Icons.light_mode_outlined,
                        AppearanceMode.dark => Icons.dark_mode_outlined,
                      }, size: 17),
                    ),
                ],
                selected: {widget.appearance.mode},
                onSelectionChanged: (selection) => _select(selection.single),
              ),
              const SizedBox(height: 10),
              Text(
                'Controls the app\'s light or dark appearance. System follows '
                'the current macOS appearance.',
                style: TextStyle(color: p.textSecondary, fontSize: 12),
              ),
              if (_saveError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _saveError!,
                  style: TextStyle(color: p.danger, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
