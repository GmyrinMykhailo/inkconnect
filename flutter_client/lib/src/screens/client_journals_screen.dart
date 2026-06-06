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

enum ClientJournalFilter { active, waiting, completed }

class ClientJournalItem {
  const ClientJournalItem({
    required this.id,
    required this.clientId,
    required this.clientUsername,
    required this.clientName,
    required this.clientImage,
    required this.clientAvatarUrl,
    required this.service,
    required this.zone,
    required this.date,
    required this.progress,
    required this.stepsDone,
    required this.stepsTotal,
    required this.status,
    required this.lastActivity,
    required this.integrity,
    this.showClientFullName = true,
  });

  final String id;
  final String clientId;
  final String clientUsername;
  final String clientName;
  final String clientImage;
  final String clientAvatarUrl;
  final String service;
  final String zone;
  final String date;
  final double progress;
  final int stepsDone;
  final int stepsTotal;
  final ClientJournalFilter status;
  final String lastActivity;
  final bool integrity;
  final bool showClientFullName;

  String get clientHandle =>
      clientUsername.startsWith('@') ? clientUsername : '@$clientUsername';

  String get clientPublicName => showClientFullName ? clientName : clientHandle;
}

class ClientJournalsScreen extends StatefulWidget {
  const ClientJournalsScreen({
    super.key,
    required this.user,
    required this.userName,
    required this.selectedJournalId,
    this.api,
    this.sessionToken,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenOwnCareJournal,
    required this.onOpenServicesPrices,
    required this.onOpenProfile,
    required this.onOpenRecommendations,
    required this.onBack,
  });

  final AuthUser? user;
  final String userName;
  final String? selectedJournalId;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenOwnCareJournal;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRecommendations;
  final VoidCallback onBack;

  @override
  State<ClientJournalsScreen> createState() => _ClientJournalsScreenState();
}

class _ClientJournalsScreenState extends State<ClientJournalsScreen> {
  late final AutoRefreshController _autoRefresh;
  ClientJournalFilter _filter = ClientJournalFilter.active;
  String _query = '';
  List<ClientJournalItem>? _backendItems;
  bool _loading = false;
  String? _loadError;

