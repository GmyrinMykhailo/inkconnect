import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../utils/auto_refresh.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/authenticated_site_header.dart';
import '../widgets/popular_masters_list.dart';
import '../widgets/profile_image.dart';

class AuthenticatedDashboardScreen extends StatelessWidget {
  const AuthenticatedDashboardScreen({
    super.key,
    required this.user,
    required this.api,
    required this.sessionToken,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenMasterProfile,
    required this.onOpenMyProfile,
    required this.onOpenFavorites,
    required this.onLogout,
  });

  final AuthUser? user;
  final InkConnectApiClient api;
  final String? sessionToken;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final ValueChanged<String> onOpenMasterProfile;
  final VoidCallback onOpenMyProfile;
  final VoidCallback onOpenFavorites;
  final Future<void> Function() onLogout;

  static const _background = AuthenticatedDashboardTheme.background;
  static const _card = AuthenticatedDashboardTheme.card;
  static const _accent = AuthenticatedDashboardTheme.accent;
  static const _text = AuthenticatedDashboardTheme.text;
  static const _muted = AuthenticatedDashboardTheme.muted;
  static const _line = AuthenticatedDashboardTheme.line;
  static const _soft = AuthenticatedDashboardTheme.soft;
  static const _warningBg = AuthenticatedDashboardTheme.warningBg;
  static const _warning = AuthenticatedDashboardTheme.warning;

  static const _appointmentImage =
      AuthenticatedDashboardTheme.appointmentImage;
  static const _mariaImage = AuthenticatedDashboardTheme.mariaImage;
  static const _dmitryImage = AuthenticatedDashboardTheme.dmitryImage;
  static const _victoriaImage = AuthenticatedDashboardTheme.victoriaImage;

