import 'package:flutter/material.dart';

import '../data/bureau_api_client.dart';
import 'theme.dart';
import 'widgets.dart';

String apiErrorText(Object error) => error is BureauApiException
    ? error.toString()
    : 'Не удалось выполнить запрос: $error';

void showApiError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(apiErrorText(error)),
      backgroundColor: BureauColors.red,
    ),
  );
}

void showApiSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: BureauColors.green),
  );
}

class ApiFutureBuilder<T> extends StatelessWidget {
  const ApiFutureBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.empty,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return NoticeCard(
            apiErrorText(snapshot.error!),
            color: BureauColors.red,
            background: BureauColors.redSoft,
            icon: Icons.cloud_off_rounded,
          );
        }
        final data = snapshot.requireData;
        if (data is Iterable && data.isEmpty && empty != null) return empty!;
        return builder(context, data);
      },
    );
  }
}

class ApiButton extends StatefulWidget {
  const ApiButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.outlined = false,
    this.icon,
  });

  final String label;
  final Future<void> Function() onPressed;
  final Color? backgroundColor;
  final bool outlined;
  final IconData? icon;

  @override
  State<ApiButton> createState() => _ApiButtonState();
}

class _ApiButtonState extends State<ApiButton> {
  bool _loading = false;

  Future<void> _run() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onPressed();
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _loading
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 19),
                const SizedBox(width: 8),
              ],
              Text(widget.label),
            ],
          );
    if (widget.outlined) {
      return OutlinedButton(onPressed: _loading ? null : _run, child: child);
    }
    return FilledButton(
      style: widget.backgroundColor == null
          ? null
          : FilledButton.styleFrom(backgroundColor: widget.backgroundColor),
      onPressed: _loading ? null : _run,
      child: child,
    );
  }
}
