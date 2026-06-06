import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../utils/auto_refresh.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/profile_image.dart';

enum MasterAppointmentTab { upcoming, past, cancelled }

enum MasterAppointmentStatus {
  pending,
  confirmed,
  cancelled,
  recommendationsReady,
  journalCreated,
}

class MasterAppointmentItem {
  const MasterAppointmentItem({
    required this.id,
    required this.clientId,
    required this.clientUsername,
    required this.clientName,
    required this.clientImage,
    required this.clientAvatarUrl,
    required this.service,
    required this.date,
    required this.startHour,
    required this.startMinute,
    required this.durationHours,
    required this.status,
    required this.tab,
    required this.note,
    this.endTimeOverride,
    this.durationLabelOverride,
    this.journalId = '',
    this.clientIsMaster = false,
    this.showClientFullName = true,
    this.isBackendBacked = false,
  });

  final String id;
  final String clientId;
  final String clientUsername;
  final String clientName;
  final String clientImage;
  final String clientAvatarUrl;
  final String service;
  final String date;
  final int startHour;
  final int startMinute;
  final int durationHours;
  final MasterAppointmentStatus status;
  final MasterAppointmentTab tab;
  final String note;
  final String? endTimeOverride;
  final String? durationLabelOverride;
  final String journalId;
  final bool clientIsMaster;
  final bool showClientFullName;
  final bool isBackendBacked;

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

  String get clientHandle =>
      clientUsername.startsWith('@') ? clientUsername : '@$clientUsername';

  String get clientPublicName => showClientFullName ? clientName : clientHandle;

  String get startTime => _formatTime(startHour, startMinute);

  String get endTime =>
      endTimeOverride ?? _formatTime(startHour + durationHours, startMinute);

  String get timeRange => '$startTime — $endTime';

  String get durationLabel {
    if (durationLabelOverride != null && durationLabelOverride!.isNotEmpty) {
      return durationLabelOverride!;
    }
    if (durationHours == 1) {
      return '1 час';
    }
    if (durationHours >= 2 && durationHours <= 4) {
      return '$durationHours часа';
    }
    return '$durationHours часов';
  }

  MasterAppointmentItem copyWith({
    int? durationHours,
    MasterAppointmentStatus? status,
    MasterAppointmentTab? tab,
    String? note,
    String? endTimeOverride,
    String? durationLabelOverride,
  }) {
    return MasterAppointmentItem(
      id: id,
      clientId: clientId,
      clientUsername: clientUsername,
      clientName: clientName,
      clientImage: clientImage,
      clientAvatarUrl: clientAvatarUrl,
      service: service,
      date: date,
      startHour: startHour,
      startMinute: startMinute,
      durationHours: durationHours ?? this.durationHours,
      status: status ?? this.status,
      tab: tab ?? this.tab,
      note: note ?? this.note,
      endTimeOverride: endTimeOverride ?? this.endTimeOverride,
      durationLabelOverride: durationLabelOverride ?? this.durationLabelOverride,
      journalId: journalId,
      clientIsMaster: clientIsMaster,
      showClientFullName: showClientFullName,
      isBackendBacked: isBackendBacked,
    );
  }

