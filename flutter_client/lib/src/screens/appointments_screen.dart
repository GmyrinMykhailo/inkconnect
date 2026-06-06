import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../utils/auto_refresh.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/profile_image.dart';

enum AppointmentStatus { pending, confirmed, cancelled }

enum RecommendationState { none, ready, approved }

enum AppointmentFilter { all, pending, confirmed, cancelled }

class AppointmentItem {
  const AppointmentItem({
    required this.id,
    required this.artistId,
    required this.artistUsername,
    required this.artistName,
    required this.artistImage,
    required this.artistAvatarUrl,
    required this.city,
    required this.date,
    required this.time,
    required this.sessionDuration,
    required this.service,
    required this.status,
    required this.recommendationState,
    required this.stepsDone,
    required this.stepsTotal,
    required this.createdLabel,
    this.journalId = 'journal',
    this.artistIsMaster = true,
    this.showArtistFullName = true,
    this.isBackendBacked = false,
  });

  final String id;
  final String artistId;
  final String artistUsername;
  final String artistName;
  final String artistImage;
  final String artistAvatarUrl;
  final String city;
  final String date;
  final String time;
  final String sessionDuration;
  final String service;
  final AppointmentStatus status;
  final RecommendationState recommendationState;
  final int stepsDone;
  final int stepsTotal;
  final String createdLabel;
  final String journalId;
  final bool artistIsMaster;
  final bool showArtistFullName;
  final bool isBackendBacked;

  double get progress => stepsTotal == 0 ? 0 : stepsDone / stepsTotal;

  bool get hasRealJournalId {
    final value = journalId.trim();
    return value.isNotEmpty &&
        value != 'journal' &&
        value != 'mock' &&
        !value.startsWith('journal-');
  }

  String get journalRouteId {
    if (isBackendBacked) {
      return hasRealJournalId ? journalId.trim() : '';
    }
    final value = journalId.trim();
    return value.isEmpty ? 'journal' : value;
  }

  String get artistHandle =>
      artistUsername.startsWith('@') ? artistUsername : '@$artistUsername';

