import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../utils/auto_refresh.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/profile_image.dart';

const _background = AuthenticatedDashboardTheme.background;
const _card = AuthenticatedDashboardTheme.card;
const _accent = AuthenticatedDashboardTheme.accent;
const _text = AuthenticatedDashboardTheme.text;
const _muted = AuthenticatedDashboardTheme.muted;
const _line = AuthenticatedDashboardTheme.line;
const _soft = AuthenticatedDashboardTheme.soft;

enum MyCareJournalFilter { all, active, completed }

class MyCareJournalItem {
  const MyCareJournalItem({
    required this.id,
    required this.masterUsername,
    required this.masterName,
    required this.masterImage,
    required this.masterAvatarUrl,
    required this.service,
    required this.zone,
    required this.date,
    required this.progress,
    required this.stepsDone,
    required this.stepsTotal,
    required this.status,
    required this.lastActivity,
    this.showMasterFullName = true,
  });

  final String id;
  final String masterUsername;
  final String masterName;
  final String masterImage;
  final String masterAvatarUrl;
  final String service;
  final String zone;
  final String date;
  final double progress;
  final int stepsDone;
  final int stepsTotal;
  final MyCareJournalFilter status;
  final String lastActivity;
  final bool showMasterFullName;

  String get masterHandle =>
      masterUsername.startsWith('@') ? masterUsername : '@$masterUsername';
}

class MyCareJournalsScreen extends StatefulWidget {
  const MyCareJournalsScreen({
    super.key,
    required this.user,
    required this.userName,
    this.api,
    this.sessionToken,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenProfile,
    required this.onOpenRecommendations,
  });

  final AuthUser? user;
  final String userName;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRecommendations;

  @override
  State<MyCareJournalsScreen> createState() => _MyCareJournalsScreenState();
}

class _MyCareJournalsScreenState extends State<MyCareJournalsScreen> {
  late final AutoRefreshController _autoRefresh;
  MyCareJournalFilter _filter = MyCareJournalFilter.all;
  List<MyCareJournalItem>? _backendItems;
  bool _loading = false;
  String? _loadError;

  List<MyCareJournalItem> get _sourceItems =>
      _backendItems ?? const <MyCareJournalItem>[];

  List<MyCareJournalItem> get _visibleItems {
    return _sourceItems.where((item) {
      return switch (_filter) {
        MyCareJournalFilter.all => true,
        MyCareJournalFilter.active =>
          item.status == MyCareJournalFilter.active,
        MyCareJournalFilter.completed =>
          item.status == MyCareJournalFilter.completed,
      };
    }).toList();
  }

  bool get _hasBackendEmptyState =>
      _backendItems != null && _backendItems!.isEmpty;

  @override
  void initState() {
    super.initState();
    _autoRefresh = AutoRefreshController(
      interval: const Duration(seconds: 12),
      onRefresh: () => _loadJournals(silent: true),
    )..start();
    _loadJournals();
  }