  static String _formatTime(int hour, int minute) {
    final safeHour = hour % 24;
    final h = safeHour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class MasterAppointmentsScreen extends StatefulWidget {
  const MasterAppointmentsScreen({
    super.key,
    required this.user,
    required this.userName,
    this.api,
    this.sessionToken,
    this.onCountsChanged,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenOwnCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenProfile,
    required this.onOpenRecommendations,
    required this.onOpenAccountProfile,
    required this.onCreateRecommendations,
  });

  final AuthUser? user;
  final String userName;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final ValueChanged<AppointmentCounts>? onCountsChanged;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenOwnCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRecommendations;
  final void Function(String username, bool isMaster) onOpenAccountProfile;
  final ValueChanged<String> onCreateRecommendations;

  @override
  State<MasterAppointmentsScreen> createState() =>
      _MasterAppointmentsScreenState();
}

class _MasterAppointmentsScreenState extends State<MasterAppointmentsScreen> {
  late final AutoRefreshController _autoRefresh;
  MasterAppointmentTab _tab = MasterAppointmentTab.upcoming;
  String _query = '';
  List<MasterAppointmentItem> _items = const <MasterAppointmentItem>[];
  bool _loading = false;
  String? _loadError;

  static const _background = AuthenticatedDashboardTheme.background;
  static const _accent = AuthenticatedDashboardTheme.accent;
  static const _text = AuthenticatedDashboardTheme.text;
  static const _muted = AuthenticatedDashboardTheme.muted;
  static const _line = AuthenticatedDashboardTheme.line;
  static const _soft = AuthenticatedDashboardTheme.soft;

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
  void didUpdateWidget(covariant MasterAppointmentsScreen oldWidget) {
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

  bool get _isMaster => widget.user?.role == 'master';

  List<MasterAppointmentItem> get _visibleItems {
    final normalized = _query.trim().toLowerCase();
    return _items.where((item) {
      final matchesTab = item.tab == _tab;
      final searchableName = item.showClientFullName ? item.clientName : '';
      final matchesSearch = normalized.isEmpty ||
          item.clientUsername.toLowerCase().contains(normalized) ||
          item.clientHandle.toLowerCase().contains(normalized) ||
          searchableName.toLowerCase().contains(normalized) ||
          item.service.toLowerCase().contains(normalized);
      return matchesTab && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMaster) {
      return _MasterOnlyScreen(onBack: widget.onOpenHome);
    }

    return AuthenticatedPageShell(
      user: widget.user,
      userName: widget.userName,
      activeSidebarItem: AuthenticatedSidebarItem.masterAppointments,
      activeMobileNavItem: AuthenticatedMobileNavItem.home,
      onOpenHome: widget.onOpenHome,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: widget.onOpenAppointments,
      onOpenMasterAppointments: () {},
      onOpenMessages: () => widget.onOpenChat('messages'),
      onOpenCareJournal: widget.onOpenOwnCareJournal,
      onOpenClientJournals: widget.onOpenClientJournals,
      onOpenServicesPrices: widget.onOpenServicesPrices,
      onOpenRecommendations: widget.onOpenRecommendations,
      onOpenProfile: widget.onOpenProfile,
      onMockAction: _showMockAction,
      bodyBuilder: (context, isDesktop) => _content(isDesktop: isDesktop),
    );
  }

  Widget _content({required bool isDesktop}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 40 : 16,
        isDesktop ? 32 : 18,
        isDesktop ? 40 : 16,
        isDesktop ? 42 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MasterTitleBar(
                isDesktop: isDesktop,
                onOpenFilters: _openFilterSheet,
              ),
              if (_loading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_loadError != null) ...[
                const SizedBox(height: 14),
                _BackendErrorState(
                  message: _loadError!,
                  onRetry: () => _loadAppointments(),
                ),
              ],
              const SizedBox(height: 22),
              _MasterTabs(
                selected: _tab,
                counts: _counts,
                onSelect: (tab) => setState(() => _tab = tab),
              ),
              const SizedBox(height: 18),
              _MasterToolbar(
                query: _query,
                isDesktop: isDesktop,
                onQueryChanged: (value) => setState(() => _query = value),
                onOpenFilters: _openFilterSheet,
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _visibleItems.isEmpty
                    ? const _EmptyMasterAppointments()
                    : Column(
                        key: ValueKey('$_tab-$_query-${_items.length}'),
                        children: [
                          for (final item in _visibleItems) ...[
                            _MasterAppointmentCard(
                              item: item,
                              isDesktop: isDesktop,
                              onConfirm: () => _confirm(item.id),
                              onCancel: () => _cancel(item.id),
                              onOpenChat: () => widget.onOpenChat(
                                item.clientId.trim().isEmpty
                                    ? 'messages'
                                    : item.clientId,
                              ),
                              onOpenJournal: () {
                                final journalId = item.journalRouteId;
                                if (journalId.isEmpty) {
                                  return;
                                }
                                widget.onOpenCareJournal(
                                  item.isBackendBacked
                                      ? 'appointment:${item.id}'
                                      : journalId,
                                );
                              },
                              onOpenDetails: () =>
                                  _showMockAction('Открыта запись ${item.clientPublicName}'),
                              onOpenAccountProfile: () =>
                                  widget.onOpenAccountProfile(
                                    item.clientUsername,
                                    item.clientIsMaster,
                                  ),
                              onCreateRecommendations: () =>
                                  widget.onCreateRecommendations(item.id),
                              onEditDuration: () => _editDuration(item),
                            ),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton.icon(
                              onPressed: () =>
                                  _showMockAction('Показать еще'),
                              icon: const Icon(Icons.keyboard_arrow_down),
                              label: const Text('Показать еще'),
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

  Map<MasterAppointmentTab, int> get _counts {
    return {
      for (final tab in MasterAppointmentTab.values)
        tab: _items.where((item) => item.tab == tab).length,
    };
  }

  Future<void> _loadAppointments({bool silent = false}) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      if (silent) {
        return;
      }
      setState(() {
        _items = const <MasterAppointmentItem>[];
        _loading = false;
        _loadError =
            'Не удалось загрузить записи мастера: нет активной backend-сессии.';
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
      final response = await api.masterAppointments(token);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = response.items.map(_appointmentFromBackend).toList();
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
        _items = const <MasterAppointmentItem>[];
        _loading = false;
        _loadError = 'Не удалось загрузить записи мастера: $error';
      });
    }
  }

  MasterAppointmentItem _appointmentFromBackend(AppointmentRecord record) {
    final scheduledAt = _parseDate(record.scheduledAt);
    final scheduledEndAt = _parseOptionalDate(record.scheduledEndAt);
    final createdAt = _parseDate(record.createdAt);
    final clientName = record.client.displayName.trim().isNotEmpty
        ? record.client.displayName.trim()
        : '@${record.client.username}';
    final status = record.status.trim();
    return MasterAppointmentItem(
      id: record.id,
      clientId: record.client.id,
      clientUsername: record.client.username,
      clientName: clientName,
      clientImage: AuthenticatedDashboardTheme.appointmentImage,
      clientAvatarUrl: record.client.avatarUrl,
      service: record.service.name,
      date: _dateLabelFromDateTime(scheduledAt),
      startHour: scheduledAt.hour,
      startMinute: scheduledAt.minute,
      durationHours: _durationHours(record.service.durationHours),
      status: _masterStatus(status, record.recommendationStatus),
      tab: _tabFor(status, scheduledAt, scheduledEndAt),
      note: _noteForStatus(status, createdAt),
      endTimeOverride:
          scheduledEndAt == null ? null : _timeLabel(scheduledEndAt),
      durationLabelOverride:
          _serviceDurationLabel(record.service.durationHours),
      journalId: record.journalId,
      clientIsMaster: record.client.isMaster,
      showClientFullName: !clientName.startsWith('@'),
      isBackendBacked: true,
    );
  }

  MasterAppointmentStatus _masterStatus(
    String status,
    String recommendationStatus,
  ) {
    final recommendations = recommendationStatus.trim();
    if (recommendations == 'approved') {
      return MasterAppointmentStatus.journalCreated;
    }
    if ((status == 'confirmed' || status == 'completed') &&
        (recommendations == 'sent' || recommendations == 'approved')) {
      return MasterAppointmentStatus.recommendationsReady;
    }
    if (status == 'confirmed') {
      return MasterAppointmentStatus.confirmed;
    }
    if (status == 'rejected' || status == 'cancelled') {
      return MasterAppointmentStatus.cancelled;
    }
    if (status == 'completed') {
      return MasterAppointmentStatus.journalCreated;
    }
    return MasterAppointmentStatus.pending;
  }

  MasterAppointmentTab _tabFor(
    String status,
    DateTime scheduledAt,
    DateTime? scheduledEndAt,
  ) {
    if (status == 'rejected' || status == 'cancelled') {
      return MasterAppointmentTab.cancelled;
    }
    if (status == 'completed') {
      return MasterAppointmentTab.past;
    }
    final compareAt = scheduledEndAt ?? scheduledAt;
    if (compareAt.isBefore(DateTime.now())) {
      return MasterAppointmentTab.past;
    }
    return MasterAppointmentTab.upcoming;
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

  String _noteForStatus(String status, DateTime createdAt) {
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

  String _serviceDurationLabel(double? hours) {
    if (hours == null || hours <= 0) {
      return '1 ч';
    }
    if (hours < 1) {
      return '${(hours * 60).round()} мин';
    }
    if (hours == hours.roundToDouble()) {
      return '${hours.round()} ч';
    }
    return '${hours.toStringAsFixed(1)} ч';
  }

  int _durationHours(double? hours) {
    if (hours == null || hours <= 0) {
      return 1;
    }
    final rounded = hours.ceil();
    return rounded < 1 ? 1 : rounded;
  }

  Future<void> _confirm(String id) async {
    final updated = await _updateStatus(id, 'confirmed');
    if (updated) {
      return;
    }
    _showMockAction('Не удалось подтвердить запись через backend');
  }

  Future<void> _cancel(String id) async {
    final updated = await _updateStatus(id, 'rejected');
    if (updated) {
      return;
    }
    _showMockAction('Не удалось отклонить запись через backend');
  }

  Future<bool> _updateStatus(String id, String status) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      return false;
    }
    try {
      final record = await api.updateMasterAppointmentStatus(
        sessionToken: token,
        appointmentId: id,
        status: status,
      );
      if (!mounted) {
        return true;
      }
      final mapped = _appointmentFromBackend(record);
      setState(() {
        _items = _items.map((item) => item.id == id ? mapped : item).toList();
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _editDuration(MasterAppointmentItem item) async {
    final selected = await showModalBottomSheet<int>(
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
                  'Изменить длительность сеанса',
                  style: TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${item.clientPublicName} · ${item.service}',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
                for (final hours in const [2, 3, 4, 6])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_durationLabel(hours)),
                    subtitle: Text(
                      'Новое время: ${item.startTime} — ${MasterAppointmentItem._formatTime(item.startHour + hours, item.startMinute)}',
                    ),
                    trailing: item.durationHours == hours
                        ? const Icon(Icons.check, color: _accent)
                        : null,
                    onTap: () => Navigator.of(context).pop(hours),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == item.durationHours) {
      return;
    }

    final api = widget.api;
    final token = widget.sessionToken;
    if (api != null && token != null && token.isNotEmpty) {
      try {
        final response = await api.updateMasterAppointmentDuration(
          sessionToken: token,
          appointmentId: item.id,
          durationMinutes: selected * 60,
        );
        if (!mounted) {
          return;
        }
        final mapped = _appointmentFromBackend(response.appointment);
        setState(() {
          _items = _items
              .map((entry) => entry.id == item.id ? mapped : entry)
              .toList();
        });
        if (response.warnings.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Длительность сохранена. Проверьте предупреждения: ${response.warnings.join(', ')}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось изменить длительность: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    _showMockAction('Не удалось изменить длительность: нет активной backend-сессии');
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
                  style: TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                for (final tab in MasterAppointmentTab.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_tabLabel(tab)),
                    trailing: _tab == tab
                        ? const Icon(Icons.check, color: _accent)
                        : null,
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() => _tab = tab);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
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

class _MasterTitleBar extends StatelessWidget {
  const _MasterTitleBar({
    required this.isDesktop,
    required this.onOpenFilters,
  });

  final bool isDesktop;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Управление записями',
                style: TextStyle(
                  color: _MasterAppointmentsScreenState._text,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Подтверждайте, отклоняйте и корректируйте записи клиентов',
                style: TextStyle(
                  color: _MasterAppointmentsScreenState._muted,
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
    );
  }
}

class _MasterTabs extends StatelessWidget {
  const _MasterTabs({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final MasterAppointmentTab selected;
  final Map<MasterAppointmentTab, int> counts;
  final ValueChanged<MasterAppointmentTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in MasterAppointmentTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _MasterTabButton(
                label: _tabLabel(tab),
                count: counts[tab] ?? 0,
                selected: selected == tab,
                onTap: () => onSelect(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _MasterTabButton extends StatelessWidget {
  const _MasterTabButton({
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
    return Material(
      color: selected
          ? _MasterAppointmentsScreenState._accent
          : Colors.white,
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
                  ? _MasterAppointmentsScreenState._accent
                  : _MasterAppointmentsScreenState._line,
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
                      : _MasterAppointmentsScreenState._text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$count',
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.86)
                      : _MasterAppointmentsScreenState._muted,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterToolbar extends StatelessWidget {
  const _MasterToolbar({
    required this.query,
    required this.isDesktop,
    required this.onQueryChanged,
    required this.onOpenFilters,
  });

  final String query;
  final bool isDesktop;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      onChanged: onQueryChanged,
      decoration: InputDecoration(
        hintText: 'Поиск по клиенту или услуге',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _MasterAppointmentsScreenState._line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _MasterAppointmentsScreenState._line),
        ),
      ),
    );

    if (!isDesktop) {
      return search;
    }

    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 14),
        OutlinedButton.icon(
          onPressed: onOpenFilters,
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Фильтр'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _MasterAppointmentsScreenState._text,
            side: const BorderSide(color: _MasterAppointmentsScreenState._line),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size(136, 52),
          ),
        ),
      ],
    );
  }
}

class _MasterAppointmentCard extends StatelessWidget {
  const _MasterAppointmentCard({
    required this.item,
    required this.isDesktop,
    required this.onConfirm,
    required this.onCancel,
    required this.onOpenChat,
    required this.onOpenJournal,
    required this.onOpenDetails,
    required this.onOpenAccountProfile,
    required this.onCreateRecommendations,
    required this.onEditDuration,
  });

  final MasterAppointmentItem item;
  final bool isDesktop;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenJournal;
  final VoidCallback onOpenDetails;
  final VoidCallback onOpenAccountProfile;
  final VoidCallback onCreateRecommendations;
  final VoidCallback onEditDuration;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.all(isDesktop ? 18 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _MasterAppointmentsScreenState._line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: isDesktop ? _desktopLayout() : _mobileLayout(),
    );
  }

  Widget _desktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AvatarImage(
          assetPath: item.clientImage,
          avatarUrl: item.clientAvatarUrl,
          letterFallback: item.clientName,
          size: 64,
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 2,
          child: _ClientInfo(
            item: item,
            onOpenAccountProfile: onOpenAccountProfile,
          ),
        ),
        Expanded(
          flex: 2,
          child: _TimeInfo(item: item),
        ),
        Expanded(
          flex: 3,
          child: _MasterAppointmentActions(
            item: item,
            isDesktop: true,
            onConfirm: onConfirm,
            onCancel: onCancel,
            onOpenChat: onOpenChat,
            onOpenJournal: onOpenJournal,
            onOpenDetails: onOpenDetails,
            onCreateRecommendations: onCreateRecommendations,
          ),
        ),
        _MasterMenu(
          onOpenDetails: onOpenDetails,
          onEditDuration: onEditDuration,
          onCancel: onCancel,
        ),
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
            _AvatarImage(
              assetPath: item.clientImage,
              avatarUrl: item.clientAvatarUrl,
              letterFallback: item.clientName,
              size: 56,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ClientInfo(
                item: item,
                compact: true,
                onOpenAccountProfile: onOpenAccountProfile,
              ),
            ),
            _MasterMenu(
              onOpenDetails: onOpenDetails,
              onEditDuration: onEditDuration,
              onCancel: onCancel,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TimeInfo(item: item, compact: true),
        const SizedBox(height: 12),
        _MasterAppointmentActions(
          item: item,
          isDesktop: false,
          onConfirm: onConfirm,
          onCancel: onCancel,
          onOpenChat: onOpenChat,
          onOpenJournal: onOpenJournal,
          onOpenDetails: onOpenDetails,
          onCreateRecommendations: onCreateRecommendations,
        ),
      ],
    );
  }
}

class _ClientInfo extends StatelessWidget {
  const _ClientInfo({
    required this.item,
    required this.onOpenAccountProfile,
    this.compact = false,
  });

  final MasterAppointmentItem item;
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
              item.clientHandle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _MasterAppointmentsScreenState._text,
                fontSize: compact ? 15 : 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (item.showClientFullName) ...[
          const SizedBox(height: 4),
          Text(
            item.clientName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _MasterAppointmentsScreenState._muted,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          item.service,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _MasterAppointmentsScreenState._muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TimeInfo extends StatelessWidget {
  const _TimeInfo({required this.item, this.compact = false});

  final MasterAppointmentItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 14 : 22,
      runSpacing: 8,
      children: [
        _InfoLine(icon: Icons.calendar_today_outlined, text: item.date),
        _InfoLine(icon: Icons.schedule, text: item.timeRange),
        _InfoPill(text: 'Сеанс: ${item.durationLabel}'),
      ],
    );
  }
}

class _MasterAppointmentActions extends StatelessWidget {
  const _MasterAppointmentActions({
    required this.item,
    required this.isDesktop,
    required this.onConfirm,
    required this.onCancel,
    required this.onOpenChat,
    required this.onOpenJournal,
    required this.onOpenDetails,
    required this.onCreateRecommendations,
  });

  final MasterAppointmentItem item;
  final bool isDesktop;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenJournal;
  final VoidCallback onOpenDetails;
  final VoidCallback onCreateRecommendations;

  @override
  Widget build(BuildContext context) {
    final status = _MasterStatusBadge(status: item.status);
    final buttons = _buttons();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        status,
        const SizedBox(height: 8),
        Text(
          item.note,
          style: const TextStyle(
            color: _MasterAppointmentsScreenState._muted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        if (isDesktop)
          Wrap(spacing: 8, runSpacing: 8, children: buttons)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < buttons.length; index++) ...[
                buttons[index],
                if (index != buttons.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
      ],
    );
  }

  List<Widget> _buttons() {
    switch (item.status) {
      case MasterAppointmentStatus.pending:
        return [
          _PrimaryActionButton(label: 'Подтвердить', onTap: onConfirm),
          _SecondaryActionButton(label: 'Написать', onTap: onOpenChat),
          _DangerActionButton(label: 'Отклонить', onTap: onCancel),
        ];
      case MasterAppointmentStatus.confirmed:
        return [
          _SecondaryActionButton(label: 'Написать', onTap: onOpenChat),
          _PrimaryActionButton(
            label: 'Сформировать рекомендации',
            onTap: onCreateRecommendations,
          ),
        ];
      case MasterAppointmentStatus.recommendationsReady:
        return [
          _SecondaryActionButton(label: 'Написать', onTap: onOpenChat),
          _SecondaryActionButton(label: 'Посмотреть', onTap: onOpenDetails),
          _SecondaryActionButton(
            label: 'Редактировать рекомендации',
            onTap: onCreateRecommendations,
          ),
        ];
      case MasterAppointmentStatus.journalCreated:
        return [
          _SecondaryActionButton(
            label: item.journalRouteId.isEmpty
                ? 'Журнал ещё не создан'
                : 'Открыть журнал',
            onTap: item.journalRouteId.isEmpty ? null : onOpenJournal,
          ),
        ];
      case MasterAppointmentStatus.cancelled:
        return [
          _SecondaryActionButton(label: 'Написать', onTap: onOpenChat),
        ];
    }
  }
}

class _MasterStatusBadge extends StatelessWidget {
  const _MasterStatusBadge({required this.status});

  final MasterAppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final data = switch (status) {
      MasterAppointmentStatus.pending => (
          'Ожидает подтверждения',
          const Color(0xFFFFF4D8),
          const Color(0xFF9A6700)
        ),
      MasterAppointmentStatus.confirmed => (
          'Подтверждена',
          const Color(0xFFEAF7EF),
          const Color(0xFF246B4F)
        ),
      MasterAppointmentStatus.cancelled => (
          'Отменена',
          const Color(0xFFFFE7E7),
          const Color(0xFFD92D20)
        ),
      MasterAppointmentStatus.recommendationsReady => (
          'Рекомендации готовы',
          const Color(0xFFEAF2FF),
          const Color(0xFF2457A6)
        ),
      MasterAppointmentStatus.journalCreated => (
          'Журнал создан',
          const Color(0xFFF0E9FF),
          const Color(0xFF6E3BB8)
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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

class _MasterMenu extends StatelessWidget {
  const _MasterMenu({
    required this.onOpenDetails,
    required this.onEditDuration,
    required this.onCancel,
  });

  final VoidCallback onOpenDetails;
  final VoidCallback onEditDuration;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'details') {
          onOpenDetails();
        } else if (value == 'duration') {
          onEditDuration();
        } else if (value == 'cancel') {
          onCancel();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'details', child: Text('Детали записи')),
        PopupMenuItem(value: 'duration', child: Text('Изменить длительность')),
        PopupMenuItem(value: 'cancel', child: Text('Отменить запись')),
      ],
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: _MasterAppointmentsScreenState._accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(116, 42),
      ),
      child: Text(label),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _MasterAppointmentsScreenState._accent,
        side: const BorderSide(color: _MasterAppointmentsScreenState._line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(112, 42),
      ),
      child: Text(label),
    );
  }
}

class _DangerActionButton extends StatelessWidget {
  const _DangerActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFD92D20),
        side: const BorderSide(color: Color(0xFFF04438)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(112, 42),
      ),
      child: Text(label),
    );
  }
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({
    required this.assetPath,
    required this.avatarUrl,
    required this.letterFallback,
    required this.size,
  });

  final String assetPath;
  final String avatarUrl;
  final String letterFallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ProfileImage(
      avatarUrl: avatarUrl,
      fallbackAssetPath: assetPath,
      letterFallback: letterFallback,
      width: size,
      height: size,
      circular: true,
      fit: BoxFit.cover,
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _MasterAppointmentsScreenState._muted),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            color: _MasterAppointmentsScreenState._muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _MasterAppointmentsScreenState._soft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _MasterAppointmentsScreenState._muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyMasterAppointments extends StatelessWidget {
  const _EmptyMasterAppointments();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _MasterAppointmentsScreenState._line),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.assignment_outlined,
            color: _MasterAppointmentsScreenState._muted,
            size: 42,
          ),
          SizedBox(height: 12),
          Text(
            'Записей не найдено',
            style: TextStyle(
              color: _MasterAppointmentsScreenState._text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterOnlyScreen extends StatelessWidget {
  const _MasterOnlyScreen({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MasterAppointmentsScreenState._background,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _MasterAppointmentsScreenState._line),
            boxShadow: AuthenticatedDashboardTheme.cardShadow(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                color: _MasterAppointmentsScreenState._accent,
                size: 42,
              ),
              const SizedBox(height: 14),
              const Text(
                'Доступно только мастерам',
                style: TextStyle(
                  color: _MasterAppointmentsScreenState._text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Управление записями появляется только для реальной роли master.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _MasterAppointmentsScreenState._muted),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: onBack,
                child: const Text('Вернуться на главную'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _tabLabel(MasterAppointmentTab tab) {
  return switch (tab) {
    MasterAppointmentTab.upcoming => 'Предстоящие',
    MasterAppointmentTab.past => 'Прошедшие',
    MasterAppointmentTab.cancelled => 'Отмененные',
  };
}

String _durationLabel(int hours) {
  if (hours == 1) {
    return '1 час';
  }
  if (hours >= 2 && hours <= 4) {
    return '$hours часа';
  }
  return '$hours часов';
}
