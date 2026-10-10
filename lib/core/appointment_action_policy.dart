/// Shared appointment action rules, independent of widget state.
/// Offline writes are disabled until an audited edit/delete queue exists.
class AppointmentActionPolicy {
  const AppointmentActionPolicy._();

  static bool canEdit({
    required bool onlineReady,
    required bool canManage,
    required bool isOwner,
    required bool linkedJob,
    required bool pending,
    required bool conflict,
  }) =>
      onlineReady &&
      canManage &&
      !pending &&
      !conflict &&
      (isOwner || !linkedJob);

  static bool canDelete({
    required bool onlineReady,
    required bool isOwner,
    required bool linkedJob,
    required bool linkedRequest,
    required bool pending,
    required bool conflict,
  }) =>
      onlineReady &&
      isOwner &&
      !linkedJob &&
      !linkedRequest &&
      !pending &&
      !conflict;
}
