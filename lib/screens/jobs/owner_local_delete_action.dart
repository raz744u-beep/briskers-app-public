import 'package:flutter/material.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_job_graph_delete.dart';
import 'offline_job_purge_dialog.dart';

Future<bool> deleteOwnerLocalJob(BuildContext context,{
  required String businessId,required String jobId,required String label,
}) async {
  final grant=await DeviceOwnerAuthorization.instance.authority.authorizeLocal(businessId);
  final engine=LocalJobGraphDelete.ownerDirected(localDatabase,ownerGrant:grant);
  final rows=await engine.preview(businessId:businessId,jobId:jobId,actorId:grant.actorId);
  if(!context.mounted) return false;
  if(!await showOfflineJobPurgeConfirmation(context,jobLabel:label,items:rows)) return false;
  await engine.confirm(businessId:businessId,jobId:jobId,actorId:grant.actorId,reviewed:rows);
  return true;
}