  String get _displayName {
    final username = user?.username.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    return 'Артём';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;
        final isMaster = user?.role == 'master';

        return DecoratedBox(
          decoration: const BoxDecoration(color: _background),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                AuthenticatedSiteHeader(
                  isDesktop: !isMobile,
                  userName: _displayName,
                  activeSection: AuthenticatedHeaderSection.home,
                  horizontalPadding: isMobile ? 16 : 32,
                  onOpenHome: () {},
                  onOpenSearch: onOpenSearch,
                  onOpenRecommendations: () => _showMockAction(
                    context,
                    'Лента рекомендаций',
                  ),
                  onOpenNotifications: () => _showMockAction(
                    context,
                    'Уведомления',
                  ),
                  onOpenFavorites: onOpenFavorites,
                  onOpenProfile: onOpenMyProfile,
                ),
                Expanded(
                  child: isMobile
                      ? _MobileDashboard(
                          userName: _displayName,
                          isMaster: isMaster,
                          onOpenSearch: onOpenSearch,
                          onOpenAppointments: onOpenAppointments,
                          onOpenMasterAppointments: onOpenMasterAppointments,
                          onOpenChat: onOpenChat,
                          onOpenCareJournal: onOpenCareJournal,
                          onOpenClientJournals: onOpenClientJournals,
                          onOpenServicesPrices: onOpenServicesPrices,
                          onOpenMasterProfile: onOpenMasterProfile,
                          onOpenFavorites: onOpenFavorites,
                          api: api,
                          sessionToken: sessionToken,
                        )
                      : _DesktopDashboard(
                          userName: _displayName,
                          isMaster: isMaster,
                          onOpenSearch: onOpenSearch,
                          onOpenAppointments: onOpenAppointments,
                          onOpenMasterAppointments: onOpenMasterAppointments,
                          onOpenChat: onOpenChat,
                          onOpenCareJournal: onOpenCareJournal,
                          onOpenClientJournals: onOpenClientJournals,
                          onOpenServicesPrices: onOpenServicesPrices,
                          onOpenMasterProfile: onOpenMasterProfile,
                          onOpenFavorites: onOpenFavorites,
                          api: api,
                          sessionToken: sessionToken,
                        ),
                ),
                if (isMobile)
                  AuthenticatedMobileNavigation(
                    activeItem: AuthenticatedMobileNavItem.home,
                    onOpenHome: () {},
                    onOpenSearch: onOpenSearch,
                    onOpenMessages: () => onOpenChat('messages'),
                    onOpenRecommendations: () =>
                        _showMockAction(context, 'Лента рекомендаций'),
                    onOpenCareJournal: () => onOpenCareJournal('journal'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _showMockAction(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: mock-экран будет подключён следующим шагом'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard({
    required this.userName,
    required this.isMaster,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenMasterProfile,
    required this.onOpenFavorites,
    required this.api,
    required this.sessionToken,
  });

  final String userName;
  final bool isMaster;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final ValueChanged<String> onOpenMasterProfile;
  final VoidCallback onOpenFavorites;
  final InkConnectApiClient api;
  final String? sessionToken;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthenticatedSidebar(
          activeItem: AuthenticatedSidebarItem.home,
          isMaster: isMaster,
          onOpenHome: () {},
          onOpenAppointments: onOpenAppointments,
          onOpenMasterAppointments: onOpenMasterAppointments,
          onOpenMessages: () => onOpenChat('messages'),
          onOpenCareJournal: () => onOpenCareJournal('journal'),
          onOpenClientJournals: onOpenClientJournals,
          onOpenServicesPrices: onOpenServicesPrices,
          onMockAction: (label) =>
              AuthenticatedDashboardScreen._showMockAction(context, label),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WelcomeHero(userName: userName),
                    const SizedBox(height: 28),
                    _UpcomingAppointmentBlock(
                      api: api,
                      sessionToken: sessionToken,
                      isMaster: isMaster,
                      compact: false,
                      onOpenAppointments: onOpenAppointments,
                      onOpenMasterAppointments: onOpenMasterAppointments,
                      onOpenSearch: onOpenSearch,
                      onOpenChat: onOpenChat,
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(title: 'Быстрые действия'),
                    const SizedBox(height: 16),
                    _QuickActions(
                      isMaster: isMaster,
                      onOpenSearch: onOpenSearch,
                      onOpenAppointments: onOpenAppointments,
                      onOpenMasterAppointments: onOpenMasterAppointments,
                      onOpenChat: () => onOpenChat('messages'),
                      onOpenCareJournal: () => onOpenCareJournal('journal'),
                      onOpenClientJournals: onOpenClientJournals,
                      onMockAction: (label) => AuthenticatedDashboardScreen._showMockAction(
                        context,
                        label,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _SectionTitle(title: 'Как проходит запись'),
                    const SizedBox(height: 16),
                    const _BookingProcess(),
                    const SizedBox(height: 32),
                    _SectionTitle(
                      title: 'Популярные мастера',
                      action: 'Смотреть всех',
                      onAction: onOpenSearch,
                    ),
                    const SizedBox(height: 16),
                    PopularMastersList(
                      api: api,
                      sessionToken: sessionToken,
                      isDesktop: true,
                      showProfileButton: false,
                      onOpenMasterProfile: onOpenMasterProfile,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileDashboard extends StatelessWidget {
  const _MobileDashboard({
    required this.userName,
    required this.isMaster,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenMasterProfile,
    required this.onOpenFavorites,
    required this.api,
    required this.sessionToken,
  });

  final String userName;
  final bool isMaster;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final ValueChanged<String> onOpenMasterProfile;
  final VoidCallback onOpenFavorites;
  final InkConnectApiClient api;
  final String? sessionToken;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeHero(userName: userName, flat: true),
          const SizedBox(height: 24),
          _UpcomingAppointmentBlock(
            api: api,
            sessionToken: sessionToken,
            isMaster: isMaster,
            compact: true,
            onOpenAppointments: onOpenAppointments,
            onOpenMasterAppointments: onOpenMasterAppointments,
            onOpenSearch: onOpenSearch,
            onOpenChat: onOpenChat,
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: 'Быстрые действия'),
          const SizedBox(height: 14),
          _QuickActions(
            mobile: true,
            isMaster: isMaster,
            onOpenSearch: onOpenSearch,
            onOpenAppointments: onOpenAppointments,
            onOpenMasterAppointments: onOpenMasterAppointments,
            onOpenChat: () => onOpenChat('messages'),
            onOpenCareJournal: () => onOpenCareJournal('journal'),
            onOpenClientJournals: onOpenClientJournals,
            onMockAction: (label) =>
                AuthenticatedDashboardScreen._showMockAction(
              context,
              label,
            ),
          ),
          const SizedBox(height: 28),
          const _SectionTitle(title: 'Как проходит запись'),
          const SizedBox(height: 14),
          const _BookingProcess(mobile: true),
          const SizedBox(height: 28),
          _SectionTitle(
            title: 'Популярные мастера',
            action: 'Смотреть всех',
            onAction: onOpenSearch,
          ),
          const SizedBox(height: 14),
          PopularMastersList(
            api: api,
            sessionToken: sessionToken,
            isDesktop: false,
            showProfileButton: false,
            onOpenMasterProfile: onOpenMasterProfile,
          ),
        ],
      ),
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({
    required this.userName,
    this.flat = false,
  });

  final String userName;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      padding: EdgeInsets.all(flat ? 0 : 32),
      flat: flat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Привет, $userName! 👋',
            style: TextStyle(
              color: AuthenticatedDashboardScreen._text,
              fontSize: flat ? 28 : 30,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Рад видеть тебя в InkConnect',
            style: TextStyle(
              color: AuthenticatedDashboardScreen._muted,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingAppointmentBlock extends StatefulWidget {
  const _UpcomingAppointmentBlock({
    required this.api,
    required this.sessionToken,
    required this.isMaster,
    required this.compact,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenSearch,
    required this.onOpenChat,
  });

  final InkConnectApiClient api;
  final String? sessionToken;
  final bool isMaster;
  final bool compact;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final VoidCallback onOpenSearch;
  final ValueChanged<String> onOpenChat;

  @override
  State<_UpcomingAppointmentBlock> createState() =>
      _UpcomingAppointmentBlockState();
}

class _UpcomingAppointmentBlockState extends State<_UpcomingAppointmentBlock> {
  late final AutoRefreshController _autoRefresh;
  _DashboardAppointmentItem? _appointment;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _autoRefresh = AutoRefreshController(
      interval: const Duration(seconds: 15),
      onRefresh: () => _load(silent: true),
    )..start();
    _load();
  }

  @override
  void didUpdateWidget(covariant _UpcomingAppointmentBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.isMaster != widget.isMaster) {
      _load();
    }
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final token = widget.sessionToken;
    if (token == null || token.isEmpty) {
      if (silent) {
        return;
      }
      setState(() {
        _appointment = null;
        _loading = false;
        _hasError = true;
      });
      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }

    try {
      final response = widget.isMaster
          ? await widget.api.masterAppointments(token)
          : await widget.api.clientAppointments(token);
      final next = _nearestUpcoming(response.items);
      if (!mounted) {
        return;
      }
      setState(() {
        _appointment = next == null ? null : _toDashboardItem(next);
        _loading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _appointment = null;
        _loading = false;
        _hasError = true;
      });
    }
  }

  AppointmentRecord? _nearestUpcoming(List<AppointmentRecord> records) {
    final now = DateTime.now();
    final upcoming = records
        .where((record) {
          final scheduledAt = _parseOptionalDate(record.scheduledAt);
          if (scheduledAt == null || !scheduledAt.isAfter(now)) {
            return false;
          }
          return !_isInactiveStatus(record.status);
        })
        .toList(growable: false);

    if (upcoming.isEmpty) {
      return null;
    }

    final sorted = [...upcoming]
      ..sort((a, b) {
        final first = _parseOptionalDate(a.scheduledAt) ?? DateTime(9999);
        final second = _parseOptionalDate(b.scheduledAt) ?? DateTime(9999);
        return first.compareTo(second);
      });
    return sorted.first;
  }

  bool _isInactiveStatus(String status) {
    final value = status.trim().toLowerCase();
    return value == 'cancelled' ||
        value == 'canceled' ||
        value == 'rejected' ||
        value == 'completed';
  }

  _DashboardAppointmentItem _toDashboardItem(AppointmentRecord record) {
    final scheduledAt = _parseOptionalDate(record.scheduledAt) ?? DateTime.now();
    final scheduledEndAt = _parseOptionalDate(record.scheduledEndAt) ??
        _endFromDuration(record, scheduledAt);
    final person = widget.isMaster ? record.client : record.master;
    final personName = person.displayName.trim().isNotEmpty
        ? person.displayName.trim()
        : _handle(person.username);
    final place = person.city.trim().isNotEmpty
        ? person.city.trim()
        : record.master.city.trim().isNotEmpty
            ? record.master.city.trim()
            : 'Место не указано';
    final session = _sessionLabel(record, scheduledAt, scheduledEndAt);
    final service = _serviceLabel(record.service);

    return _DashboardAppointmentItem(
      id: record.id,
      personId: person.id,
      personUsername: person.username,
      personName: personName,
      imagePath: AuthenticatedDashboardScreen._appointmentImage,
      imageUrl: person.avatarUrl,
      dateLabel: _dateLabel(scheduledAt),
      sessionLabel: session,
      placeLabel: place,
      serviceLabel: service,
      statusLabel: _statusLabel(record.status),
      showVerified: !widget.isMaster && record.master.isMaster,
      messageLabel: widget.isMaster ? 'Написать клиенту' : 'Написать мастеру',
    );
  }

  String _serviceLabel(MasterServiceSettings service) {
    final name = service.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final category = service.category.trim();
    if (category.isNotEmpty) {
      return category;
    }
    return 'Сеанс';
  }

  String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'confirmed':
        return 'Подтверждена';
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return 'Отменена';
      case 'completed':
        return 'Завершена';
      case 'rescheduled':
        return 'Перенесена';
      default:
        return 'Ожидает подтверждения';
    }
  }

  DateTime? _parseOptionalDate(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }

  DateTime? _endFromDuration(
    AppointmentRecord record,
    DateTime scheduledAt,
  ) {
    if (record.durationMinutes > 0) {
      return scheduledAt.add(Duration(minutes: record.durationMinutes));
    }
    final hours = record.service.durationHours;
    if (hours != null && hours > 0) {
      return scheduledAt.add(Duration(minutes: (hours * 60).round()));
    }
    return null;
  }

  String _sessionLabel(
    AppointmentRecord record,
    DateTime start,
    DateTime? end,
  ) {
    final range = end == null
        ? _timeLabel(start)
        : '${_timeLabel(start)} - ${_timeLabel(end)}';
    return '$range · Сеанс: ${_durationLabel(record, start, end)}';
  }

  String _durationLabel(
    AppointmentRecord record,
    DateTime start,
    DateTime? end,
  ) {
    var minutes = record.durationMinutes;
    if (minutes <= 0 && end != null) {
      minutes = end.difference(start).inMinutes;
    }
    if (minutes <= 0 && record.service.durationHours != null) {
      minutes = (record.service.durationHours! * 60).round();
    }
    if (minutes <= 0) {
      return '1 ч';
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

  String _dateLabel(DateTime date) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    const weekdays = [
      'понедельник',
      'вторник',
      'среда',
      'четверг',
      'пятница',
      'суббота',
      'воскресенье',
    ];
    return '${date.day} ${months[date.month - 1]}, ${weekdays[date.weekday - 1]}';
  }

  String _timeLabel(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _handle(String username) {
    final value = username.trim();
    if (value.isEmpty) {
      return '@user';
    }
    return value.startsWith('@') ? value : '@$value';
  }

  void _openDetails() {
    if (widget.isMaster) {
      widget.onOpenMasterAppointments();
      return;
    }
    widget.onOpenAppointments();
  }

  void _openMessages() {
    final personId = _appointment?.personId.trim();
    widget.onOpenChat(
      personId == null || personId.isEmpty ? 'messages' : personId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Мои ближайшие записи',
          action: 'Перейти к моим записям',
          onAction: _openDetails,
        ),
        SizedBox(height: widget.compact ? 12 : 16),
        if (_loading)
          const _UpcomingAppointmentStateCard(
            icon: Icons.hourglass_empty_rounded,
            title: 'Загружаем ближайшие записи...',
          )
        else if (_hasError)
          _UpcomingAppointmentStateCard(
            icon: Icons.wifi_off_rounded,
            title: 'Не удалось загрузить ближайшие записи',
            action: OutlinedButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить'),
            ),
          )
        else if (_appointment == null)
          _UpcomingAppointmentStateCard(
            icon: Icons.calendar_today_outlined,
            title: 'У вас пока нет ближайших записей',
            action: OutlinedButton(
              onPressed: widget.onOpenSearch,
              child: const Text('Найти мастера'),
            ),
          )
        else
          _AppointmentCard(
            item: _appointment!,
            compact: widget.compact,
            onDetails: _openDetails,
            onMessage: _openMessages,
          ),
      ],
    );
  }
}

class _DashboardAppointmentItem {
  const _DashboardAppointmentItem({
    required this.id,
    required this.personId,
    required this.personUsername,
    required this.personName,
    required this.imagePath,
    required this.imageUrl,
    required this.dateLabel,
    required this.sessionLabel,
    required this.placeLabel,
    required this.serviceLabel,
    required this.statusLabel,
    required this.showVerified,
    required this.messageLabel,
  });

  final String id;
  final String personId;
  final String personUsername;
  final String personName;
  final String imagePath;
  final String imageUrl;
  final String dateLabel;
  final String sessionLabel;
  final String placeLabel;
  final String serviceLabel;
  final String statusLabel;
  final bool showVerified;
  final String messageLabel;
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.item,
    required this.compact,
    required this.onDetails,
    required this.onMessage,
  });

  final _DashboardAppointmentItem item;
  final bool compact;
  final VoidCallback onDetails;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RoundedImage(
                  path: item.imagePath,
                  imageUrl: item.imageUrl,
                  width: 110,
                  height: 104,
                ),
                const SizedBox(width: 16),
                Expanded(child: _AppointmentInfo(item: item, compact: true)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _PrimaryButton(label: 'Подробнее', onTap: onDetails),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _SecondaryButton(label: item.messageLabel, onTap: onMessage),
            ),
          ],
        ),
      );
    }

    return _DashboardCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoundedImage(
            path: item.imagePath,
            imageUrl: item.imageUrl,
            width: 128,
            height: 128,
          ),
          const SizedBox(width: 24),
          Expanded(child: _AppointmentInfo(item: item, compact: false)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusPill(text: item.statusLabel),
              const SizedBox(height: 78),
              Row(
                children: [
                  _PrimaryButton(label: 'Подробнее', onTap: onDetails),
                  const SizedBox(width: 12),
                  _SecondaryButton(label: item.messageLabel, onTap: onMessage),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppointmentInfo extends StatelessWidget {
  const _AppointmentInfo({
    required this.item,
    required this.compact,
  });

  final _DashboardAppointmentItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                item.personName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AuthenticatedDashboardScreen._text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (item.showVerified) ...[
              const SizedBox(width: 8),
              Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: AuthenticatedDashboardScreen._accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 11, color: Colors.white),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          item.serviceLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AuthenticatedDashboardScreen._muted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        _MetaLine(icon: Icons.calendar_today_outlined, text: item.dateLabel),
        const SizedBox(height: 8),
        _MetaLine(icon: Icons.access_time, text: item.sessionLabel),
        const SizedBox(height: 8),
        _MetaLine(icon: Icons.location_on_outlined, text: item.placeLabel),
        if (compact) ...[
          const SizedBox(height: 12),
          _StatusPill(text: item.statusLabel),
        ],
      ],
    );
  }
}