  AppointmentItem copyWith({
    RecommendationState? recommendationState,
    String? journalId,
  }) {
    return AppointmentItem(
      id: id,
      artistId: artistId,
      artistUsername: artistUsername,
      artistName: artistName,
      artistImage: artistImage,
      artistAvatarUrl: artistAvatarUrl,
      city: city,
      date: date,
      time: time,
      sessionDuration: sessionDuration,
      service: service,
      status: status,
      recommendationState: recommendationState ?? this.recommendationState,
      stepsDone: stepsDone,
      stepsTotal: stepsTotal,
      createdLabel: createdLabel,
      journalId: journalId ?? this.journalId,
      artistIsMaster: artistIsMaster,
      showArtistFullName: showArtistFullName,
      isBackendBacked: isBackendBacked,
    );
  }
}

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({
    super.key,
    required this.user,
    required this.userName,
    this.api,
    this.sessionToken,
    this.onCountsChanged,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenProfile,
    required this.onOpenAccountProfile,
    required this.onOpenRecommendationApproval,
    required this.onOpenRecommendations,
    required this.approvedRecommendationIds,
    required this.approvedRecommendationJournalIds,
  });

  final AuthUser? user;
  final String userName;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final ValueChanged<AppointmentCounts>? onCountsChanged;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenProfile;
  final void Function(String username, bool isMaster) onOpenAccountProfile;
  final ValueChanged<String> onOpenRecommendationApproval;
  final VoidCallback onOpenRecommendations;
  final Set<String> approvedRecommendationIds;
  final Map<String, String> approvedRecommendationJournalIds;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late final AutoRefreshController _autoRefresh;
  AppointmentFilter _filter = AppointmentFilter.all;
  List<AppointmentItem>? _backendItems;
  AppointmentCounts? _backendCounts;
  bool _loading = false;
  String? _loadError;

  static const _background = AuthenticatedDashboardTheme.background;
  static const _card = AuthenticatedDashboardTheme.card;
  static const _accent = AuthenticatedDashboardTheme.accent;
  static const _text = AuthenticatedDashboardTheme.text;
  static const _muted = AuthenticatedDashboardTheme.muted;
  static const _line = AuthenticatedDashboardTheme.line;
  static const _soft = AuthenticatedDashboardTheme.soft;

  List<AppointmentItem> get _visibleItems {
    final source = _backendItems ?? const <AppointmentItem>[];
    return source.map(_withApprovedRecommendations).where((item) {
      return switch (_filter) {
        AppointmentFilter.all => true,
        AppointmentFilter.pending => item.status == AppointmentStatus.pending,
        AppointmentFilter.confirmed =>
          item.status == AppointmentStatus.confirmed,
        AppointmentFilter.cancelled =>
          item.status == AppointmentStatus.cancelled,
      };
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _autoRefresh = AutoRefreshController(
      interval: const Duration(seconds: 12),
      onRefresh: () => _loadAppointments(silent: true),
    )..start();
    _loadAppointments();
  }

  @override
  void didUpdateWidget(covariant AppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken) {
      _loadAppointments();
    }
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  Future<void> _loadAppointments({bool silent = false}) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      if (silent) {
        return;
      }
      setState(() {
        _backendItems = const <AppointmentItem>[];
        _backendCounts = AppointmentCounts.empty();
        _loading = false;
        _loadError = 'Не удалось загрузить записи: нет активной backend-сессии.';
      });
      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final response = await api.clientAppointments(token);
      if (!mounted) {
        return;
      }
      setState(() {
        _backendItems = response.items.map(_appointmentFromBackend).toList();
        _backendCounts = response.counts;
        _loading = false;
        _loadError = null;
      });
      widget.onCountsChanged?.call(response.counts);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _backendItems = const <AppointmentItem>[];
        _backendCounts = AppointmentCounts.empty();
        _loading = false;
        _loadError = 'Не удалось загрузить записи: $error';
      });
    }
  }

  AppointmentItem _appointmentFromBackend(AppointmentRecord record) {
    final scheduledAt = _parseDate(record.scheduledAt);
    final scheduledEndAt = _parseOptionalDate(record.scheduledEndAt);
    final createdAt = _parseDate(record.createdAt);
    final status = record.status.trim();
    final artistName = record.master.displayName.trim().isNotEmpty
        ? record.master.displayName.trim()
        : '@${record.master.username}';
    final recommendationState =
        _recommendationState(record.recommendationStatus);
    return AppointmentItem(
      id: record.id,
      artistId: record.master.id,
      artistUsername: record.master.username,
      artistName: artistName,
      artistImage: AuthenticatedDashboardTheme.appointmentImage,
      artistAvatarUrl: record.master.avatarUrl,
      city: record.master.city.trim().isEmpty ? 'Город скрыт' : record.master.city,
      date: _dateLabelFromDateTime(scheduledAt),
      time: _timeRangeLabel(record, scheduledAt, scheduledEndAt),
      sessionDuration: _durationLabel(record),
      service: record.service.name,
      status: _clientStatus(status),
      recommendationState: recommendationState,
      stepsDone: record.journalStepsDone,
      stepsTotal: record.journalStepsTotal > 0
          ? record.journalStepsTotal
          : record.recommendationStepsCount,
      createdLabel: _createdLabelForStatus(status, createdAt),
      journalId: record.journalId,
      artistIsMaster: record.master.isMaster,
      showArtistFullName: !artistName.startsWith('@'),
      isBackendBacked: true,
    );
  }

  AppointmentStatus _clientStatus(String status) {
    if (status == 'confirmed' || status == 'completed') {
      return AppointmentStatus.confirmed;
    }
    if (status == 'rejected' || status == 'cancelled') {
      return AppointmentStatus.cancelled;
    }
    return AppointmentStatus.pending;
  }

  RecommendationState _recommendationState(String status) {
    if (status == 'approved') {
      return RecommendationState.approved;
    }
    if (status == 'sent') {
      return RecommendationState.ready;
    }
    return RecommendationState.none;
  }

  DateTime _parseDate(String value) {
    return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
  }

  DateTime? _parseOptionalDate(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }

  String _dateLabelFromDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _timeLabel(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _timeRangeLabel(
    AppointmentRecord record,
    DateTime scheduledAt,
    DateTime? scheduledEndAt,
  ) {
    final end = scheduledEndAt ?? _endFromDuration(record, scheduledAt);
    if (end == null) {
      return _timeLabel(scheduledAt);
    }
    return '${_timeLabel(scheduledAt)} — ${_timeLabel(end)}';
  }

  String _createdLabelForStatus(String status, DateTime createdAt) {
    final createdLabel = _dateLabelFromDateTime(createdAt);
    switch (status) {
      case 'confirmed':
        return 'Запись подтверждена · создана: $createdLabel';
      case 'rejected':
        return 'Запись отклонена · создана: $createdLabel';
      case 'cancelled':
        return 'Запись отменена · создана: $createdLabel';
      case 'completed':
        return 'Сеанс завершён · создана: $createdLabel';
      default:
        return 'Запись создана: $createdLabel';
    }
  }

  DateTime? _endFromDuration(AppointmentRecord record, DateTime scheduledAt) {
    if (record.durationMinutes > 0) {
      return scheduledAt.add(Duration(minutes: record.durationMinutes));
    }
    final hours = record.service.durationHours;
    if (hours != null && hours > 0) {
      return scheduledAt.add(Duration(minutes: (hours * 60).round()));
    }
    return null;
  }

  String _durationLabel(AppointmentRecord record) {
    var minutes = record.durationMinutes;
    if (minutes <= 0) {
      final start = _parseOptionalDate(record.scheduledAt);
      final end = _parseOptionalDate(record.scheduledEndAt);
      if (start != null && end != null) {
        minutes = end.difference(start).inMinutes;
      }
    }
    if (minutes <= 0 && record.service.durationHours != null) {
      minutes = (record.service.durationHours! * 60).round();
    }
    if (minutes <= 0) {
      return '1 час';
    }
    if (minutes < 60) {
      return '$minutes мин';
    }
    if (minutes % 60 == 0) {
      return '${minutes ~/ 60} ч';
    }
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(1)} ч';
  }

  AppointmentItem _withApprovedRecommendations(AppointmentItem item) {
    final journalId = widget.approvedRecommendationJournalIds[item.id] ?? '';
    if (!widget.approvedRecommendationIds.contains(item.id) &&
        journalId.isEmpty) {
      return item;
    }
    return item.copyWith(
      recommendationState: RecommendationState.approved,
      journalId: journalId.isEmpty ? null : journalId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedPageShell(
      user: widget.user,
      userName: widget.userName,
      activeSidebarItem: AuthenticatedSidebarItem.appointments,
      activeMobileNavItem: AuthenticatedMobileNavItem.home,
      onOpenHome: widget.onOpenHome,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: () {},
      onOpenMasterAppointments: widget.onOpenMasterAppointments,
      onOpenMessages: () => widget.onOpenChat('messages'),
      onOpenCareJournal: () => widget.onOpenCareJournal('journal'),
      onOpenClientJournals: widget.onOpenClientJournals,
      onOpenServicesPrices: widget.onOpenServicesPrices,
      onOpenRecommendations: widget.onOpenRecommendations,
      onOpenProfile: widget.onOpenProfile,
      onMockAction: _showMockAction,
      bodyBuilder: (context, isDesktop) {
        return _AppointmentsContent(
          items: _visibleItems,
          loading: _loading,
          errorText: _loadError,
          selectedFilter: _filter,
          isDesktop: isDesktop,
          counts: _filterCounts,
          onSelectFilter: _setFilter,
          onOpenFilters: _openFilterSheet,
          onOpenChat: widget.onOpenChat,
          onOpenCareJournal: widget.onOpenCareJournal,
          onOpenRecommendationApproval: widget.onOpenRecommendationApproval,
          onOpenAccountProfile: widget.onOpenAccountProfile,
          onCardMenu: _handleCardMenu,
          onRetry: () => _loadAppointments(),
        );
      },
    );
  }

  void _setFilter(AppointmentFilter filter) {
    setState(() => _filter = filter);
  }

  Map<AppointmentFilter, int> get _filterCounts {
    final counts = _backendCounts;
    if (counts != null) {
      return {
        AppointmentFilter.all: counts.all,
        AppointmentFilter.pending: counts.pending,
        AppointmentFilter.confirmed: counts.confirmed,
        AppointmentFilter.cancelled: counts.inactive,
      };
    }

    final source = _backendItems ?? const <AppointmentItem>[];
    return {
      for (final filter in AppointmentFilter.values)
        filter: source.where((item) {
          return switch (filter) {
            AppointmentFilter.all => true,
            AppointmentFilter.pending =>
              item.status == AppointmentStatus.pending,
            AppointmentFilter.confirmed =>
              item.status == AppointmentStatus.confirmed,
            AppointmentFilter.cancelled =>
              item.status == AppointmentStatus.cancelled,
          };
        }).length,
    };
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Фильтр записей',
                  style: const TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                for (final filter in AppointmentFilter.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_filterLabel(filter)),
                    trailing: _filter == filter
                        ? const Icon(Icons.check, color: _accent)
                        : null,
                    onTap: () {
                      Navigator.of(context).pop();
                      _setFilter(filter);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleCardMenu(String action) {
    _showMockAction(action);
  }

  void _showMockAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _AppointmentsContent extends StatelessWidget {
  const _AppointmentsContent({
    required this.items,
    required this.loading,
    required this.errorText,
    required this.selectedFilter,
    required this.isDesktop,
    required this.counts,
    required this.onSelectFilter,
    required this.onOpenFilters,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenRecommendationApproval,
    required this.onOpenAccountProfile,
    required this.onCardMenu,
    required this.onRetry,
  });

  final List<AppointmentItem> items;
  final bool loading;
  final String? errorText;
  final AppointmentFilter selectedFilter;
  final bool isDesktop;
  final Map<AppointmentFilter, int> counts;
  final ValueChanged<AppointmentFilter> onSelectFilter;
  final VoidCallback onOpenFilters;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final ValueChanged<String> onOpenRecommendationApproval;
  final void Function(String username, bool isMaster) onOpenAccountProfile;
  final ValueChanged<String> onCardMenu;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      isDesktop ? 40 : 16,
      isDesktop ? 36 : 24,
      isDesktop ? 40 : 16,
      isDesktop ? 42 : 104,
    );

    return SingleChildScrollView(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Мои записи',
                          style: const TextStyle(
                            color: _AppointmentsScreenState._text,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Здесь вы можете просмотреть и управлять своими записями',
                          style: const TextStyle(
                            color: _AppointmentsScreenState._muted,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isDesktop)
                    IconButton(
                      onPressed: onOpenFilters,
                      icon: const Icon(Icons.tune),
                    ),
                ],
              ),
              if (loading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (errorText != null) ...[
                const SizedBox(height: 14),
                _BackendErrorState(message: errorText!, onRetry: onRetry),
              ],
              const SizedBox(height: 26),
              _AppointmentsToolbar(
                selectedFilter: selectedFilter,
                isDesktop: isDesktop,
                counts: counts,
                onSelectFilter: onSelectFilter,
                onOpenFilters: onOpenFilters,
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Column(
                  key: ValueKey(selectedFilter),
                  children: [
                    if (items.isEmpty)
                      const _AppointmentsEmptyState()
                    else
                      for (final item in items) ...[
                        _AppointmentCard(
                          item: item,
                          isDesktop: isDesktop,
                          onOpenChat: () => onOpenChat(
                            item.artistId.trim().isEmpty
                                ? 'messages'
                                : item.artistId,
                          ),
                          onOpenCareJournal: () {
                            final journalId = item.journalRouteId;
                            if (journalId.isEmpty) {
                              return;
                            }
                            onOpenCareJournal(
                              item.isBackendBacked
                                  ? 'appointment:${item.id}'
                                  : journalId,
                            );
                          },
                          onOpenRecommendationApproval: () =>
                              onOpenRecommendationApproval(item.id),
                          onOpenAccountProfile: () =>
                              onOpenAccountProfile(
                                item.artistUsername,
                                item.artistIsMaster,
                              ),
                          onMenuSelected: onCardMenu,
                        ),
                        const SizedBox(height: 14),
                      ],
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        items.isEmpty
                            ? 'Попробуйте выбрать другой фильтр'
                            : 'Это все ваши записи',
                        style: const TextStyle(
                          color: _AppointmentsScreenState._muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackendErrorState extends StatelessWidget {
  const _BackendErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF2D48A)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 22,
            color: Color(0xFF9A6700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF7A4D00),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

class _AppointmentsToolbar extends StatelessWidget {
  const _AppointmentsToolbar({
    required this.selectedFilter,
    required this.isDesktop,
    required this.counts,
    required this.onSelectFilter,
    required this.onOpenFilters,
  });

  final AppointmentFilter selectedFilter;
  final bool isDesktop;
  final Map<AppointmentFilter, int> counts;
  final ValueChanged<AppointmentFilter> onSelectFilter;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final filters = AppointmentFilter.values;
    final chips = filters.map((filter) {
      return _FilterChipButton(
        label: _filterLabel(filter),
        count: counts[filter] ?? 0,
        selected: selectedFilter == filter,
        onTap: () => onSelectFilter(filter),
      );
    }).toList();

    if (!isDesktop) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: chips),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Wrap(spacing: 14, runSpacing: 10, children: chips),
        ),
        _FilterButton(onTap: onOpenFilters),
      ],
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? _AppointmentsScreenState._accent : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? _AppointmentsScreenState._accent
                    : _AppointmentsScreenState._line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : _AppointmentsScreenState._text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.16)
                        : _AppointmentsScreenState._soft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : _AppointmentsScreenState._muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.tune, size: 18),
      label: const Text('Все записи'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _AppointmentsScreenState._text,
        side: const BorderSide(color: _AppointmentsScreenState._line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(150, 42),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.item,
    required this.isDesktop,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenRecommendationApproval,
    required this.onOpenAccountProfile,
    required this.onMenuSelected,
  });

  final AppointmentItem item;
  final bool isDesktop;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenCareJournal;
  final VoidCallback onOpenRecommendationApproval;
  final VoidCallback onOpenAccountProfile;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _AppointmentsScreenState._card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onMenuSelected('Открыта запись ${item.artistName}'),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(isDesktop ? 18 : 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _AppointmentsScreenState._line),
            boxShadow: AuthenticatedDashboardTheme.cardShadow(),
          ),
          child: isDesktop ? _desktopLayout() : _mobileLayout(),
        ),
      ),
    );
  }

  Widget _desktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AppointmentImage(
          assetPath: item.artistImage,
          avatarUrl: item.artistAvatarUrl,
          size: 154,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _AppointmentMainInfo(
            item: item,
            onOpenAccountProfile: onOpenAccountProfile,
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 380,
          child: _AppointmentActions(
            item: item,
            isDesktop: true,
            onOpenChat: onOpenChat,
            onOpenCareJournal: onOpenCareJournal,
            onOpenRecommendationApproval: onOpenRecommendationApproval,
          ),
        ),
        _AppointmentMenu(onSelected: onMenuSelected),
      ],
    );
  }

  Widget _mobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppointmentImage(
              assetPath: item.artistImage,
              avatarUrl: item.artistAvatarUrl,
              size: 88,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AppointmentMainInfo(
                item: item,
                compact: true,
                onOpenAccountProfile: onOpenAccountProfile,
              ),
            ),
            _AppointmentMenu(onSelected: onMenuSelected),
          ],
        ),
        const SizedBox(height: 14),
        _AppointmentActions(
          item: item,
          isDesktop: false,
          onOpenChat: onOpenChat,
          onOpenCareJournal: onOpenCareJournal,
          onOpenRecommendationApproval: onOpenRecommendationApproval,
        ),
      ],
    );
  }
}