  @override
  void didUpdateWidget(covariant MyCareJournalsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken) {
      _loadJournals();
    }
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedPageShell(
      user: widget.user,
      userName: widget.userName,
      activeSidebarItem: AuthenticatedSidebarItem.careJournal,
      activeMobileNavItem: AuthenticatedMobileNavItem.careJournal,
      onOpenHome: widget.onOpenHome,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: widget.onOpenAppointments,
      onOpenMasterAppointments: widget.onOpenMasterAppointments,
      onOpenMessages: () => widget.onOpenChat('messages'),
      onOpenCareJournal: _showAlreadyOpen,
      onOpenClientJournals: widget.onOpenClientJournals,
      onOpenServicesPrices: widget.onOpenServicesPrices,
      onOpenRecommendations: widget.onOpenRecommendations,
      onOpenProfile: widget.onOpenProfile,
      onMockAction: _showMockAction,
      bodyBuilder: (context, isDesktop) => _content(isDesktop: isDesktop),
    );
  }

  Widget _content({required bool isDesktop}) {
    if (_loading && _backendItems == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 40 : 16,
        isDesktop ? 30 : 18,
        isDesktop ? 40 : 16,
        isDesktop ? 42 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PageTitle(),
              if (_loadError != null) ...[
                const SizedBox(height: 14),
                _BackendErrorState(
                  message: _loadError!,
                  onRetry: () => _loadJournals(),
                ),
              ],
              const SizedBox(height: 22),
              _StatsRow(
                items: _sourceItems,
                filter: _filter,
                onFilterChanged: (value) => setState(() => _filter = value),
              ),
              const SizedBox(height: 18),
              if (_hasBackendEmptyState)
                const _EmptyState(isBackendEmpty: true)
              else if (_visibleItems.isEmpty)
                const _EmptyState(isBackendEmpty: false)
              else
                for (final item in _visibleItems) ...[
                  _JournalCard(
                    item: item,
                    onOpen: () => widget.onOpenCareJournal(item.id),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadJournals({bool silent = false}) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      if (silent) {
        return;
      }
      setState(() {
        _backendItems = const <MyCareJournalItem>[];
        _loading = false;
        _loadError =
            'Не удалось загрузить журналы ухода: нет активной backend-сессии.';
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
      final response = await api.clientCareJournals(token);
      if (!mounted) {
        return;
      }
      setState(() {
        _backendItems = response.items.map(_journalFromBackend).toList();
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _backendItems = const <MyCareJournalItem>[];
        _loading = false;
        _loadError = 'Не удалось загрузить журналы ухода: $error';
      });
    }
  }

  MyCareJournalItem _journalFromBackend(CareJournalSummary summary) {
    final appointment = summary.appointment;
    final masterName = appointment.master.displayName.trim().isNotEmpty
        ? appointment.master.displayName.trim()
        : '@${appointment.master.username}';
    final stepsDone = summary.progress.stepsDone;
    final stepsTotal = summary.progress.stepsTotal;
    final progress = stepsTotal <= 0
        ? 0.0
        : (summary.progress.percent > 0
            ? summary.progress.percent / 100
            : stepsDone / stepsTotal);
    final completed = stepsTotal > 0 && stepsDone >= stepsTotal;
    final zone = appointment.service.style.trim().isNotEmpty
        ? appointment.service.style.trim()
        : appointment.service.category.trim();

    return MyCareJournalItem(
      id: summary.journal.id,
      masterUsername: appointment.master.username,
      masterName: masterName,
      masterImage: '',
      masterAvatarUrl: appointment.master.avatarUrl,
      service: appointment.service.name.trim().isEmpty
          ? 'Услуга'
          : appointment.service.name.trim(),
      zone: zone.isEmpty ? 'Зона не указана' : zone,
      date: _dateLabel(appointment.scheduledAt),
      progress: progress.clamp(0, 1).toDouble(),
      stepsDone: stepsDone,
      stepsTotal: stepsTotal,
      status: completed
          ? MyCareJournalFilter.completed
          : MyCareJournalFilter.active,
      lastActivity: completed
          ? 'Журнал завершён'
          : 'Осталось шагов: ${(stepsTotal - stepsDone).clamp(0, stepsTotal)}',
      showMasterFullName: !masterName.startsWith('@'),
    );
  }

  String _dateLabel(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) {
      return 'Дата уточняется';
    }
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  void _showAlreadyOpen() {
    _showMockAction('Список журналов ухода уже открыт');
  }

  void _showMockAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), behavior: SnackBarBehavior.floating),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Журнал ухода',
          style: TextStyle(
            color: _text,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Выберите журнал по конкретной записи и продолжайте уход по рекомендациям мастера.',
          style: TextStyle(color: _muted, fontSize: 15, height: 1.35),
        ),
      ],
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
          const Icon(Icons.wifi_off_rounded, size: 22, color: Color(0xFF9A6700)),
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

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.items,
    required this.filter,
    required this.onFilterChanged,
  });

  final List<MyCareJournalItem> items;
  final MyCareJournalFilter filter;
  final ValueChanged<MyCareJournalFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final all = items.length;
    final active =
        items.where((item) => item.status == MyCareJournalFilter.active).length;
    final completed = items
        .where((item) => item.status == MyCareJournalFilter.completed)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final compact = constraints.maxWidth < 520;
        final cardWidth =
            compact ? (constraints.maxWidth - spacing * 2) / 3 : 164.0;
        return Row(
          children: [
            _FilterStatCard(
              label: 'Все',
              value: '$all',
              icon: Icons.menu_book_outlined,
              selected: filter == MyCareJournalFilter.all,
              width: cardWidth,
              compact: compact,
              onTap: () => onFilterChanged(MyCareJournalFilter.all),
            ),
            const SizedBox(width: spacing),
            _FilterStatCard(
              label: 'Активные',
              value: '$active',
              icon: Icons.playlist_add_check,
              selected: filter == MyCareJournalFilter.active,
              width: cardWidth,
              compact: compact,
              onTap: () => onFilterChanged(MyCareJournalFilter.active),
            ),
            const SizedBox(width: spacing),
            _FilterStatCard(
              label: 'Завершены',
              value: '$completed',
              icon: Icons.check_circle_outline,
              selected: filter == MyCareJournalFilter.completed,
              width: cardWidth,
              compact: compact,
              onTap: () => onFilterChanged(MyCareJournalFilter.completed),
            ),
          ],
        );
      },
    );
  }
}