class _UpcomingAppointmentStateCard extends StatelessWidget {
  const _UpcomingAppointmentStateCard({
    required this.icon,
    required this.title,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final summary = Row(
      children: [
        _IconBox(icon: icon, compact: true),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AuthenticatedDashboardScreen._text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    return _DashboardCard(
      child: action == null
          ? summary
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: action!,
                ),
              ],
            ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.isMaster,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onMockAction,
    this.mobile = false,
  });

  final bool isMaster;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final ValueChanged<String> onMockAction;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final actions = isMaster
        ? [
            _ActionData(
              Icons.event_note_outlined,
              'Мои записи',
              onOpenAppointments,
            ),
            _ActionData(
              Icons.fact_check_outlined,
              'Управление записями',
              onOpenMasterAppointments,
            ),
            _ActionData(
              Icons.calendar_month_outlined,
              'Календарь',
              () => onMockAction('Календарь'),
            ),
            _ActionData(
              Icons.folder_shared_outlined,
              'Журналы клиентов',
              onOpenClientJournals,
            ),
          ]
        : [
            _ActionData(Icons.search, 'Найти мастера', onOpenSearch),
            _ActionData(
              Icons.calendar_month_outlined,
              'Мои записи',
              onOpenAppointments,
            ),
            _ActionData(
              Icons.fact_check_outlined,
              'Журнал ухода',
              onOpenCareJournal,
            ),
            _ActionData(Icons.chat_bubble_outline, 'Сообщения', onOpenChat),
          ];

    if (mobile) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(actions.length, (index) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == actions.length - 1 ? 0 : 10,
              ),
              child: _QuickActionCard(data: actions[index], mobile: true),
            ),
          );
        }),
      );
    }

    return Row(
      children: actions
          .map(
            (item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _QuickActionCard(data: item),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.data,
    this.mobile = false,
  });

  final _ActionData data;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AuthenticatedDashboardScreen._card,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: mobile ? 84 : 104,
          padding: mobile
              ? const EdgeInsets.fromLTRB(8, 8, 8, 12)
              : const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AuthenticatedDashboardScreen._line),
            boxShadow: _cardShadow(),
            color: Colors.white,
          ),
          child: mobile
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _IconBox(icon: data.icon, compact: true),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 26,
                      child: Text(
                        data.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AuthenticatedDashboardScreen._text,
                          fontSize: 10,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconBox(icon: data.icon),
                    const Spacer(),
                    Text(
                      data.label,
                      style: const TextStyle(
                        color: AuthenticatedDashboardScreen._text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _BookingProcess extends StatelessWidget {
  const _BookingProcess({this.mobile = false});

  final bool mobile;

  @override
  Widget build(BuildContext context) {
    const steps = [
      _StepData(Icons.calendar_today_outlined, '1', 'Запись', 'Выберите мастера и удобное время'),
      _StepData(Icons.check_circle_outline, '2', 'Подтверждение', 'Мастер подтвердит запись'),
      _StepData(Icons.groups_outlined, '3', 'Встреча', 'Приходите в назначенное время'),
      _StepData(Icons.description_outlined, '4', 'Составление рекомендаций', 'Мастер составит рекомендации'),
      _StepData(Icons.menu_book_outlined, '5', 'Журнал ухода', 'Фиксируйте выполнение рекомендаций'),
    ];

    if (mobile) {
      return _DashboardCard(
        child: Column(
          children: steps
              .map(
                (step) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _ProcessStep(step: step, mobile: true),
                ),
              )
              .toList(),
        ),
      );
    }

    return _DashboardCard(
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(child: _ProcessStep(step: steps[i])),
            if (i != steps.length - 1)
              Container(height: 1, width: 34, color: AuthenticatedDashboardScreen._line),
          ],
        ],
      ),
    );
  }
}

