import 'dart:async';

import 'package:flutter/material.dart';

import '../services/local_job_access_history.dart';
import '../services/local_recent_records.dart';

mixin RecentRecordView<T extends StatefulWidget> on State<T> {
  (String, String, RecentRecord)? _recentView;

  void recordRecentView(String business, RecentRecord record) {
    final user = LocalJobAccessHistory.currentUserId;
    if (user == null ||
        record.id.isEmpty ||
        ModalRoute.isCurrentOf(context) != true ||
        _recentView == (business, user, record)) {
      return;
    }
    _recentView = (business, user, record);
    unawaited(
      LocalRecentRecords(
        business,
        user,
      ).record(record).catchError((Object _) {}),
    );
  }
}
