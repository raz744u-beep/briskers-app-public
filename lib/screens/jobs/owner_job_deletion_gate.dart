import 'package:flutter/material.dart';

import '../../core/module_modal_theme.dart';
import '../../core/briskers_colors.dart';

import '../../core/briskers_i18n.dart';

/// The legacy invoice-cascade route remains permanently disabled.
/// Owner Job deletion uses OwnerJobRetirementService and the audited v2
/// server protocol instead. This flag must never enable the legacy endpoint.
class OwnerJobDeletionGate {
  static const enabled = false;
}

Future<void> showOwnerJobDeletionUnavailable(BuildContext context) {
  final spanish = BriskersLanguageController.instance.isSpanish;
  return showModuleDialog<void>(
    context: context,
    accent: BriskersColors.jobs,
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
