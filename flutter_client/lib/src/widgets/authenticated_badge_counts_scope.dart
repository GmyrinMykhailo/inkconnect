import 'package:flutter/widgets.dart';

import '../models.dart';

class AuthenticatedBadgeCounts {
  const AuthenticatedBadgeCounts({
    this.clientAppointments,
    this.masterAppointments,
    this.messagesUnread = 0,
  });

  final AppointmentCounts? clientAppointments;
  final AppointmentCounts? masterAppointments;
  final int messagesUnread;

  int? get clientAppointmentsBadge => clientAppointments?.all;

  int? get masterAppointmentsBadge {
    final counts = masterAppointments;
    if (counts == null) {
      return null;
    }
    return counts.pending + counts.confirmed;
  }

  int? get messagesBadge => messagesUnread > 0 ? messagesUnread : null;
}

class AuthenticatedBadgeCountsScope extends InheritedWidget {
  const AuthenticatedBadgeCountsScope({
    super.key,
    required this.counts,
    required super.child,
  });

  final AuthenticatedBadgeCounts counts;

  static AuthenticatedBadgeCounts? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AuthenticatedBadgeCountsScope>()
        ?.counts;
  }

  @override
  bool updateShouldNotify(AuthenticatedBadgeCountsScope oldWidget) {
    return counts != oldWidget.counts;
  }
}
