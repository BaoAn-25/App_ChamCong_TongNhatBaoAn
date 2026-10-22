import 'package:flutter/material.dart';

void message(BuildContext context, Object error) {
  final text = error.toString().replaceFirst(
    RegExp(r'^(Bad state: |Invalid argument\(s\): )'),
    '',
  );
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

class Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  const Section({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 380 ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(color: Color(0xFF637487)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: action),
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 38, color: Color(0xFF8094A5)),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ) ??
    false;

/// Owns and disposes form controllers; stays open when domain validation fails.
Future<void> editForm(
  BuildContext context, {
  required String title,
  required Map<String, String> fields,
  required Future<void> Function(Map<String, String>) save,
  Set<String> passwords = const {},
}) => showDialog<void>(
  context: context,
  builder: (_) => _EditDialog(
    title: title,
    fields: fields,
    save: save,
    passwords: passwords,
  ),
);

class _EditDialog extends StatefulWidget {
  final String title;
  final Map<String, String> fields;
  final Set<String> passwords;
  final Future<void> Function(Map<String, String>) save;
  const _EditDialog({
    required this.title,
    required this.fields,
    required this.save,
    required this.passwords,
  });
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final inputs = widget.fields.map(
    (k, v) => MapEntry(k, TextEditingController(text: v)),
  );
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in inputs.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextField(
                    controller: entry.value,
                    obscureText: widget.passwords.contains(entry.key),
                    enabled: !busy,
                    readOnly: entry.key.contains('yyyy-MM-dd'),
                    onTap: !entry.key.contains('yyyy-MM-dd')
                        ? null
                        : () async {
                            final initial =
                                DateTime.tryParse(entry.value.text) ??
                                DateTime.now();
                            final chosen = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (chosen != null && mounted) {
                              entry.value.text =
                                  '${chosen.year}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
                            }
                          },
                    textInputAction: TextInputAction.next,
                    keyboardType: entry.key.contains('Email')
                        ? TextInputType.emailAddress
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: entry.key.replaceAll(' (yyyy-MM-dd)', ''),
                      suffixIcon: entry.key.contains('yyyy-MM-dd')
                          ? const Icon(Icons.calendar_today_outlined)
                          : null,
                    ),
                    maxLines: entry.key.toLowerCase().contains('lý do') ? 4 : 1,
                  ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.save(
                      inputs.map(
                        (k, v) => MapEntry(
                          k,
                          widget.passwords.contains(k) ? v.text : v.text.trim(),
                        ),
                      ),
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) setState(() => error = e.toString());
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Đang lưu…' : 'Lưu'),
        ),
      ],
    ),
  );
}
