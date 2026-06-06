import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../utils/auto_refresh.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';

const _accent = AuthenticatedDashboardTheme.accent;
const _card = AuthenticatedDashboardTheme.card;
const _line = AuthenticatedDashboardTheme.line;
const _muted = AuthenticatedDashboardTheme.muted;
const _soft = AuthenticatedDashboardTheme.soft;
const _text = AuthenticatedDashboardTheme.text;
const _warning = AuthenticatedDashboardTheme.warning;
const _warningBg = AuthenticatedDashboardTheme.warningBg;

class AppointmentCareJournalsScreen extends StatefulWidget {
  const AppointmentCareJournalsScreen({
    super.key,
    required this.user,
    required this.userName,
    required this.appointmentId,
    required this.items,
    required this.isLoading,
    required this.asMaster,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenJournal,
    required this.onOpenOwnCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenProfile,
    required this.onOpenRecommendations,
    required this.onBack,
    required this.onRetry,
    required this.onAutoRefresh,
    this.errorText,
  });

  final AuthUser? user;
  final String userName;
  final String appointmentId;
  final List<AppointmentJournalSummary> items;
  final bool isLoading;
  final bool asMaster;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenJournal;
  final VoidCallback onOpenOwnCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRecommendations;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final VoidCallback onAutoRefresh;
  final String? errorText;

  @override
  State<AppointmentCareJournalsScreen> createState() =>
      _AppointmentCareJournalsScreenState();
}

class _AppointmentCareJournalsScreenState
    extends State<AppointmentCareJournalsScreen> {
  late final AutoRefreshController _autoRefresh;

  @override
  void initState() {
    super.initState();
    _autoRefresh = AutoRefreshController(
      interval: const Duration(seconds: 12),
      onRefresh: () async {
        if (!mounted || widget.isLoading || widget.appointmentId.trim().isEmpty) {
          return;
        }
        widget.onAutoRefresh();
      },
    )..start();
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
      activeSidebarItem: widget.asMaster
          ? AuthenticatedSidebarItem.clientJournals
          : AuthenticatedSidebarItem.careJournal,
      activeMobileNavItem: widget.asMaster
          ? AuthenticatedMobileNavItem.none
          : AuthenticatedMobileNavItem.careJournal,
      onOpenHome: widget.onOpenHome,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: widget.onOpenAppointments,
      onOpenMasterAppointments: widget.onOpenMasterAppointments,
      onOpenMessages: () => widget.onOpenChat('messages'),
      onOpenCareJournal: widget.onOpenOwnCareJournal,
      onOpenClientJournals: widget.onOpenClientJournals,
      onOpenServicesPrices: widget.onOpenServicesPrices,
      onOpenRecommendations: widget.onOpenRecommendations,
      onOpenProfile: widget.onOpenProfile,
      onMockAction: _showSnackBar(context),
      bodyBuilder: (context, isDesktop) => _content(context, isDesktop),
    );
  }

  Widget _content(BuildContext context, bool isDesktop) {
    if (widget.isLoading) {
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
              _Header(onBack: widget.onBack),
              const SizedBox(height: 18),
              if (widget.errorText != null &&
                  widget.errorText!.trim().isNotEmpty) ...[
                _BackendErrorState(
                  message: widget.errorText!,
                  onRetry: widget.onRetry,
                ),
                const SizedBox(height: 18),
              ],
              if (widget.items.isEmpty && widget.errorText == null)
                const _EmptyState()
              else
                for (var index = 0; index < widget.items.length; index++) ...[
                  _AppointmentJournalCard(
                    item: widget.items[index],
                    fallbackNumber: index + 1,
                    onOpen: () => widget.onOpenJournal(widget.items[index].id),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }

  ValueChanged<String> _showSnackBar(BuildContext context) {
    return (message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Назад к записям'),
          style: TextButton.styleFrom(foregroundColor: _text),
        ),
        const SizedBox(height: 18),
        const Text(
          'Журналы ухода по записи',
          style: TextStyle(
            color: _text,
            fontSize: 34,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'По этой записи может быть несколько версий журнала. Откройте нужный журнал для просмотра шагов ухода.',
          style: TextStyle(color: _muted, fontSize: 16, height: 1.45),
        ),
      ],
    );
  }
}

class _AppointmentJournalCard extends StatelessWidget {
  const _AppointmentJournalCard({
    required this.item,
    required this.fallbackNumber,
    required this.onOpen,
  });

  final AppointmentJournalSummary item;
  final int fallbackNumber;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final version = item.versionNumber > 0 ? item.versionNumber : fallbackNumber;
    final progressLabel = '${item.completedStepsCount}/${item.stepsCount}';
    final status = _statusLabel(item);
    final integrity = _integrityLabel(item);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Журнал №$version',
                style: const TextStyle(
                  color: _text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              _StatusChip(label: status.label, color: status.color),
              if (integrity != null)
                _StatusChip(
                  label: integrity.label,
                  color: integrity.color,
                  icon: integrity.icon,
                ),
              if (item.isOpen) const _StatusChip(label: 'Текущий', color: _accent),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 22,
            runSpacing: 10,
            children: [
              _InfoLine(
                icon: Icons.event_note_outlined,
                label: 'Создан',
                value: _dateLabel(item.createdAt),
              ),
              if (item.stoppedAt.trim().isNotEmpty)
                _InfoLine(
                  icon: Icons.block_outlined,
                  label: 'Остановлен',
                  value: _dateLabel(item.stoppedAt),
                ),
              _InfoLine(
                icon: Icons.check_circle_outline,
                label: 'Прогресс',
                value: progressLabel,
              ),
              if (item.cancelledStepsCount > 0)
                _InfoLine(
                  icon: Icons.remove_circle_outline,
                  label: 'Отменено',
                  value: '${item.cancelledStepsCount}',
                ),
            ],
          ),
          if (item.stopReason.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _ReasonBlock(title: 'Причина остановки', text: item.stopReason),
          ],
          if (item.replacementReason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _ReasonBlock(title: 'Причина замены', text: item.replacementReason),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: item.id.trim().isEmpty ? null : onOpen,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Открыть'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: _accent),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ReasonBlock extends StatelessWidget {
  const _ReasonBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(color: _muted, height: 1.4)),
        ],
      ),
    );
  }
}

class _BackendErrorState extends StatelessWidget {
  const _BackendErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _warningBg,
        border: Border.all(color: _warning.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: _warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF7A3E00),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.menu_book_outlined, color: _accent, size: 30),
          SizedBox(height: 14),
          Text(
            'Журналов по этой записи пока нет',
            style: TextStyle(
              color: _text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Журнал появится после подтверждения рекомендаций мастера.',
            style: TextStyle(color: _muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

({String label, Color color}) _statusLabel(AppointmentJournalSummary item) {
  return switch (item.status) {
    'active' => (label: 'Активный', color: _accent),
    'completed' => (label: 'Завершён', color: _accent),
    'stopped' => (label: 'Остановлен', color: _warning),
    'replaced' => (label: 'Заменён', color: _muted),
    'draft' => (label: 'Черновик', color: _muted),
    _ => (label: 'Статус уточняется', color: _muted),
  };
}

({String label, Color color, IconData icon})? _integrityLabel(
  AppointmentJournalSummary item,
) {
  final status = item.integrityCheckStatus.trim();
  if (status == 'valid' && item.integrityValid && item.integrityEventsCount > 0) {
    return (
      label: 'Целостность подтверждена',
      color: _accent,
      icon: Icons.verified_user_outlined,
    );
  }
  return null;
}

String _dateLabel(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) {
    return 'Не указано';
  }
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}
