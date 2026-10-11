/// Shared appointment action rules for Android and iOS Flutter screens.
/// Connectivity does not gate local-first changes; the sync queue does.
class AppointmentActionPolicy {
  const AppointmentActionPolicy._();

  static bool canEdit({
    required bool canManage,
    required bool isOwner,
    required bool linkedJob,
    required String status,
    required bool conflict,
  }) => canManage && !conflict &&
      (isOwner || (!linkedJob && status == 'confirmed'));

  static bool canCancel({
    required bool canManage,
    required bool linkedJob,
    required String status,
    required bool pending,
    required bool conflict,
  }) => canManage && !linkedJob && !pending && !conflict &&
      (status == 'confirmed' || status == 'tentative');

  static bool canDelete({
    required bool isOwner,
    required bool linkedJob,
    required bool linkedRequest,
    required bool pending,
    required bool conflict,
  }) => isOwner && !linkedJob && !linkedRequest &&
      !pending && !conflict;
}