class _FilterStatCard extends StatelessWidget {
  const _FilterStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.selected,
    required this.width,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool selected;
  final double width;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: width,
          padding: EdgeInsets.all(compact ? 10 : 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? _accent : _line),
            boxShadow: AuthenticatedDashboardTheme.cardShadow(),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 30 : 38,
                height: compact ? 30 : 38,
                decoration: BoxDecoration(
                  color: _soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _accent, size: compact ? 16 : 19),
              ),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: _text,
                        fontSize: compact ? 14 : 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: selected ? _accent : _muted,
                          fontSize: compact ? 10 : 12,
                          fontWeight: FontWeight.w800,
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

class _JournalCard extends StatelessWidget {
  const _JournalCard({
    required this.item,
    required this.onOpen,
  });

  final MyCareJournalItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    return Container(
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _cardChildren(compact: true),
            )
          : Row(children: _cardChildren(compact: false)),
    );
  }

  List<Widget> _cardChildren({required bool compact}) {
    final image = ProfileImage(
      avatarUrl: item.masterAvatarUrl,
      fallbackAssetPath: item.masterImage,
      letterFallback: item.masterName,
      width: compact ? 76 : 96,
      height: compact ? 76 : 96,
      borderRadius: 16,
      fit: BoxFit.cover,
    );
    final info = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.masterHandle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (item.showMasterFullName) ...[
            const SizedBox(height: 4),
            Text(
              item.masterName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${item.service} · ${item.zone}',
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(item.date, style: const TextStyle(color: _muted)),
          const SizedBox(height: 12),
          _ProgressLine(progress: item.progress),
          const SizedBox(height: 8),
          Text(
            '${item.stepsDone} из ${item.stepsTotal} шагов выполнено · ${item.lastActivity}',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
    final actions = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
      children: [
        _StatusPill(filter: item.status),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(128, 42),
              ),
              child: const Text('Открыть журнал'),
            ),
          ],
        ),
      ],
    );

    if (compact) {
      return [
        Row(children: [image, const SizedBox(width: 12), info]),
        const SizedBox(height: 14),
        actions,
      ];
    }

    return [
      image,
      const SizedBox(width: 18),
      info,
      const SizedBox(width: 18),
      actions,
    ];
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 7,
        color: _accent,
        backgroundColor: _soft,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.filter});

  final MyCareJournalFilter filter;

  @override
  Widget build(BuildContext context) {
    final completed = filter == MyCareJournalFilter.completed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: completed ? const Color(0xFFEAF2FF) : const Color(0xFFEAF7EF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        completed ? 'Завершён' : 'Активный',
        style: TextStyle(
          color: completed ? const Color(0xFF2457A6) : _accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isBackendEmpty});

  final bool isBackendEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: Column(
        children: [
          const Icon(Icons.menu_book_outlined, color: _accent, size: 36),
          const SizedBox(height: 12),
          Text(
            isBackendEmpty
                ? 'У вас пока нет журналов ухода'
                : 'В этом фильтре журналов нет',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isBackendEmpty
                ? 'Журнал появится после подтверждения рекомендаций мастера.'
                : 'Переключите фильтр, чтобы увидеть остальные журналы.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
