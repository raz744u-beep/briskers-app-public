/// Recent uses device-local, per-user opens; All is the complete activity history.
enum JobListView { recent, active, all }

enum JobListSort { lastAccessed, lastModified }

/// Kept in the route's PageStorage, so returning to Jobs restores the view but
/// a fresh app session still starts on Recent. Never shared between users.
class JobListPreferences {
  const JobListPreferences({
    this.view = JobListView.recent,
    this.sort = JobListSort.lastAccessed,
    this.status,
    this.search = '',
    this.visibleLimit = 30,
  });

  final JobListView view;
  final JobListSort sort;
  final String? status;
  final String search;
  final int visibleLimit;
}
