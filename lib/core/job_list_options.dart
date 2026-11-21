/// Legacy query options retained for callers; Jobs uses All / latest activity.
enum JobListView { recent, active, all }

enum JobListSort { lastAccessed, lastModified, jobDate }

/// Kept in route PageStorage to restore status, search and paging per user.
/// Legacy view/sort fields are ignored by Jobs so saved settings cannot bring
/// back removed selectors or override latest-activity ordering.
class JobListPreferences {
  const JobListPreferences({
    this.view = JobListView.all,
    this.sort = JobListSort.lastModified,
    this.allSort = JobListSort.lastModified,
    this.status,
    this.search = '',
    this.visibleLimit = 30,
  });

  final JobListView view;
  final JobListSort sort;
  final JobListSort allSort;
  final String? status;
  final String search;
  final int visibleLimit;
}
