/// Preserve the authenticated caller's role across invoice/customer/Job routes.
/// Legacy callers without a role fail closed instead of inheriting Office UI.
String documentNavigationRole({String? roleCode, required bool isOwner}) =>
    roleCode ?? (isOwner ? 'owner' : 'viewer');