class _ProcessStep extends StatelessWidget {
  const _ProcessStep({
    required this.step,
    this.mobile = false,
  });

  final _StepData step;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return mobile
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBox(icon: step.icon),
              const SizedBox(width: 14),
              Expanded(child: _StepText(step: step, align: TextAlign.left)),
            ],
          )
        : Column(
            children: [
              _IconBox(icon: step.icon),
              const SizedBox(height: 14),
              _StepText(step: step, align: TextAlign.center),
            ],
          );
  }
}

class _StepText extends StatelessWidget {
  const _StepText({
    required this.step,
    required this.align,
  });

  final _StepData step;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          step.number,
          textAlign: align,
          style: const TextStyle(
            color: AuthenticatedDashboardScreen._accent,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.title,
          textAlign: align,
          style: const TextStyle(
            color: AuthenticatedDashboardScreen._text,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          step.caption,
          textAlign: align,
          style: const TextStyle(
            color: AuthenticatedDashboardScreen._muted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _FavoriteMasters extends StatelessWidget {
  const _FavoriteMasters({
    required this.onOpenMasterProfile,
    this.mobile = false,
  });

  final ValueChanged<String> onOpenMasterProfile;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final masters = [
      const _MasterCardData('Анна Волкова', 'Реализм', '4.9', AuthenticatedDashboardScreen._appointmentImage),
      const _MasterCardData('Илья Орлов', 'Япония', '4.8', AuthenticatedDashboardScreen._mariaImage),
      const _MasterCardData('Мария Соколова', 'Графика', '4.9', AuthenticatedDashboardScreen._victoriaImage),
    ];

    if (mobile) {
      return SizedBox(
        height: 268,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: masters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) => SizedBox(
            width: 220,
            child: _FavoriteMasterCard(
              data: masters[index],
              onTap: () => onOpenMasterProfile('master'),
            ),
          ),
        ),
      );
    }

    return Row(
      children: masters
          .map(
            (master) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _FavoriteMasterCard(
                  data: master,
                  onTap: () => onOpenMasterProfile('master'),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FavoriteMasterCard extends StatelessWidget {
  const _FavoriteMasterCard({
    required this.data,
    required this.onTap,
  });

  final _MasterCardData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _cardShadow(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _RoundedImage(
                    path: data.image,
                    imageUrl: '',
                    width: double.infinity,
                    height: 172,
                    radius: 0,
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite, color: AuthenticatedDashboardScreen._accent, size: 19),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      style: const TextStyle(
                        color: AuthenticatedDashboardScreen._text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data.style,
                      style: const TextStyle(color: AuthenticatedDashboardScreen._muted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Color(0xFFF5B301), size: 16),
                        const SizedBox(width: 4),
                        Text(data.rating, style: const TextStyle(fontSize: 12)),
                        const Spacer(),
                        const Icon(Icons.location_on_outlined, size: 14, color: AuthenticatedDashboardScreen._muted),
                        const Text(' Москва', style: TextStyle(color: AuthenticatedDashboardScreen._muted, fontSize: 12)),
                      ],
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

class _Recommendations extends StatelessWidget {
  const _Recommendations({
    required this.onOpenMasterProfile,
    this.mobile = false,
  });

  final VoidCallback onOpenMasterProfile;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final items = [
      const _RecommendationData('Илья Орлов', 'Япония, Леттеринг', '4.8', '(156)', 'от 2 000 ₽ / час', AuthenticatedDashboardScreen._mariaImage),
      const _RecommendationData('Мария Соколова', 'Графика, Геометрия', '4.9', '(203)', 'от 2 500 ₽ / час', AuthenticatedDashboardScreen._victoriaImage),
      const _RecommendationData('Дмитрий Ким', 'Реализм', '4.7', '(187)', 'от 2 600 ₽ / час', AuthenticatedDashboardScreen._dmitryImage),
      const _RecommendationData('Виктория Лис', 'Ньюскул, Олд Скул', '4.9', '(234)', 'от 2 200 ₽ / час', AuthenticatedDashboardScreen._appointmentImage),
    ];

    if (mobile) {
      return SizedBox(
        height: 326,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) => SizedBox(
            width: 178,
            child: _RecommendationCard(
              data: items[index],
              onTap: onOpenMasterProfile,
            ),
          ),
        ),
      );
    }

    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _RecommendationCard(
                  data: item,
                  onTap: onOpenMasterProfile,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.data,
    required this.onTap,
  });

  final _RecommendationData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _cardShadow(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoundedImage(
                path: data.image,
                imageUrl: '',
                width: double.infinity,
                height: 148,
                radius: 0,
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AuthenticatedDashboardScreen._text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      data.style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AuthenticatedDashboardScreen._muted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Color(0xFFF5B301), size: 15),
                        const SizedBox(width: 4),
                        Text(data.rating, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            data.reviews,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AuthenticatedDashboardScreen._muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _MetaLine(icon: Icons.location_on_outlined, text: 'Москва', small: true),
                    const Divider(height: 22, color: AuthenticatedDashboardScreen._soft),
                    Text(
                      data.price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AuthenticatedDashboardScreen._text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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

class _CareJournalTeaser extends StatelessWidget {
  const _CareJournalTeaser({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: const [
            _IconBox(icon: Icons.spa_outlined, large: true),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Журнал ухода за тату',
                    style: TextStyle(
                      color: AuthenticatedDashboardScreen._text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Следи за заживлением и получай советы от экспертов',
                    style: TextStyle(color: AuthenticatedDashboardScreen._muted, height: 1.35),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AuthenticatedDashboardScreen._muted),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AuthenticatedDashboardScreen._text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              action!,
              style: const TextStyle(color: AuthenticatedDashboardScreen._accent),
            ),
          ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.flat = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    if (flat) {
      return child;
    }

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AuthenticatedDashboardScreen._card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _cardShadow(),
      ),
      child: child,
    );
  }
}

class _RoundedImage extends StatelessWidget {
  const _RoundedImage({
    required this.path,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.radius = 14,
  });

  final String path;
  final String imageUrl;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width.isFinite ? width : double.infinity,
      height: height,
      child: ProfileImage(
        avatarUrl: imageUrl,
        fallbackAssetPath: path,
        width: width.isFinite ? width : null,
        height: height,
        borderRadius: radius,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AuthenticatedDashboardScreen._accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AuthenticatedDashboardScreen._accent,
        side: const BorderSide(color: AuthenticatedDashboardScreen._line),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({
    required this.icon,
    this.large = false,
    this.compact = false,
  });

  final IconData icon;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: large ? 54 : (compact ? 38 : 44),
      height: large ? 54 : (compact ? 38 : 44),
      decoration: BoxDecoration(
        color: AuthenticatedDashboardScreen._accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        color: AuthenticatedDashboardScreen._accent,
        size: large ? 26 : (compact ? 20 : 22),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AuthenticatedDashboardScreen._warningBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AuthenticatedDashboardScreen._warning,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: const BoxDecoration(
        color: AuthenticatedDashboardScreen._accent,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.icon,
    required this.text,
    this.small = false,
  });

  final IconData icon;
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: small ? 14 : 16, color: AuthenticatedDashboardScreen._muted),
        SizedBox(width: small ? 4 : 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AuthenticatedDashboardScreen._muted,
              fontSize: small ? 12 : 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionData {
  const _ActionData(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _StepData {
  const _StepData(this.icon, this.number, this.title, this.caption);

  final IconData icon;
  final String number;
  final String title;
  final String caption;
}

class _MasterCardData {
  const _MasterCardData(this.name, this.style, this.rating, this.image);

  final String name;
  final String style;
  final String rating;
  final String image;
}

class _RecommendationData {
  const _RecommendationData(
    this.name,
    this.style,
    this.rating,
    this.reviews,
    this.price,
    this.image,
  );

  final String name;
  final String style;
  final String rating;
  final String reviews;
  final String price;
  final String image;
}

List<BoxShadow> _cardShadow() {
  return AuthenticatedDashboardTheme.cardShadow();
}
