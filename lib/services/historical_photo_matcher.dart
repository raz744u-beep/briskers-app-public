class HistoricalPhotoMatch {
  const HistoricalPhotoMatch({
    required this.job,
    required this.file,
    required this.jobNumberKey,
  });

  final Map<String, dynamic> job;
  final Map<String, dynamic> file;
  final String jobNumberKey;
}

class HistoricalPhotoMatcher {
  const HistoricalPhotoMatcher();

  String jobNumberKey(Map<String, dynamic> job) {
    final number = job['job_number']?.toString().trim() ?? '';
    final matches = RegExp(r'\d+').allMatches(number).toList();
    if (matches.isEmpty) return '';
    return matches.last.group(0) ?? '';
  }

  String filePath(Map<String, dynamic> file) {
    final relative = file['relative_path']?.toString().trim() ?? '';
    final name = file['name']?.toString().trim() ?? '';
    return relative.isNotEmpty ? relative : name;
  }

  bool pathContainsJobNumber(String path, String jobNumberKey) {
    if (jobNumberKey.isEmpty) return false;
    final pattern = RegExp(
      '(^|[^0-9])' + RegExp.escape(jobNumberKey) + r'([^0-9]|$)',
      caseSensitive: false,
    );
    return pattern.hasMatch(path);
  }

  List<HistoricalPhotoMatch> exactMatches(
    List<Map<String, dynamic>> jobs,
    List<Map<String, dynamic>> files,
  ) {
    final completedJobs = jobs.where((job) {
      final status = job['status']?.toString().toLowerCase() ?? '';
      return status == 'completed';
    }).toList();

    final keyedJobs = <(Map<String, dynamic>, String)>[];
    for (final job in completedJobs) {
      final key = jobNumberKey(job);
      if (key.isNotEmpty) keyedJobs.add((job, key));
    }

    final matches = <HistoricalPhotoMatch>[];
    for (final file in files) {
      final path = filePath(file);
      if (path.isEmpty) continue;

      final found = keyedJobs.where(
        (entry) => pathContainsJobNumber(path, entry.$2),
      );
      if (found.length != 1) continue;
      final entry = found.single;
      matches.add(
        HistoricalPhotoMatch(
          job: entry.$1,
          file: file,
          jobNumberKey: entry.$2,
        ),
      );
    }
    return matches;
  }
}
