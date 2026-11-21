/// Conservative client-side display policy for Owner delete planning.
/// The server must independently revalidate under lock before any mutation.
class OwnerDeleteEligibility {
  const OwnerDeleteEligibility._();

  static bool canOfferDelete(Map<String, dynamic> plan, {
    required bool isOwner,
    required bool isOnline,
    required bool hasPendingLocalWork,
  }) {
    if (!isOwner || !isOnline || hasPendingLocalWork) return false;
    if (plan['can_delete'] != true) return false;
    // Server plans can evolve. Never infer that test or paid records are safe.
    final invoices = plan['invoices'];
    if (invoices is! List) return false;
    for (final invoice in invoices) {
      if (invoice is! Map) return false;
      final status = '${invoice['status'] ?? ''}'.toLowerCase();
      if (const {'paid', 'closed', 'void', 'cancelled'}.contains(status)) {
        return false;
      }
    }
    return true;
  }

  /// Number recycling is opt-in, never a side effect of showing a preview.
  /// Caller must still verify issuance history and reserve at the server.
  static bool canOfferNumberReclaim({
    required bool explicitlyRequested,
    required bool verifiedUnused,
    required bool serverReservationAvailable,
  }) => explicitlyRequested && verifiedUnused && serverReservationAvailable;
}