  List<ClientJournalItem> get _visibleItems {
    final source = _backendItems ?? const <ClientJournalItem>[];
    final normalized = _query.trim().toLowerCase();
    return source.where((item) {
      final matchesFilter = item.status == _filter;
      final searchableName = item.showClientFullName ? item.clientName : '';
      final matchesQuery = normalized.isEmpty ||
          item.clientUsername.toLowerCase().contains(normalized) ||
          item.clientHandle.toLowerCase().contains(normalized) ||
          searchableName.toLowerCase().contains(normalized) ||
          item.service.toLowerCase().contains(normalized) ||
          item.zone.toLowerCase().contains(normalized);
      return matchesFilter && matchesQuery;
    }).toList();
  }

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
  void didUpdateWidget(covariant ClientJournalsScreen oldWidget) {
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
    if (widget.user?.role != 'master') {
      return _MasterOnlyState(onBack: widget.onOpenHome);
    }

    return AuthenticatedPageShell(
      user: widget.user,
      userName: widget.userName,
      activeSidebarItem: AuthenticatedSidebarItem.clientJournals,
      activeMobileNavItem: AuthenticatedMobileNavItem.none,
      onOpenHome: widget.onOpenHome,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: widget.onOpenAppointments,
      onOpenMasterAppointments: widget.onOpenMasterAppointments,
      onOpenMessages: () => widget.onOpenChat('messages'),
      onOpenCareJournal: widget.onOpenOwnCareJournal,
      onOpenClientJournals: () =>
          _showMockAction('Журналы клиентов уже открыты'),
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
        isDesktop ? 30 : 18,
        isDesktop ? 40 : 16,
        isDesktop ? 42 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackLink(onTap: widget.onBack),
              const SizedBox(height: 20),
              const _PageTitle(),
              if (_loading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_loadError != null) ...[
                const SizedBox(height: 14),
                _BackendErrorState(
                  message: _loadError!,
                  onRetry: () => _loadJournals(),
                ),
              ],
              const SizedBox(height: 22),
              _StatsRow(
                items: _backendItems ?? const <ClientJournalItem>[],
                filter: _filter,
                onFilterChanged: (value) => setState(() => _filter = value),
              ),
              const SizedBox(height: 14),
              _Toolbar(
                onQueryChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              for (final item in _visibleItems) ...[
                _JournalCard(
                  item: item,
                  highlighted: item.id == widget.selectedJournalId,
                  onOpen: () => _openJournal(item),
                  onMessage: () => widget.onOpenChat(
                    item.clientId.trim().isEmpty ? 'messages' : item.clientId,
                  ),
                  onIntegrity: () => _showIntegrity(item),
                ),
                const SizedBox(height: 12),
              ],
              if (_visibleItems.isEmpty) const _EmptyState(),
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
        _backendItems = const <ClientJournalItem>[];
        _loading = false;
        _loadError =
            'Не удалось загрузить журналы клиентов: нет активной backend-сессии.';
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
      final response = await api.masterCareJournals(token);
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
        _backendItems = const <ClientJournalItem>[];
        _loading = false;
        _loadError = 'Не удалось загрузить журналы клиентов: $error';
      });
    }
  }

  ClientJournalItem _journalFromBackend(CareJournalSummary summary) {
    final appointment = summary.appointment;
    final clientName = appointment.client.displayName.trim().isNotEmpty
        ? appointment.client.displayName
        : '@${appointment.client.username}';
    final progress = summary.progress.stepsTotal == 0
        ? 0.0
        : summary.progress.stepsDone / summary.progress.stepsTotal;
    return ClientJournalItem(
      id: summary.journal.id,
      clientId: appointment.client.id,
      clientUsername: appointment.client.username,
      clientName: clientName,
      clientImage: AuthenticatedDashboardTheme.appointmentImage,
      clientAvatarUrl: appointment.client.avatarUrl,
      service: appointment.service.name,
      zone: appointment.service.style.trim().isNotEmpty
          ? appointment.service.style
          : appointment.service.category,
      date: _dateLabel(appointment.scheduledAt),
      progress: progress,
      stepsDone: summary.progress.stepsDone,
      stepsTotal: summary.progress.stepsTotal,
      status: _filterFromProgress(summary.progress),
      lastActivity: _activityLabel(summary.progress),
      integrity: summary.journal.integrityStatus,
      showClientFullName: !clientName.startsWith('@'),
    );
  }

  void _openJournal(ClientJournalItem item) {
    widget.onOpenCareJournal(item.id);
  }

  void _showIntegrity(ClientJournalItem item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Целостность журнала ${item.clientPublicName} подтверждена',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showMockAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), behavior: SnackBarBehavior.floating),
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

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Журналы клиентов',
          style: TextStyle(
            color: _text,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Следите за прогрессом ухода, целостностью журналов и вопросами клиентов.',
          style: TextStyle(color: _muted, fontSize: 15, height: 1.35),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.items,
    required this.filter,
    required this.onFilterChanged,
  });

  final List<ClientJournalItem> items;
  final ClientJournalFilter filter;
  final ValueChanged<ClientJournalFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final active = items.where((item) => item.status == ClientJournalFilter.active).length;
    final waiting = items.where((item) => item.status == ClientJournalFilter.waiting).length;
    final completed =
        items.where((item) => item.status == ClientJournalFilter.completed).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final compact = constraints.maxWidth < 520;
        final cardWidth =
            compact ? (constraints.maxWidth - spacing * 2) / 3 : 164.0;

        return Row(
          children: [
            _FilterStatCard(
              label: 'Активные',
              value: '$active',
              icon: Icons.playlist_add_check,
              selected: filter == ClientJournalFilter.active,
              width: cardWidth,
              compact: compact,
              onTap: () => onFilterChanged(ClientJournalFilter.active),
            ),
            const SizedBox(width: spacing),
            _FilterStatCard(
              label: 'Ожидают',
              value: '$waiting',
              icon: Icons.hourglass_top,
              selected: filter == ClientJournalFilter.waiting,
              width: cardWidth,
              compact: compact,
              onTap: () => onFilterChanged(ClientJournalFilter.waiting),
            ),
            const SizedBox(width: spacing),
            _FilterStatCard(
              label: 'Завершены',
              value: '$completed',
              icon: Icons.check_circle_outline,
              selected: filter == ClientJournalFilter.completed,
              width: cardWidth,
              compact: compact,
              onTap: () => onFilterChanged(ClientJournalFilter.completed),
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
    final iconSize = compact ? 30.0 : 38.0;

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
                width: iconSize,
                height: iconSize,
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

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onQueryChanged,
  });

  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onQueryChanged,
      decoration: InputDecoration(
        hintText: 'Поиск по клиенту, услуге или зоне',
        prefixIcon: const Icon(Icons.search, color: _muted),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _accent),
        ),
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  const _JournalCard({
    required this.item,
    required this.highlighted,
    required this.onOpen,
    required this.onMessage,
    required this.onIntegrity,
  });

  final ClientJournalItem item;
  final bool highlighted;
  final VoidCallback onOpen;
  final VoidCallback onMessage;
  final VoidCallback onIntegrity;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 720;

    return Container(
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      decoration: BoxDecoration(
        color: highlighted ? _accent.withValues(alpha: 0.06) : _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlighted ? _accent : _line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _cardChildren(compact: true),
            )
          : Row(
              children: _cardChildren(compact: false),
            ),
    );
  }

  List<Widget> _cardChildren({required bool compact}) {
    final image = ProfileImage(
      avatarUrl: item.clientAvatarUrl,
      fallbackAssetPath: item.clientImage,
      letterFallback: item.clientName,
      width: compact ? 76 : 96,
      height: compact ? 76 : 96,
      circular: true,
      fit: BoxFit.cover,
    );
    final info = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.clientHandle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          if (item.showClientFullName) ...[
            const SizedBox(height: 4),
            Text(
              item.clientName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 8),
          Text('${item.service} · ${item.zone}', style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
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
      crossAxisAlignment: compact ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
      children: [
        _StatusPill(filter: item.status),
        if (item.integrity) ...[
          const SizedBox(height: 12),
          _IntegrityPill(onTap: onIntegrity),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(
              onPressed: onMessage,
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: _line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(112, 42),
              ),
              child: const Text('Написать'),
            ),
            FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  final ClientJournalFilter filter;

  @override
  Widget build(BuildContext context) {
    final color = switch (filter) {
      ClientJournalFilter.active => _accent,
      ClientJournalFilter.waiting => const Color(0xFF9A6700),
      ClientJournalFilter.completed => const Color(0xFF3653A4),
    };
    final bg = color.withValues(alpha: 0.10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        _filterLabel(filter),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _IntegrityPill extends StatelessWidget {
  const _IntegrityPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 15,
              color: _accent,
            ),
            const SizedBox(width: 6),
            Text(
              'Целостность подтверждена',
              style: const TextStyle(
                color: _accent,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, size: 18, color: _muted),
            SizedBox(width: 8),
            Text('Назад к записям', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: _accent, size: 21),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: const Text(
        'По этому фильтру журналов пока нет.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MasterOnlyState extends StatelessWidget {
  const _MasterOnlyState({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AuthenticatedDashboardTheme.cardShadow(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: _accent, size: 36),
              const SizedBox(height: 12),
              const Text(
                'Журналы клиентов доступны только мастеру',
                textAlign: TextAlign.center,
                style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onBack, child: const Text('На главную')),
            ],
          ),
        ),
      ),
    );
  }
}

String _filterLabel(ClientJournalFilter filter) {
  return switch (filter) {
    ClientJournalFilter.active => 'Активные',
    ClientJournalFilter.waiting => 'Ожидают подтверждения',
    ClientJournalFilter.completed => 'Завершенные',
  };
}

ClientJournalFilter _filterFromProgress(CareJournalProgress progress) {
  if (progress.stepsTotal > 0 && progress.stepsDone >= progress.stepsTotal) {
    return ClientJournalFilter.completed;
  }
  if (progress.stepsDone == 0) {
    return ClientJournalFilter.waiting;
  }
  return ClientJournalFilter.active;
}

String _activityLabel(CareJournalProgress progress) {
  if (progress.stepsTotal > 0 && progress.stepsDone >= progress.stepsTotal) {
    return 'Журнал завершен';
  }
  if (progress.stepsDone == 0) {
    return 'Клиент еще не подтвердил шаги';
  }
  return '${progress.stepsDone} из ${progress.stepsTotal} шагов выполнено';
}

String _dateLabel(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) {
    return value;
  }
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}
