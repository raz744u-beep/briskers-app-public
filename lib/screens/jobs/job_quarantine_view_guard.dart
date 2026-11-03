import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../local/local_database_provider.dart';
import '../../services/job_sync_service.dart';
import '../../services/local_job_quarantine.dart';
import '../../services/local_job_retirement.dart';

/// Covers the entire detail route, including already-open section dialogs.
/// Durable status is checked before showing the first frame of cached content.
class JobQuarantineViewGuard extends StatefulWidget {
  const JobQuarantineViewGuard({
    super.key,
    required this.businessId,
    required this.jobId,
    this.documentId,
    required this.child,
    required this.onBlocked,
    required this.onRestored,
    this.blockedLookup,
    this.quarantineEvents,
    this.syncEvents,
  });

  final String businessId;
  final String jobId;
  final String? documentId;
  final Widget child;
  final VoidCallback onBlocked;
  final VoidCallback onRestored;
  final Future<bool> Function()? blockedLookup;
  final Stream<({String businessId, Set<String> jobIds})>? quarantineEvents;
  final Stream<String>? syncEvents;

  @override
  State<JobQuarantineViewGuard> createState() => _JobQuarantineViewGuardState();
}

class _JobQuarantineViewGuardState extends State<JobQuarantineViewGuard>
    with WidgetsBindingObserver {
  StreamSubscription<({String businessId, Set<String> jobIds})>? _quarantine;
  StreamSubscription<String>? _sync;
  StreamSubscription<({String businessId, Set<String> jobIds})>? _retirement;
  var _checking = true;
  var _blocked = false;
  var _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _quarantine = (widget.quarantineEvents ?? LocalJobQuarantine.events).listen(
      (event) {
        if (event.businessId == widget.businessId &&
            event.jobIds.contains(widget.jobId)) {
          _block();
        }
      },
    );
    _sync = (widget.syncEvents ?? JobSyncService.syncEvents).listen((
      businessId,
    ) {
      // Document retirement has its own event stream below. Job sync
      // notifications must not repeatedly cancel a Document's first access
      // check while unrelated Jobs are refreshing.
      if (widget.documentId == null &&
          businessId == widget.businessId) {
        unawaited(_readStatus());
      }
    });
    _retirement = LocalJobRetirement.events.listen((event) {
      if (event.businessId == widget.businessId &&
          (widget.documentId != null || event.jobIds.contains(widget.jobId))) {
        unawaited(_readStatus());
      }
    });
    unawaited(_readStatus());
  }

  @override
  void didUpdateWidget(covariant JobQuarantineViewGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.jobId != widget.jobId ||
        oldWidget.documentId != widget.documentId) {
      _epoch++;
      _checking = true;
      unawaited(_readStatus());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readStatus());
  }

  Future<void> _readStatus() async {
    final epoch = ++_epoch;
    bool blocked;
    try {
      if (widget.blockedLookup != null) {
        blocked = await widget.blockedLookup!();
      } else if (widget.documentId != null) {
        // Document routes deliberately have no Job ID. The scoped
        // retirement check preserves exact invoice + linked Job fences
        // without scanning the entire shop or checking an empty Job ID.
        blocked = await LocalJobRetirement.isDocumentBlocked(
          localDatabase, widget.businessId, widget.documentId!);
      } else {
        blocked = await LocalJobQuarantine.isJobBlocked(
          localDatabase, widget.businessId, widget.jobId);
        if (!blocked) {
          blocked = await LocalJobRetirement.isJobBlocked(
            localDatabase, widget.businessId, widget.jobId);
        }
      }
    } catch (_) {
      blocked = true;
    }
    if (!mounted || epoch != _epoch) return;
    if (blocked) {
      _block();
    } else {
      final restored = _blocked;
      setState(() {
        _blocked = false;
        _checking = false;
      });
      if (restored) widget.onRestored();
    }
  }

  void _block() {
    if (!mounted) return;
    _epoch++;
    widget.onBlocked();
    setState(() {
      _blocked = true;
      _checking = false;
    });
    void dismissOverlays() {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        Navigator.of(context)
            .popUntil((candidate) => candidate == route || candidate.isFirst);
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => dismissOverlays());
    } else {
      dismissOverlays();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quarantine?.cancel();
    _sync?.cancel();
    _retirement?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checking && !_blocked) return widget.child;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentId == null ? 'Job' : 'Document'),
      ),
      body: Center(
        child: _checking
            ? const CircularProgressIndicator()
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Access changed or deletion is pending. Saved local work is preserved for review.',
                ),
              ),
      ),
    );
  }
}
