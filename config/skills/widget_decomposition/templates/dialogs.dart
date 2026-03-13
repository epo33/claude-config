// Template : fonctions de dialogue réutilisables pour un projet Flutter.
// Copier ce fichier dans lib/utils/dialogs.dart et adapter selon les besoins.

import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";

Future<void> showMessage(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showAdaptiveDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text("OK"),
        ),
      ],
    ),
  );
}

/// Shows a confirmation dialog and returns true if the user confirmed.
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = "Annuler",
  required String confirmLabel,
}) async {
  final result = await showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
