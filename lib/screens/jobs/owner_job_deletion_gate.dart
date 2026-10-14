import 'package:flutter/material.dart';

import '../../core/briskers_i18n.dart';

/// Whole-Job deletion is intentionally disabled in this release. A client-side
/// flag is never authorization: future enablement also requires the audited
/// server contract and approved rollout. Never fall back to legacy deletion.
class OwnerJobDeletionGate {
  static const enabled = false;
}

Future<void> showOwnerJobDeletionUnavailable(BuildContext context) {
  final spanish = BriskersLanguageController.instance.isSpanish;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        spanish ? 'Eliminar trabajo no disponible' : 'Job deletion unavailable',
      ),
      content: Text(
        spanish
            ? 'La eliminación conjunta del trabajo y sus documentos está pendiente de la verificación de seguridad del servidor. Se conservarán los pagos, el historial y la numeración. No se ha eliminado nada.'
            : 'Deleting a Job together with its documents is awaiting server safety verification. Payments, history, and numbering will be preserved. Nothing has been deleted.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(spanish ? 'Entendido' : 'OK'),
        ),
      ],
    ),
  );
}