class _AppointmentMainInfo extends StatelessWidget {
  const _AppointmentMainInfo({
    required this.item,
    required this.onOpenAccountProfile,
    this.compact = false,
  });

  final AppointmentItem item;
  final VoidCallback onOpenAccountProfile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onOpenAccountProfile,
            child: Text(
              item.artistHandle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _AppointmentsScreenState._text,
                fontSize: compact ? 15 : 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (item.showArtistFullName) ...[
          const SizedBox(height: 4),
          Text(
            item.artistName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _AppointmentsScreenState._muted,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _InfoRow(icon: Icons.location_on_outlined, text: item.city),
        const SizedBox(height: 8),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            _InfoRow(icon: Icons.calendar_today_outlined, text: item.date),
            _InfoRow(icon: Icons.schedule, text: item.time),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaPill('Сеанс: ${item.sessionDuration}'),
            _MetaPill(item.service),
          ],
        ),
      ],
    );
  }
}

class _AppointmentActions extends StatelessWidget {
  const _AppointmentActions({
    required this.item,
    required this.isDesktop,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenRecommendationApproval,
  });

  final AppointmentItem item;
  final bool isDesktop;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenCareJournal;
  final VoidCallback onOpenRecommendationApproval;

  @override
  Widget build(BuildContext context) {
    final isConfirmed = item.status == AppointmentStatus.confirmed;
    final canApproveRecommendations =
        isConfirmed && item.recommendationState == RecommendationState.ready;
    final canOpenCareJournal =
        isConfirmed && item.recommendationState == RecommendationState.approved;
    final hasJournalRoute = item.journalRouteId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBadge(status: item.status),
        const SizedBox(height: 10),
        Text(
          item.createdLabel,
          style: const TextStyle(
            color: _AppointmentsScreenState._muted,
            fontSize: 12,
          ),
        ),
        if (canOpenCareJournal) ...[
          const SizedBox(height: 16),
          const Text(
            'Прогресс ухода',
            style: const TextStyle(
              color: _AppointmentsScreenState._text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.stepsDone} из ${item.stepsTotal} шагов выполнено',
            style: const TextStyle(
              color: _AppointmentsScreenState._muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    minHeight: 6,
                    backgroundColor: _AppointmentsScreenState._line,
                    color: _AppointmentsScreenState._accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${(item.progress * 100).round()}%'),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (isDesktop)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionButton(
                icon: Icons.chat_bubble_outline,
                label: 'Написать мастеру',
                onTap: onOpenChat,
              ),
              if (canApproveRecommendations)
                _ActionButton(
                  icon: Icons.fact_check_outlined,
                  label: 'Подтвердить рекомендации',
                  onTap: onOpenRecommendationApproval,
                ),
              if (canOpenCareJournal)
                _ActionButton(
                  icon: Icons.menu_book_outlined,
                  label:
                      hasJournalRoute ? 'Открыть журнал ухода' : 'Журнал ещё не создан',
                  onTap: hasJournalRoute ? onOpenCareJournal : null,
                ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ActionButton(
                icon: Icons.chat_bubble_outline,
                label: 'Написать мастеру',
                onTap: onOpenChat,
              ),
              if (canApproveRecommendations) ...[
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.fact_check_outlined,
                  label: 'Подтвердить рекомендации',
                  onTap: onOpenRecommendationApproval,
                ),
              ],
              if (canOpenCareJournal) ...[
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.menu_book_outlined,
                  label:
                      hasJournalRoute ? 'Открыть журнал ухода' : 'Журнал ещё не создан',
                  onTap: hasJournalRoute ? onOpenCareJournal : null,
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _AppointmentsScreenState._accent,
        side: const BorderSide(color: _AppointmentsScreenState._line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(0, 42),
      ),
    );
  }
}

class _AppointmentMenu extends StatelessWidget {
  const _AppointmentMenu({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'Детали записи', child: Text('Детали записи')),
        PopupMenuItem(value: 'Перенести запись', child: Text('Перенести')),
        PopupMenuItem(value: 'Отменить запись', child: Text('Отменить')),
      ],
    );
  }
}

