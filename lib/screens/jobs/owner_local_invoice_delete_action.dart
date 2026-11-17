import 'package:flutter/material.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_invoice_delete.dart';
import '../../widgets/briskers_dialog.dart';

Future<bool> deleteOwnerLocalInvoice(BuildContext context, {
  required String businessId, required String invoiceId, required String number,
}) async {
  final grant = await DeviceOwnerAuthorization.instance.authority.authorizeSession(businessId);
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(context:context,builder:(dialog)=>BriskersDialog(
    title:'Delete invoice${number.isEmpty ? '' : ' #$number'}?',
    icon: Icons.delete_outline,
    content: const Text('Remove this selected invoice from the app? Its saved record and payment history will be retained in the local audit trail. The Job and other invoices will be kept.'),
    actions:[
      OutlinedButton(style:BriskersDialog.cancelStyle,onPressed:()=>Navigator.pop(dialog,false),child:const Text('Cancel')),
      FilledButton(style:BriskersDialog.confirmStyle(destructive:true),onPressed:()=>Navigator.pop(dialog,true),child:const Text('Delete')),
    ],
  ));
  if(confirmed != true) return false;
  await LocalInvoiceDelete(localDatabase).remove(businessId:businessId,invoiceId:invoiceId,ownerGrant:grant);
  return true;
}