class _AppointmentImage extends StatelessWidget {
  const _AppointmentImage({
    required this.assetPath,
    required this.avatarUrl,
    required this.size,
  });

  final String assetPath;
  final String avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ProfileImage(
      avatarUrl: avatarUrl,
      fallbackAssetPath: assetPath,
      width: size,
      height: size,
      borderRadius: 12,
      fit: BoxFit.cover,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final data = switch (status) {
      AppointmentStatus.pending => (
          'Ожидает подтверждения',
          const Color(0xFFFFF4D8),
          const Color(0xFF9A6700)
        ),
      AppointmentStatus.confirmed => (
          'Подтверждена',
          const Color(0xFFEAF7EF),
          const Color(0xFF246B4F)
        ),
      AppointmentStatus.cancelled => (
          'Отменена',
          const Color(0xFFFFE7E7),
          const Color(0xFFD92D20)
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: data.$2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        data.$1,
        style: TextStyle(
          color: data.$3,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _AppointmentsScreenState._muted),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            color: _AppointmentsScreenState._muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _AppointmentsScreenState._soft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _AppointmentsScreenState._muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AppointmentsEmptyState extends StatelessWidget {
  const _AppointmentsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AppointmentsScreenState._line),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            color: _AppointmentsScreenState._muted,
            size: 42,
          ),
          SizedBox(height: 12),
          Text(
            'Записей не найдено',
            style: const TextStyle(
              color: _AppointmentsScreenState._text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _filterLabel(AppointmentFilter filter) {
  return switch (filter) {
    AppointmentFilter.all => 'Все записи',
    AppointmentFilter.pending => 'Ожидают подтверждения',
    AppointmentFilter.confirmed => 'Подтвержденные',
    AppointmentFilter.cancelled => 'Отмененные',
  };
}
