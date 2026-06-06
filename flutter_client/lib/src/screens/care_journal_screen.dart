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

class CareJournalScreen extends StatefulWidget {
  const CareJournalScreen({
    super.key,
    required this.user,
    required this.userName,
    required this.journalId,
    required this.journalAsMaster,
    this.api,
    this.sessionToken,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenChat,
    required this.onOpenCareJournal,
    required this.onOpenCareJournalAsMaster,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenProfile,
    required this.onOpenRecommendations,
    required this.onOpenStepConfirmation,
    required this.completedStepIds,
    required this.onStepConfirmed,
    required this.onBack,
  });

  final AuthUser? user;
  final String userName;
  final String journalId;
  final bool journalAsMaster;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onOpenCareJournal;
  final ValueChanged<String> onOpenCareJournalAsMaster;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRecommendations;
  final ValueChanged<String> onOpenStepConfirmation;
  final Set<String> completedStepIds;
  final ValueChanged<String> onStepConfirmed;
  final VoidCallback onBack;

  @override
  State<CareJournalScreen> createState() => _CareJournalScreenState();
}

class _CareJournalScreenState extends State<CareJournalScreen> {
  late final AutoRefreshController _autoRefresh;
  final Set<String> _expandedIds = <String>{};
  bool _remindersEnabled = true;
  bool _desktopRecommendationsExpanded = true;
  bool _recommendationsExpanded = false;
  bool _historyExpanded = true;
  bool _showFullHistory = false;
  CareJournalDetail? _backendDetail;
  JournalIntegrityReport? _integrityReport;
  List<JournalEventRecord> _events = const <JournalEventRecord>[];
  AppointmentJournalSummary? _appointmentJournalSummary;
  bool _loading = true;
  String? _loadError;
  String? _integrityError;
  String? _eventsError;

  bool get _isClientJournalContext {
    return widget.journalAsMaster;
  }

  _JournalSubject get _subject =>
      _subjectFromDetail(_backendDetail!, _isClientJournalContext);

  List<_CareStep> get _visibleSteps =>
      _backendDetail?.steps
          .map((step) => _careStepFromBackend(step, _backendDetail!.appointment))
          .toList() ??
      const <_CareStep>[];

  Set<String> get _visibleCompletedIds {
    final detail = _backendDetail;
    if (detail != null) {
      return detail.steps
          .where((step) => step.isConfirmed)
          .map((step) => step.id)
          .toSet();
    }
    return const <String>{};
  }

  double get _progress {
    final detail = _backendDetail;
    if (detail != null && detail.progress.stepsTotal > 0) {
      return detail.progress.stepsDone / detail.progress.stepsTotal;
    }
    final steps = _visibleSteps;
    return steps.isEmpty ? 0 : _visibleCompletedIds.length / steps.length;
  }

  _JournalStateView get _journalState {
    final detail = _backendDetail;
    return _JournalStateView.from(
      journal: detail?.journal,
      summary: _appointmentJournalSummary,
    );
  }

  bool get _journalReadOnly => _journalState.isReadOnly;

  bool get _canClientNotify =>
      !_isClientJournalContext &&
      _journalState.status == 'active' &&
      !_journalState.hasStopMarker;

  bool get _canMasterManage =>
      _isClientJournalContext &&
      _journalState.status == 'active' &&
      !_journalState.hasStopMarker;

  bool get _canCreateReplacement =>
      _isClientJournalContext &&
      (_journalState.isStopped || _journalState.hasStopMarker) &&
      !_journalState.isCompleted &&
      !_journalState.isReplaced &&
      _journalState.replacedByJournalId.trim().isEmpty;

  List<_ClientJournalMessage> get _clientJournalMessages {
    return _events
        .where((event) =>
            event.eventType == 'client_unavailability_notice_added' ||
            event.eventType == 'client_problem_reported')
        .map((event) {
          final reason = _payloadString(event.payload, 'reason').trim().isNotEmpty
              ? _payloadString(event.payload, 'reason')
              : event.reason;
          final comment = _payloadString(event.payload, 'comment');
          return _ClientJournalMessage(
            id: event.id,
            reason: reason.trim(),
            comment: comment.trim(),
            createdAt: event.createdAt,
          );
        })
        .where((message) => message.id.trim().isNotEmpty && message.reason.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  void initState() {
    super.initState();
    _autoRefresh = AutoRefreshController(
      interval: const Duration(seconds: 7),
      onRefresh: () => _loadJournal(silent: true),
    )..start();
    _loadJournal();
  }

  @override
  void didUpdateWidget(covariant CareJournalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.journalId != widget.journalId ||
        oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken) {
      _loadJournal();
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
      activeSidebarItem: _isClientJournalContext
          ? AuthenticatedSidebarItem.clientJournals
          : AuthenticatedSidebarItem.careJournal,
      activeMobileNavItem: _isClientJournalContext
          ? AuthenticatedMobileNavItem.none
          : AuthenticatedMobileNavItem.careJournal,
      onOpenHome: widget.onOpenHome,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: widget.onOpenAppointments,
      onOpenMasterAppointments: widget.onOpenMasterAppointments,
      onOpenMessages: () => widget.onOpenChat('messages'),
      onOpenCareJournal: () => widget.onOpenCareJournal('journal'),
      onOpenClientJournals: widget.onOpenClientJournals,
      onOpenServicesPrices: widget.onOpenServicesPrices,
      onOpenRecommendations: widget.onOpenRecommendations,
      onOpenProfile: widget.onOpenProfile,
      onMockAction: _showMockAction,
      bodyBuilder: (context, isDesktop) => _content(isDesktop: isDesktop),
    );
  }

  Widget _content({required bool isDesktop}) {
    if (_loading && _backendDetail == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_loadError != null || _backendDetail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _BackendErrorState(
            message: _loadError ?? 'Журнал ухода не загружен.',
            onRetry: () => _loadJournal(),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 40 : 12,
        isDesktop ? 30 : 14,
        isDesktop ? 40 : 12,
        isDesktop ? 42 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackLink(onTap: widget.onBack),
              const SizedBox(height: 20),
              _PageTitle(
                clientJournalContext: _isClientJournalContext,
                journalState: _journalState,
                subject: _subject,
                integrityReport: _integrityReport,
                integrityError: _integrityError,
                compact: !isDesktop,
              ),
              if (_journalState.hasLifecycleNotice) ...[
                const SizedBox(height: 14),
                _JournalLifecycleNotice(
                  journalState: _journalState,
                  onOpenReplacement: _openReplacementJournal,
                ),
              ],
              const SizedBox(height: 22),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          _AppointmentCard(
                            subject: _subject,
                            clientJournalContext: _isClientJournalContext,
                            onOpenChat: () => widget.onOpenChat(_subject.id),
                          ),
                          const SizedBox(height: 22),
                          _RecommendationsTimeline(
                            steps: _visibleSteps,
                            completedIds: _visibleCompletedIds,
                            expandedIds: _expandedIds,
                            expanded: _desktopRecommendationsExpanded,
                            onToggle: _toggleStep,
                            onToggleExpanded: () => setState(
                              () => _desktopRecommendationsExpanded =
                                  !_desktopRecommendationsExpanded,
                            ),
                            onConfirm: _confirmStep,
                            onExtendDeadline: _showDeadlineExtensionDialog,
                            onOpenStep: widget.onOpenStepConfirmation,
                            readOnly: _isClientJournalContext || _journalReadOnly,
                            masterCanExtend: _canMasterManage,
                            compact: false,
                          ),
                          const SizedBox(height: 18),
                          _JournalHistoryCard(
                            events: _events,
                            steps: _visibleSteps,
                            errorText: _eventsError,
                            expanded: _historyExpanded,
                            showFullHistory: true,
                            canToggleFullHistory: false,
                            onToggleExpanded: () => setState(
                              () => _historyExpanded = !_historyExpanded,
                            ),
                            onToggleFullHistory: () {},
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          const _TipsCard(),
                          const SizedBox(height: 16),
                          _ProgressCard(progress: _progress),
                          const SizedBox(height: 16),
                          _IntegrityCard(
                            report: _integrityReport,
                            errorText: _integrityError,
                          ),
                          if (!_journalReadOnly || _canCreateReplacement) ...[
                            const SizedBox(height: 16),
                            _JournalActionsCard(
                              clientJournalContext: _isClientJournalContext,
                              journalState: _journalState,
                              canClientNotify: _canClientNotify,
                              canMasterManage: _canMasterManage,
                              canCreateReplacement: _canCreateReplacement,
                              onNotify: _showUnavailabilityDialog,
                              onStop: _showStopJournalDialog,
                              onReplacement: _showReplacementJournalDialog,
                            ),
                          ],
                          if (!_isClientJournalContext) ...[
                            const SizedBox(height: 16),
                            _ReminderCard(
                              enabled: _remindersEnabled,
                              onChanged: (value) =>
                                  setState(() => _remindersEnabled = value),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                const _TipsCard(),
                const SizedBox(height: 16),
                _AppointmentCard(
                  subject: _subject,
                  clientJournalContext: _isClientJournalContext,
                  onOpenChat: () => widget.onOpenChat(_subject.id),
                ),
                const SizedBox(height: 18),
                _RecommendationsTimeline(
                  steps: _visibleSteps,
                  completedIds: _visibleCompletedIds,
                  expandedIds: _expandedIds,
                  expanded: _recommendationsExpanded,
                  onToggle: _toggleStep,
                  onToggleExpanded: () => setState(
                    () => _recommendationsExpanded = !_recommendationsExpanded,
                  ),
                  onConfirm: _confirmStep,
                  onExtendDeadline: _showDeadlineExtensionDialog,
                  onOpenStep: widget.onOpenStepConfirmation,
                  readOnly: _isClientJournalContext || _journalReadOnly,
                  masterCanExtend: _canMasterManage,
                  compact: true,
                ),
                const SizedBox(height: 16),
                _ProgressCard(progress: _progress),
                const SizedBox(height: 16),
                _IntegrityCard(
                  report: _integrityReport,
                  errorText: _integrityError,
                ),
                if (!_journalReadOnly || _canCreateReplacement) ...[
                  const SizedBox(height: 16),
                  _JournalActionsCard(
                    clientJournalContext: _isClientJournalContext,
                    journalState: _journalState,
                    canClientNotify: _canClientNotify,
                    canMasterManage: _canMasterManage,
                    canCreateReplacement: _canCreateReplacement,
                    onNotify: _showUnavailabilityDialog,
                    onStop: _showStopJournalDialog,
                    onReplacement: _showReplacementJournalDialog,
                  ),
                ],
                if (!_isClientJournalContext) ...[
                  const SizedBox(height: 16),
                  _ReminderCard(
                    enabled: _remindersEnabled,
                    onChanged: (value) =>
                        setState(() => _remindersEnabled = value),
                  ),
                ],
                const SizedBox(height: 16),
                _JournalHistoryCard(
                  events: _events,
                  steps: _visibleSteps,
                  errorText: _eventsError,
                  expanded: true,
                  showFullHistory: _showFullHistory,
                  canToggleFullHistory: true,
                  onToggleExpanded: () {},
                  onToggleFullHistory: () => setState(
                    () => _showFullHistory = !_showFullHistory,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadJournal({bool silent = false}) async {
    final api = widget.api;
    final token = widget.sessionToken;
    final journalId = widget.journalId.trim();
    if (api == null ||
        token == null ||
        token.isEmpty ||
        journalId.isEmpty ||
        journalId == 'mock' ||
        journalId == 'journal') {
      if (silent) {
        return;
      }
      setState(() {
        _backendDetail = null;
        _integrityReport = null;
        _events = const <JournalEventRecord>[];
        _appointmentJournalSummary = null;
        _loading = false;
        _eventsError = null;
        _loadError =
            'Не удалось загрузить журнал ухода: нет активной сессии или выбранного журнала.';
      });
      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
        _integrityError = null;
        _eventsError = null;
      });
    }
    try {
      final detail = await api.careJournal(
        sessionToken: token,
        journalId: journalId,
      );
      JournalIntegrityReport? integrity;
      String? integrityError;
      try {
        integrity = await api.getJournalIntegrity(
          sessionToken: token,
          journalId: journalId,
        );
      } catch (error) {
        integrityError = 'Не удалось проверить целостность журнала: $error';
      }

      var events = const <JournalEventRecord>[];
      String? eventsError;
      try {
        final eventsResponse = await api.getJournalEvents(
          sessionToken: token,
          journalId: journalId,
        );
        events = eventsResponse.items;
      } catch (error) {
        eventsError = 'Не удалось загрузить историю ухода: $error';
      }

      AppointmentJournalSummary? summary;
      if (detail.journal.appointmentId.trim().isNotEmpty) {
        try {
          final journals = await api.getAppointmentJournals(
            sessionToken: token,
            appointmentId: detail.journal.appointmentId,
          );
          for (final item in journals) {
            if (item.id == detail.journal.id) {
              summary = item;
              break;
            }
          }
        } catch (_) {}
      }
      if (!mounted || widget.journalId.trim() != journalId) {
        return;
      }
      setState(() {
        _backendDetail = detail;
        _integrityReport = integrity;
        _events = events;
        _appointmentJournalSummary = summary;
        _loading = false;
        _loadError = null;
        _integrityError = integrityError;
        _eventsError = eventsError;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _backendDetail = null;
        _integrityReport = null;
        _events = const <JournalEventRecord>[];
        _appointmentJournalSummary = null;
        _loading = false;
        _eventsError = null;
        _loadError = 'Не удалось загрузить журнал ухода: $error';
      });
    }
  }

  void _toggleStep(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  Future<void> _confirmStep(String id) async {
    final api = widget.api;
    final token = widget.sessionToken;
    final detail = _backendDetail;
    if (!_isClientJournalContext &&
        api != null &&
        token != null &&
        token.isNotEmpty &&
        detail != null) {
      try {
        await api.confirmCareJournalStep(
          sessionToken: token,
          journalId: detail.journal.id,
          stepId: id,
        );
        if (!mounted) {
          return;
        }
        await _loadJournal();
        if (!mounted) {
          return;
        }
        setState(() {
          _expandedIds.add(id);
        });
        widget.onStepConfirmed(id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Шаг отмечен выполненным'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      } catch (_) {
        if (!mounted) {
          return;
        }
        _showMockAction('Не удалось подтвердить шаг.');
        return;
      }
    }
    if (_isClientJournalContext) {
      _showMockAction('В клиентском журнале шаги подтверждает клиент');
      return;
    }
    _showMockAction(
      'Не удалось подтвердить шаг: журнал не загружен.',
    );
  }

  Future<void> _showUnavailabilityDialog() async {
    final detail = _backendDetail;
    final api = widget.api;
    final token = widget.sessionToken;
    if (detail == null || api == null || token == null || token.isEmpty) {
      _showMockAction('Журнал не загружен.');
      return;
    }

    final payload = await showDialog<_ClientMessageDialogResult>(
      context: context,
      builder: (context) => const _ClientMessageDialog(),
    );
    if (payload == null) {
      return;
    }

    try {
      final unavailablePayload = payload.unavailabilityPayload;
      final problemPayload = payload.problemPayload;
      if (unavailablePayload != null) {
        await api.createJournalUnavailabilityNotice(
          sessionToken: token,
          journalId: detail.journal.id,
          payload: unavailablePayload,
        );
      } else if (problemPayload != null) {
        await api.createJournalClientProblemReport(
          sessionToken: token,
          journalId: detail.journal.id,
          payload: problemPayload,
        );
      }
      if (!mounted) {
        return;
      }
      await _loadJournal();
      if (!mounted) {
        return;
      }
      _showMockAction('Сообщение добавлено в журнал ухода.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMockAction('Не удалось отправить сообщение мастеру: $error');
    }
  }

  Future<void> _showDeadlineExtensionDialog(_CareStep step) async {
    final detail = _backendDetail;
    final api = widget.api;
    final token = widget.sessionToken;
    if (detail == null || api == null || token == null || token.isEmpty) {
      _showMockAction('Журнал не загружен.');
      return;
    }

    final payload = await showDialog<JournalDeadlineExtensionPayload>(
      context: context,
      builder: (context) => _DeadlineExtensionDialog(
        step: step,
        clientMessages: _clientJournalMessages,
      ),
    );
    if (payload == null) {
      return;
    }

    try {
      await api.extendJournalStepDeadline(
        sessionToken: token,
        journalId: detail.journal.id,
        stepId: step.id,
        payload: payload,
      );
      if (!mounted) {
        return;
      }
      await _loadJournal();
      if (!mounted) {
        return;
      }
      _showMockAction('Срок выполнения продлён.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMockAction('Не удалось продлить срок: $error');
    }
  }

  Future<void> _showStopJournalDialog() async {
    final detail = _backendDetail;
    final api = widget.api;
    final token = widget.sessionToken;
    if (detail == null || api == null || token == null || token.isEmpty) {
      _showMockAction('Журнал не загружен.');
      return;
    }

    final payload = await showDialog<JournalStopPayload>(
      context: context,
      builder: (context) => _StopJournalDialog(
        clientMessages: _clientJournalMessages,
      ),
    );
    if (payload == null) {
      return;
    }

    try {
      await api.stopJournal(
        sessionToken: token,
        journalId: detail.journal.id,
        payload: payload,
      );
      if (!mounted) {
        return;
      }
      await _loadJournal();
      if (!mounted) {
        return;
      }
      _showMockAction('Журнал остановлен.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMockAction('Не удалось остановить журнал: $error');
    }
  }

  Future<void> _showReplacementJournalDialog() async {
    final detail = _backendDetail;
    final api = widget.api;
    final token = widget.sessionToken;
    if (detail == null || api == null || token == null || token.isEmpty) {
      _showMockAction('Журнал не загружен.');
      return;
    }

    final payload = await showDialog<ReplacementJournalPayload>(
      context: context,
      builder: (context) => const _ReplacementJournalDialog(),
    );
    if (payload == null) {
      return;
    }

    try {
      final result = await api.createReplacementJournal(
        sessionToken: token,
        journalId: detail.journal.id,
        payload: payload,
      );
      if (!mounted) {
        return;
      }
      _showMockAction('Новый журнал ухода создан.');
      widget.onOpenCareJournalAsMaster(result.newJournalId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMockAction('Не удалось создать новый журнал ухода: $error');
    }
  }

  void _showAlreadyOpen() {
    _showMockAction('Журнал ухода уже открыт');
  }

  void _openReplacementJournal() {
    final journalId = _journalState.replacedByJournalId.trim();
    if (journalId.isEmpty) {
      return;
    }
    if (_isClientJournalContext) {
      widget.onOpenCareJournalAsMaster(journalId);
      return;
    }
    widget.onOpenCareJournal(journalId);
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2D48A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18, color: Color(0xFF9A6700)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF7A4D00),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

class _JournalSubject {
  const _JournalSubject({
    required this.id,
    required this.username,
    required this.name,
    required this.avatarUrl,
    required this.roleLabel,
    required this.service,
    required this.date,
    required this.sessionTime,
    required this.completedStepIds,
    this.showFullName = true,
  });

  final String id;
  final String username;
  final String name;
  final String avatarUrl;
  final String roleLabel;
  final String service;
  final String date;
  final String sessionTime;
  final Set<String> completedStepIds;
  final bool showFullName;

  String get handle => username.startsWith('@') ? username : '@$username';
}

class _JournalStateView {
  const _JournalStateView({
    required this.status,
    required this.label,
    required this.color,
    required this.background,
    required this.stoppedAt,
    required this.stopReason,
    required this.replacedByJournalId,
  });

  factory _JournalStateView.from({
    CareJournalInfo? journal,
    AppointmentJournalSummary? summary,
  }) {
    final summaryStatus = summary?.status.trim() ?? '';
    final journalStatus = journal?.status.trim() ?? '';
    final summaryStoppedAt = summary?.stoppedAt.trim() ?? '';
    final journalStoppedAt = journal?.stoppedAt.trim() ?? '';
    final summaryStopReason = summary?.stopReason.trim() ?? '';
    final journalStopReason = journal?.stopReason.trim() ?? '';
    final summaryReplacedBy = summary?.replacedByJournalId.trim() ?? '';
    final journalReplacedBy = journal?.replacedByJournalId.trim() ?? '';

    final status = summaryStatus.isNotEmpty
        ? summaryStatus
        : journalStatus.isNotEmpty
            ? journalStatus
            : 'active';
    final stoppedAt =
        summaryStoppedAt.isNotEmpty ? summaryStoppedAt : journalStoppedAt;
    final stopReason = summaryStopReason.isNotEmpty
        ? summaryStopReason
        : journalStopReason;
    final replacedByJournalId =
        summaryReplacedBy.isNotEmpty ? summaryReplacedBy : journalReplacedBy;

    final presentation = switch (status) {
      'active' => (
          label: 'Активен',
          color: _accent,
          background: _accent.withValues(alpha: 0.10),
        ),
      'stopped' => (
          label: 'Остановлен',
          color: const Color(0xFF9A6700),
          background: const Color(0xFFFFF4D8),
        ),
      'replaced' => (
          label: 'Заменён новым',
          color: _muted,
          background: _soft,
        ),
      'completed' => (
          label: 'Завершён',
          color: _accent,
          background: _accent.withValues(alpha: 0.10),
        ),
      'draft' => (
          label: 'Черновик',
          color: _muted,
          background: _soft,
        ),
      'awaiting_client_confirmation' => (
          label: 'Ожидает подтверждения',
          color: const Color(0xFF9A6700),
          background: const Color(0xFFFFF4D8),
        ),
      _ => (
          label: 'Статус уточняется',
          color: _muted,
          background: _soft,
        ),
    };

    return _JournalStateView(
      status: status,
      label: presentation.label,
      color: presentation.color,
      background: presentation.background,
      stoppedAt: stoppedAt,
      stopReason: stopReason,
      replacedByJournalId: replacedByJournalId,
    );
  }

  final String status;
  final String label;
  final Color color;
  final Color background;
  final String stoppedAt;
  final String stopReason;
  final String replacedByJournalId;

  bool get isStopped => status == 'stopped';

  bool get isReplaced => status == 'replaced';

  bool get isCompleted => status == 'completed';

  bool get hasStopMarker =>
      stoppedAt.trim().isNotEmpty || stopReason.trim().isNotEmpty;

  bool get isReadOnly => isStopped || isReplaced || isCompleted || hasStopMarker;

  bool get hasLifecycleNotice =>
      isReadOnly ||
      stoppedAt.trim().isNotEmpty ||
      stopReason.trim().isNotEmpty ||
      replacedByJournalId.trim().isNotEmpty;
}

_JournalSubject _subjectFromDetail(CareJournalDetail detail, bool masterContext) {
  final appointment = detail.appointment;
  final person = masterContext ? appointment.client : appointment.master;
  final sessionTime = _sessionTimeLabel(appointment);
  final serviceName = _serviceNameLabel(
    appointment.service.name,
    appointment.service.type,
  );
  return _JournalSubject(
    id: person.id,
    username: person.username,
    name: person.displayName,
    avatarUrl: person.avatarUrl,
    roleLabel: masterContext ? 'Клиент' : 'Мастер',
    service: serviceName,
    date: _dateLabel(appointment.scheduledAt),
    sessionTime: sessionTime,
    completedStepIds: detail.steps
        .where((step) => step.isConfirmed)
        .map((step) => step.id)
        .toSet(),
    showFullName: !person.displayName.startsWith('@'),
  );
}

String _serviceNameLabel(String name, String type) {
  final trimmedName = name.trim();
  if (trimmedName.isNotEmpty && !_isTechnicalServiceValue(trimmedName)) {
    return trimmedName;
  }
  return _serviceValueLabel(type);
}

String _journalZoneLabel(String value) {
  final label = _serviceValueLabel(value);
  return label == 'Сеанс' ? 'Уход после сеанса' : label;
}

String _serviceValueLabel(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    '' => '',
    'session' => 'Сеанс',
    'consultation' => 'Консультация',
    'sketch' => 'Эскиз',
    _ => value.trim(),
  };
}

bool _isTechnicalServiceValue(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'session' ||
      normalized == 'consultation' ||
      normalized == 'sketch';
}

_CareStep _careStepFromBackend(
  CareJournalStep step,
  AppointmentRecord appointment,
) {
  final day = step.dueOffsetDays == null
      ? 'Шаг ${step.stepNumber}'
      : 'День ${step.dueOffsetDays == 0 ? 1 : step.dueOffsetDays}';
  final fallbackDeadline = _deadlineFromAppointment(
    appointment.scheduledAt,
    step.dueOffsetDays ?? step.stepNumber,
  );
  final rawDeadline =
      step.deadlineAt.trim().isEmpty ? fallbackDeadline : step.deadlineAt;
  return _CareStep(
    id: step.id,
    day: day,
    summary: step.title,
    details: step.description,
    completedAt:
        step.confirmedAt.trim().isEmpty ? null : _dateTimeLabel(step.confirmedAt),
    deadlineAt: rawDeadline == null ? null : _dateTimeLabel(rawDeadline),
    deadlineRaw: rawDeadline,
    deadlineExpired: rawDeadline == null ? false : _isPastDeadline(rawDeadline),
    status: step.status,
  );
}

String? _deadlineFromAppointment(String scheduledAt, int dayNumber) {
  final start = DateTime.tryParse(scheduledAt);
  if (start == null || dayNumber <= 0) {
    return null;
  }
  return start.add(Duration(days: dayNumber)).toUtc().toIso8601String();
}

String _dateLabel(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) {
    return value;
  }
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String _dateTimeLabel(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) {
    return value;
  }
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month, $hour:$minute';
}

bool _isPastDeadline(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) {
    return false;
  }
  return DateTime.now().toUtc().isAfter(date.toUtc());
}

String _durationLabel(AppointmentRecord appointment) {
  var minutes = appointment.durationMinutes;
  if (minutes <= 0) {
    final start = DateTime.tryParse(appointment.scheduledAt);
    final end = DateTime.tryParse(appointment.scheduledEndAt);
    if (start != null && end != null) {
      minutes = end.difference(start).inMinutes;
    }
  }
  if (minutes <= 0 && appointment.service.durationHours != null) {
    minutes = (appointment.service.durationHours! * 60).round();
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
  return '${(minutes / 60).toStringAsFixed(1)} ч';
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _sessionTimeLabel(AppointmentRecord appointment) {
  final start = DateTime.tryParse(appointment.scheduledAt);
  final end = DateTime.tryParse(appointment.scheduledEndAt);
  if (start != null && end != null && end.isAfter(start)) {
    return '${_timeLabel(start)}-${_timeLabel(end)}';
  }
  if (start != null) {
    return _timeLabel(start);
  }
  return _durationLabel(appointment);
}

class _CareStep {
  const _CareStep({
    required this.id,
    required this.day,
    required this.summary,
    required this.details,
    required this.status,
    required this.deadlineExpired,
    this.deadlineRaw,
    this.completedAt,
    this.deadlineAt,
  });

  final String id;
  final String day;
  final String summary;
  final String details;
  final String status;
  final bool deadlineExpired;
  final String? deadlineRaw;
  final String? completedAt;
  final String? deadlineAt;

  bool get isCompleted => status == 'completed_by_client';

  bool get isCancelled => status == 'cancelled_due_to_journal_stop';

  bool get isPending => status.isEmpty || status == 'pending';

  bool get canConfirm => isPending && !deadlineExpired;
}

class _ClientJournalMessage {
  const _ClientJournalMessage({
    required this.id,
    required this.reason,
    required this.comment,
    required this.createdAt,
  });

  final String id;
  final String reason;
  final String comment;
  final String createdAt;

  String get dropdownLabel {
    final date = _dateTimeLabel(createdAt);
    if (date.trim().isEmpty || date == createdAt) {
      return reason;
    }
    return '$reason · $date';
  }
}

class _ClientMessageReasonChoice {
  const _ClientMessageReasonChoice({
    required this.label,
    this.requiresAvailabilityPeriod = false,
    this.requiresComment = false,
  });

  final String label;
  final bool requiresAvailabilityPeriod;
  final bool requiresComment;
}

const List<_ClientMessageReasonChoice> _clientMessageReasonChoices = [
  _ClientMessageReasonChoice(
    label: 'Не смогу быть на связи',
    requiresAvailabilityPeriod: true,
  ),
  _ClientMessageReasonChoice(label: 'Есть боль или дискомфорт'),
  _ClientMessageReasonChoice(label: 'Появилось покраснение'),
  _ClientMessageReasonChoice(label: 'Появился отёк'),
  _ClientMessageReasonChoice(label: 'Есть выделения / загноение'),
  _ClientMessageReasonChoice(label: 'Есть подозрение на осложнение'),
  _ClientMessageReasonChoice(label: 'Нужно уточнить рекомендации'),
  _ClientMessageReasonChoice(label: 'Другое', requiresComment: true),
];

class _ClientMessageDialogResult {
  const _ClientMessageDialogResult._({
    this.unavailabilityPayload,
    this.problemPayload,
  });

  factory _ClientMessageDialogResult.unavailability(
    JournalUnavailabilityPayload payload,
  ) {
    return _ClientMessageDialogResult._(unavailabilityPayload: payload);
  }

  factory _ClientMessageDialogResult.problem(
    JournalClientProblemPayload payload,
  ) {
    return _ClientMessageDialogResult._(problemPayload: payload);
  }

  final JournalUnavailabilityPayload? unavailabilityPayload;
  final JournalClientProblemPayload? problemPayload;
}

String _composeMasterActionReason({
  _ClientJournalMessage? clientMessage,
  required String fallbackReason,
  required String masterComment,
}) {
  final parts = <String>[];
  if (clientMessage != null && clientMessage.reason.trim().isNotEmpty) {
    parts.add('Причина клиента: ${clientMessage.reason.trim()}');
    if (clientMessage.comment.trim().isNotEmpty) {
      parts.add('Комментарий клиента: ${clientMessage.comment.trim()}');
    }
  } else if (fallbackReason.trim().isNotEmpty) {
    parts.add(fallbackReason.trim());
  }
  if (masterComment.trim().isNotEmpty) {
    parts.add('Комментарий мастера: ${masterComment.trim()}');
  }
  return parts.join('\n');
}

_ClientJournalMessage? _findClientMessage(
  List<_ClientJournalMessage> messages,
  String id,
) {
  if (id.trim().isEmpty) {
    return null;
  }
  for (final message in messages) {
    if (message.id == id) {
      return message;
    }
  }
  return null;
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
            Text(
              'Назад к записям',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({
    required this.clientJournalContext,
    required this.journalState,
    required this.subject,
    required this.integrityReport,
    required this.integrityError,
    required this.compact,
  });

  final bool clientJournalContext;
  final _JournalStateView journalState;
  final _JournalSubject subject;
  final JournalIntegrityReport? integrityReport;
  final String? integrityError;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final integrity = _IntegrityStateView.from(
      report: integrityReport,
      errorText: integrityError,
    );
    final subtitle = journalState.isReadOnly
        ? 'Этот журнал доступен только для просмотра. История, сроки и проверка целостности сохранены.'
        : 'Рекомендации, подтверждения и изменения фиксируются в истории журнала.';
    final relation = clientJournalContext
        ? 'Запись ${subject.date} · клиент ${subject.handle}'
        : 'Запись ${subject.date} · мастер ${subject.handle}';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: journalState.color.withValues(alpha: 0.22)),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const _IconBubble(icon: Icons.verified_user_outlined),
              Text(
                'Защищённый журнал ухода',
                style: TextStyle(
                  color: _text,
                  fontSize: compact ? 22 : 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              _StatusPill(
                label: journalState.label,
                color: journalState.color,
                background: journalState.background,
              ),
              _StatusPill(
                label: integrity.label,
                color: integrity.color,
                background: integrity.background,
                icon: integrity.icon,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(color: _muted, fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: relation,
                color: _muted,
                background: _soft,
                icon: Icons.event_note_outlined,
              ),
              _StatusPill(
                label: clientJournalContext ? 'Просмотр мастера' : 'Мой уход',
                color: _muted,
                background: _soft,
                icon: clientJournalContext
                    ? Icons.person_search_outlined
                    : Icons.spa_outlined,
              ),
            ],
          ),
          if (journalState.isReadOnly) ...[
            const SizedBox(height: 12),
            Text(
              journalState.isReplaced
                  ? 'Архивная версия: после остановки был создан новый журнал ухода.'
                  : 'Архивная версия: действия внутри журнала недоступны, но история остаётся проверяемой.',
              style: TextStyle(
                color: journalState.color,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JournalLifecycleNotice extends StatelessWidget {
  const _JournalLifecycleNotice({
    required this.journalState,
    required this.onOpenReplacement,
  });

  final _JournalStateView journalState;
  final VoidCallback onOpenReplacement;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[];
    if (journalState.isStopped) {
      messages.add('Журнал остановлен и доступен только для просмотра.');
    } else if (journalState.isReplaced) {
      messages.add('Этот журнал остановлен и доступен только для просмотра.');
    } else if (journalState.isCompleted) {
      messages.add('Журнал завершён и доступен только для просмотра.');
    }
    if (journalState.stoppedAt.trim().isNotEmpty) {
      messages.add('Остановлен: ${_dateTimeLabel(journalState.stoppedAt)}');
    }
    if (journalState.stopReason.trim().isNotEmpty) {
      messages.add('Журнал был остановлен из-за осложнения: ${journalState.stopReason}');
    }
    if (journalState.replacedByJournalId.trim().isNotEmpty) {
      messages.add('После остановки был создан новый журнал ухода.');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: journalState.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: journalState.color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: journalState.color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  messages.join('\n'),
                  style: TextStyle(
                    color: journalState.color,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (journalState.replacedByJournalId.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onOpenReplacement,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Открыть новый журнал'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: journalState.color,
                      side: BorderSide(
                        color: journalState.color.withValues(alpha: 0.38),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.subject,
    required this.clientJournalContext,
    required this.onOpenChat,
  });

  final _JournalSubject subject;
  final bool clientJournalContext;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 620;

    return _SurfaceCard(
      padding: EdgeInsets.all(isNarrow ? 12 : 18),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SubjectImage(
                  avatarUrl: subject.avatarUrl,
                  letterFallback: subject.name,
                  compact: true,
                ),
                const SizedBox(height: 14),
                _AppointmentInfo(
                  subject: subject,
                  clientJournalContext: clientJournalContext,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onOpenChat,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: const BorderSide(color: _line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(0, 42),
                    ),
                    child: Text(clientJournalContext
                        ? 'Написать клиенту'
                        : 'Написать мастеру'),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                _SubjectImage(
                  avatarUrl: subject.avatarUrl,
                  letterFallback: subject.name,
                  compact: false,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _AppointmentInfo(
                    subject: subject,
                    clientJournalContext: clientJournalContext,
                  ),
                ),
                OutlinedButton(
                  onPressed: onOpenChat,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(112, 42),
                  ),
                  child: Text(clientJournalContext
                      ? 'Написать клиенту'
                      : 'Написать мастеру'),
                ),
              ],
            ),
    );
  }
}

class _SubjectImage extends StatelessWidget {
  const _SubjectImage({
    required this.avatarUrl,
    required this.letterFallback,
    required this.compact,
  });

  final String avatarUrl;
  final String letterFallback;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 76.0 : 96.0;
    return ProfileImage(
      avatarUrl: avatarUrl,
      letterFallback: letterFallback,
      width: size,
      height: size,
      borderRadius: 16,
      fit: BoxFit.cover,
    );
  }
}

class _AppointmentInfo extends StatelessWidget {
  const _AppointmentInfo({
    required this.subject,
    required this.clientJournalContext,
  });

  final _JournalSubject subject;
  final bool clientJournalContext;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 28,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 190,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject.handle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subject.showFullName) ...[
                const SizedBox(height: 4),
                Text(
                  subject.name,
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
                subject.roleLabel,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subject.service,
                style: const TextStyle(color: _text),
              ),
            ],
          ),
        ),
        _MetaBlock(
          icon: Icons.calendar_today_outlined,
          label: 'Дата сеанса',
          value: subject.date,
        ),
        _MetaBlock(
          icon: Icons.schedule_outlined,
          label: 'Сеанс',
          value: subject.sessionTime,
        ),
      ],
    );
  }
}

class _MetaBlock extends StatelessWidget {
  const _MetaBlock({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, color: _muted, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendationsTimeline extends StatelessWidget {
  const _RecommendationsTimeline({
    required this.steps,
    required this.completedIds,
    required this.expandedIds,
    required this.expanded,
    required this.onToggle,
    required this.onToggleExpanded,
    required this.onConfirm,
    required this.onExtendDeadline,
    required this.onOpenStep,
    required this.readOnly,
    required this.masterCanExtend,
    required this.compact,
  });

  final List<_CareStep> steps;
  final Set<String> completedIds;
  final Set<String> expandedIds;
  final bool expanded;
  final ValueChanged<String> onToggle;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onConfirm;
  final ValueChanged<_CareStep> onExtendDeadline;
  final ValueChanged<String> onOpenStep;
  final bool readOnly;
  final bool masterCanExtend;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final nextStepIndex = steps.indexWhere((step) =>
        !completedIds.contains(step.id) &&
        !step.isCancelled &&
        !step.deadlineExpired);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Рекомендации мастера',
                style: TextStyle(
                  color: _text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: onToggleExpanded,
              tooltip: expanded ? 'Свернуть' : 'Развернуть',
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: _text,
              ),
            ),
          ],
        ),
        if (expanded) ...[
          const SizedBox(height: 14),
          Stack(
            children: [
              if (!compact)
                Positioned(
                  left: 21,
                  top: 34,
                  bottom: 34,
                  child: Container(
                    width: 1.5,
                    color: _accent.withValues(alpha: 0.35),
                  ),
                ),
              Column(
                children: [
                  for (var i = 0; i < steps.length; i++) ...[
                    _CareStepTile(
                      index: i + 1,
                      step: steps[i],
                      completed: completedIds.contains(steps[i].id),
                      waiting: i > completedIds.length,
                      expanded: expandedIds.contains(steps[i].id),
                      onToggle: () => onToggle(steps[i].id),
                      onConfirm: () => onConfirm(steps[i].id),
                      onExtendDeadline: () => onExtendDeadline(steps[i]),
                      onOpenStep: () => onOpenStep(steps[i].id),
                      readOnly: readOnly,
                      masterCanExtend: masterCanExtend,
                      compact: compact,
                      highlightAsNext: i == nextStepIndex,
                    ),
                    if (i != steps.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CareStepTile extends StatelessWidget {
  const _CareStepTile({
    required this.index,
    required this.step,
    required this.completed,
    required this.waiting,
    required this.expanded,
    required this.onToggle,
    required this.onConfirm,
    required this.onExtendDeadline,
    required this.onOpenStep,
    required this.readOnly,
    required this.masterCanExtend,
    required this.compact,
    required this.highlightAsNext,
  });

  final int index;
  final _CareStep step;
  final bool completed;
  final bool waiting;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onConfirm;
  final VoidCallback onExtendDeadline;
  final VoidCallback onOpenStep;
  final bool readOnly;
  final bool masterCanExtend;
  final bool compact;
  final bool highlightAsNext;

  @override
  Widget build(BuildContext context) {
    final canConfirm = !readOnly && step.canConfirm && !waiting;
    final canExtendDeadline =
        masterCanExtend && step.isPending && !step.isCancelled;
    final markerColor = completed || canConfirm ? _accent : Colors.white;
    final markerBorder = completed || canConfirm ? _accent : _line;
    final cardBackground =
        highlightAsNext ? const Color(0xFFF4FAF7) : _card;
    final cardBorder =
        highlightAsNext ? _accent.withValues(alpha: 0.42) : _line;
    final cardShadow = highlightAsNext
        ? [
            BoxShadow(
              color: _accent.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ]
        : null;

    if (compact) {
      return _buildCompactTile(
        canConfirm: canConfirm,
        canExtendDeadline: canExtendDeadline,
        markerColor: markerColor,
        markerBorder: markerBorder,
        cardBackground: cardBackground,
        cardBorder: cardBorder,
        cardShadow: cardShadow,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(top: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: markerColor,
            shape: BoxShape.circle,
            border: Border.all(color: markerBorder),
            boxShadow: completed || canConfirm
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.16),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: completed
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : Text(
                  '$index',
                  style: TextStyle(
                    color: canConfirm ? Colors.white : _muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: canConfirm ? onOpenStep : onToggle,
              borderRadius: BorderRadius.circular(20),
              child: _SurfaceCard(
            color: cardBackground,
            borderColor: cardBorder,
            shadows: cardShadow,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.day,
                            style: const TextStyle(
                              color: _text,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (highlightAsNext) ...[
                            const SizedBox(height: 8),
                            const _StatusPill(
                              label: 'Следующий шаг',
                              color: _accent,
                              background: Color(0xFFEAF3F0),
                              icon: Icons.flag_outlined,
                            ),
                          ],
                          const SizedBox(height: 7),
                          Text(
                            step.summary,
                            style: const TextStyle(
                              color: _muted,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _StepStatus(
                      step: step,
                      completed: completed,
                      waiting: waiting,
                      completedAt: step.completedAt,
                      compact: false,
                    ),
                    IconButton(
                      onPressed: onToggle,
                      splashRadius: 20,
                      icon: Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
                if (step.deadlineAt != null) ...[
                  const SizedBox(height: 12),
                  _StepDeadline(
                    label: step.deadlineExpired
                        ? 'Срок истёк: ${step.deadlineAt}'
                        : 'Выполнить до: ${step.deadlineAt}',
                    expired: step.deadlineExpired,
                  ),
                ],
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _DetailBox(text: step.details),
                  ),
                  crossFadeState: expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
                if (canConfirm) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: onOpenStep,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(132, 42),
                      ),
                      child: const Text('Подтвердить'),
                    ),
                  ),
                ] else if (canExtendDeadline) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: onExtendDeadline,
                      icon: const Icon(Icons.event_repeat_outlined, size: 18),
                      label: const Text('Продлить срок'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: const BorderSide(color: _line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(150, 42),
                      ),
                    ),
                  ),
                ],
              ],
            ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTile({
    required bool canConfirm,
    required bool canExtendDeadline,
    required Color markerColor,
    required Color markerBorder,
    required Color cardBackground,
    required Color cardBorder,
    required List<BoxShadow>? cardShadow,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: canConfirm ? onOpenStep : onToggle,
        borderRadius: BorderRadius.circular(18),
        child: _SurfaceCard(
          color: cardBackground,
          borderColor: cardBorder,
          shadows: cardShadow,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: markerColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: markerBorder),
                    ),
                    child: completed
                        ? const Icon(Icons.check, color: Colors.white, size: 17)
                        : Text(
                            '$index',
                            style: TextStyle(
                              color: canConfirm ? Colors.white : _muted,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.day,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (highlightAsNext) ...[
                          const SizedBox(height: 8),
                          const _StatusPill(
                            label: 'Следующий шаг',
                            color: _accent,
                            background: Color(0xFFEAF3F0),
                            icon: Icons.flag_outlined,
                          ),
                        ],
                        const SizedBox(height: 5),
                        Text(
                          step.summary,
                          style: const TextStyle(
                            color: _muted,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onToggle,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: _muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StepStatus(
                    step: step,
                    completed: completed,
                    waiting: waiting,
                    completedAt: step.completedAt,
                    compact: true,
                  ),
                  if (step.deadlineAt != null)
                    _StepDeadline(
                      label: step.deadlineExpired
                          ? 'Срок истёк: ${step.deadlineAt}'
                          : 'Выполнить до: ${step.deadlineAt}',
                      expired: step.deadlineExpired,
                    ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _DetailBox(text: step.details, compact: true),
                ),
                crossFadeState: expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
              ),
              if (canConfirm || canExtendDeadline) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: canConfirm
                      ? FilledButton(
                          onPressed: onOpenStep,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size.fromHeight(42),
                          ),
                          child: const Text('Подтвердить'),
                        )
                      : OutlinedButton.icon(
                          onPressed: onExtendDeadline,
                          icon: const Icon(
                            Icons.event_repeat_outlined,
                            size: 18,
                          ),
                          label: const Text('Продлить срок'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            side: const BorderSide(color: _line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size.fromHeight(42),
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepStatus extends StatelessWidget {
  const _StepStatus({
    required this.step,
    required this.completed,
    required this.waiting,
    required this.completedAt,
    required this.compact,
  });

  final _CareStep step;
  final bool completed;
  final bool waiting;
  final String? completedAt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (completed) {
      return Column(
        crossAxisAlignment:
            compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          _StatusPill(
            label: 'Выполнено',
            color: _accent,
            background: _accent.withValues(alpha: 0.09),
            icon: Icons.check,
          ),
          if (completedAt != null) ...[
            const SizedBox(height: 5),
            Text(
              completedAt!,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ],
      );
    }

    return _StatusPill(
      label: _pendingLabel,
      color: _pendingColor,
      background: _pendingBackground,
    );
  }

  String get _pendingLabel {
    if (step.isCancelled) {
      return 'Отменено из-за остановки журнала';
    }
    if (step.deadlineExpired) {
      return 'Срок истёк';
    }
    return 'Ожидает выполнения';
  }

  Color get _pendingColor {
    if (step.isCancelled || step.deadlineExpired || waiting) {
      return _muted;
    }
    return _accent;
  }

  Color get _pendingBackground {
    if (step.isCancelled || step.deadlineExpired || waiting) {
      return _soft;
    }
    return _accent.withValues(alpha: 0.08);
  }
}

class _StepDeadline extends StatelessWidget {
  const _StepDeadline({required this.label, required this.expired});

  final String label;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final color = expired ? const Color(0xFF9A6700) : _muted;
    final background = expired ? const Color(0xFFFFF4D8) : _soft;
    final maxWidth = MediaQuery.sizeOf(context).width - 52;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth < 180 ? 180 : maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_outlined, size: 16, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBox extends StatelessWidget {
  const _DetailBox({required this.text, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Подробная рекомендация от мастера',
            style: TextStyle(color: _text, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: _muted, height: 1.55)),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  static const _tips = [
    (Icons.water_drop_outlined, 'Не распаривайте татуировку баней или горячей ванной.'),
    (Icons.wb_sunny_outlined, 'Избегайте прямых солнечных лучей.'),
    (Icons.sanitizer_outlined, 'Не используйте спиртосодержащие средства.'),
    (Icons.checkroom_outlined, 'Носите свободную одежду и не трите татуировку.'),
  ];

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Что важно знать',
            style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          for (final tip in _tips) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconBubble(icon: tip.$1),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tip.$2,
                    style: const TextStyle(color: _text, height: 1.35),
                  ),
                ),
              ],
            ),
            if (tip != _tips.last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Прогресс заживления',
            style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 116,
                    height: 116,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                      color: _accent,
                      backgroundColor: _soft,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          color: _text,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'выполнено',
                        style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegrityCard extends StatelessWidget {
  const _IntegrityCard({
    required this.report,
    required this.errorText,
  });

  final JournalIntegrityReport? report;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final state = _IntegrityStateView.from(report: report, errorText: errorText);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(icon: Icons.lock_outline),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Проверка журнала',
                  style: TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.description,
            style: const TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          _StatusPill(
            label: state.label,
            color: state.color,
            background: state.background,
            icon: state.icon,
          ),
          if (report != null) ...[
            const SizedBox(height: 12),
            Text(
              'Подписано событий: ${report!.signedEventsCount}/${report!.eventsCount}',
              style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Событий в цепочке: ${report!.hashedEventsCount}/${report!.eventsCount}',
              style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
            ),
          ],
          if (state.issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final issue in state.issues.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  issue,
                  style: TextStyle(
                    color: state.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _IntegrityStateView {
  const _IntegrityStateView({
    required this.label,
    required this.description,
    required this.color,
    required this.background,
    required this.icon,
    required this.issues,
  });

  factory _IntegrityStateView.from({
    required JournalIntegrityReport? report,
    required String? errorText,
  }) {
    if (errorText != null && errorText.trim().isNotEmpty) {
      return _IntegrityStateView(
        label: 'Проверка недоступна',
        description: errorText,
        color: const Color(0xFF9A6700),
        background: const Color(0xFFFFF4D8),
        icon: Icons.pending_actions,
        issues: const <String>[],
      );
    }

    if (report == null) {
      return const _IntegrityStateView(
        label: 'Проверка загружается',
        description:
            'Данные проверки целостности будут показаны после ответа сервера.',
        color: _muted,
        background: _soft,
        icon: Icons.pending_actions,
        issues: <String>[],
      );
    }

    if (report.status == 'valid') {
      return const _IntegrityStateView(
        label: 'Подтверждена',
        description:
            'Целостность подтверждена. Подписи подтверждены для защищённых событий.',
        color: _accent,
        background: Color(0xFFEAF3F0),
        icon: Icons.verified_user_outlined,
        issues: <String>[],
      );
    }

    if (report.status == 'invalid') {
      return _IntegrityStateView(
        label: 'Нарушена',
        description:
            'Обнаружено несоответствие в цепочке событий или цифровых подписях.',
        color: const Color(0xFFB42318),
        background: const Color(0xFFFFE4E2),
        icon: Icons.error_outline,
        issues: report.issues,
      );
    }

    final issues = <String>[];
    if (report.hasLegacyUnhashedEvents) {
      issues.add('Есть события старого формата без защитной отметки.');
    }
    if (report.unsignedHashedEventsCount > 0) {
      issues.add('Есть события без цифровой подписи.');
    }
    return _IntegrityStateView(
      label: 'Частично подтверждена',
      description:
          'Журнал частично подтверждён. В журнале есть события старого формата.',
      color: const Color(0xFF9A6700),
      background: const Color(0xFFFFF4D8),
      icon: Icons.security_outlined,
      issues: issues,
    );
  }

  final String label;
  final String description;
  final Color color;
  final Color background;
  final IconData icon;
  final List<String> issues;
}

class _JournalActionsCard extends StatelessWidget {
  const _JournalActionsCard({
    required this.clientJournalContext,
    required this.journalState,
    required this.canClientNotify,
    required this.canMasterManage,
    required this.canCreateReplacement,
    required this.onNotify,
    required this.onStop,
    required this.onReplacement,
  });

  final bool clientJournalContext;
  final _JournalStateView journalState;
  final bool canClientNotify;
  final bool canMasterManage;
  final bool canCreateReplacement;
  final VoidCallback onNotify;
  final VoidCallback onStop;
  final VoidCallback onReplacement;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    if (canClientNotify) {
      actions.add(
        _JournalActionButton(
          icon: Icons.report_gmailerrorred_outlined,
          label: 'Сообщить мастеру',
          onPressed: onNotify,
        ),
      );
    }
    if (canMasterManage) {
      actions.add(
        _JournalActionButton(
          icon: Icons.stop_circle_outlined,
          label: 'Остановить журнал',
          onPressed: onStop,
        ),
      );
    }
    if (canCreateReplacement) {
      actions.add(
        _JournalActionButton(
          icon: Icons.add_task_outlined,
          label: 'Создать новый журнал ухода',
          onPressed: onReplacement,
        ),
      );
    }

    if (actions.isEmpty && !clientJournalContext) {
      return const SizedBox.shrink();
    }
    final replacementOnly =
        canCreateReplacement && !canClientNotify && !canMasterManage;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replacementOnly ? 'Новый журнал ухода' : 'Действия журнала',
            style: const TextStyle(
              color: _text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (replacementOnly) ...[
            const SizedBox(height: 6),
            const Text(
              'Остановленный журнал останется доступен для просмотра. Новый журнал начнётся как отдельная версия ухода.',
              style: TextStyle(color: _muted, height: 1.35),
            ),
          ],
          const SizedBox(height: 12),
          if (actions.isEmpty)
            Text(
              journalState.replacedByJournalId.trim().isNotEmpty
                  ? 'Для этой записи уже создан новый журнал ухода.'
                  : 'Журнал доступен только для просмотра.',
              style: const TextStyle(color: _muted, height: 1.35),
            )
          else
            Column(
              children: [
                for (final action in actions) ...[
                  action,
                  if (action != actions.last) const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _JournalActionButton extends StatelessWidget {
  const _JournalActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(0, 44),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

class _JournalHistoryCard extends StatelessWidget {
  const _JournalHistoryCard({
    required this.events,
    required this.steps,
    required this.errorText,
    required this.expanded,
    required this.showFullHistory,
    required this.canToggleFullHistory,
    required this.onToggleExpanded,
    required this.onToggleFullHistory,
  });

  final List<JournalEventRecord> events;
  final List<_CareStep> steps;
  final String? errorText;
  final bool expanded;
  final bool showFullHistory;
  final bool canToggleFullHistory;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleFullHistory;

  @override
  Widget build(BuildContext context) {
    final stepById = {for (final step in steps) step.id: step};
    final visibleEvents = showFullHistory || events.length <= 1
        ? events
        : <JournalEventRecord>[events.last];
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(icon: Icons.history_outlined),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'История ухода',
                  style: TextStyle(
                    color: _text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggleExpanded,
                tooltip: expanded ? 'Свернуть' : 'Развернуть',
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _text,
                ),
              ),
            ],
          ),
          if (!expanded)
            const SizedBox.shrink()
          else if (errorText != null && errorText!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _InlineWarning(text: 'Не удалось загрузить историю ухода.'),
          ] else if (events.isEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Событий пока нет. Они появятся после подтверждения шагов или действий мастера.',
              style: TextStyle(color: _muted, height: 1.35),
            ),
          ] else ...[
            const SizedBox(height: 16),
            for (var index = 0; index < visibleEvents.length; index++) ...[
              _HistoryEventTile(
                event: visibleEvents[index],
                step: stepById[visibleEvents[index].stepId],
              ),
              if (_shouldShowReplacementStepNote(visibleEvents[index], steps)) ...[
                const SizedBox(height: 12),
                _HistoryNoteTile(
                  title: 'Рекомендации и шаги ухода зафиксированы в журнале',
                  description:
                      'Добавлено рекомендаций: ${steps.length}. Сроки выполнения сохранены в карточках шагов. Журнал связан с предыдущей остановленной версией.',
                ),
              ],
              if (index != visibleEvents.length - 1) const SizedBox(height: 12),
            ],
            if (canToggleFullHistory && events.length > 1) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onToggleFullHistory,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(0, 42),
                  ),
                  child: Text(
                    showFullHistory
                        ? 'Свернуть историю'
                        : 'Показать всю историю',
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

bool _shouldShowReplacementStepNote(
  JournalEventRecord event,
  List<_CareStep> steps,
) {
  return event.eventType == 'replacement_journal_created' && steps.isNotEmpty;
}

class _HistoryEventTile extends StatelessWidget {
  const _HistoryEventTile({required this.event, required this.step});

  final JournalEventRecord event;
  final _CareStep? step;

  @override
  Widget build(BuildContext context) {
    final title = _eventTitle(event.eventType);
    final description = _eventDescription(event, step);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBubble(icon: _eventIcon(event.eventType)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(color: _muted, height: 1.35),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusPill(
                      label: event.hasSignature ? 'Подписано' : 'Старый формат',
                      color: event.hasSignature ? _accent : const Color(0xFF9A6700),
                      background:
                          event.hasSignature ? const Color(0xFFEAF3F0) : const Color(0xFFFFF4D8),
                      icon: event.hasSignature ? Icons.verified_outlined : Icons.history_outlined,
                    ),
                    if (event.hasHash)
                      _StatusPill(
                        label: 'Зафиксировано',
                        color: _muted,
                        background: Colors.white,
                        icon: Icons.tag_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _dateTimeLabel(event.createdAt),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HistoryNoteTile extends StatelessWidget {
  const _HistoryNoteTile({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _IconBubble(icon: Icons.playlist_add_check_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: _muted, height: 1.35),
                ),
                const SizedBox(height: 8),
                const _StatusPill(
                  label: 'Основано на данных журнала',
                  color: _muted,
                  background: _soft,
                  icon: Icons.fact_check_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2D48A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF7A4D00),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _eventTitle(String eventType) {
  return switch (eventType) {
    'step_completed_by_client' => 'Клиент подтвердил выполнение рекомендации',
    'client_unavailability_notice_added' => 'Клиент сообщил мастеру',
    'client_problem_reported' => 'Клиент сообщил мастеру',
    'deadline_extended' => 'Мастер продлил срок',
    'journal_stopped' => 'Мастер остановил журнал',
    'replacement_journal_created' => 'Создан новый журнал ухода',
    _ => 'Событие журнала',
  };
}

IconData _eventIcon(String eventType) {
  return switch (eventType) {
    'step_completed_by_client' => Icons.check_circle_outline,
    'client_unavailability_notice_added' => Icons.report_gmailerrorred_outlined,
    'client_problem_reported' => Icons.medical_information_outlined,
    'deadline_extended' => Icons.event_repeat_outlined,
    'journal_stopped' => Icons.stop_circle_outlined,
    'replacement_journal_created' => Icons.add_task_outlined,
    _ => Icons.history_outlined,
  };
}

String _eventDescription(JournalEventRecord event, _CareStep? step) {
  final payload = event.payload;
  switch (event.eventType) {
    case 'step_completed_by_client':
      final stepTitle = step?.summary ?? _payloadString(payload, 'step_title');
      final completedAt = _payloadDate(payload, 'completed_at');
      return [
        if (stepTitle.isNotEmpty) stepTitle,
        if (completedAt.isNotEmpty) 'Выполнено: $completedAt',
      ].join('\n');
    case 'client_unavailability_notice_added':
      final from = _payloadDate(payload, 'unavailable_from');
      final until = _payloadDate(payload, 'unavailable_until');
      final reason = _eventReason(event, payload);
      final comment = _payloadString(payload, 'comment');
      return [
        if (from.isNotEmpty || until.isNotEmpty) 'Период: $from — $until',
        if (reason.isNotEmpty) 'Клиент сообщил мастеру: $reason',
        if (comment.isNotEmpty) 'Комментарий клиента: $comment',
      ].join('\n');
    case 'client_problem_reported':
      final reason = _eventReason(event, payload);
      final comment = _payloadString(payload, 'comment');
      return [
        if (reason.isNotEmpty) 'Клиент сообщил мастеру: $reason',
        if (comment.isNotEmpty) 'Комментарий клиента: $comment',
      ].join('\n');
    case 'deadline_extended':
      final oldDeadline = _payloadDate(payload, 'old_deadline_at');
      final newDeadline = _payloadDate(payload, 'new_deadline_at');
      final reason = _eventReason(event, payload);
      return [
        if (oldDeadline.isNotEmpty) 'Было: $oldDeadline',
        if (newDeadline.isNotEmpty) 'Стало: $newDeadline',
        if (reason.isNotEmpty) 'Причина продления: $reason',
      ].join('\n');
    case 'journal_stopped':
      final reason = _eventReason(event, payload);
      final category = _stopCategoryLabel(_payloadString(payload, 'stop_category'));
      return [
        if (category.isNotEmpty) 'Основание: $category',
        if (reason.isNotEmpty) 'Причина остановки: $reason',
      ].join('\n');
    case 'replacement_journal_created':
      final reason = _eventReason(event, payload);
      final version = _payloadString(payload, 'version_number');
      final parentHash = _shortHash(_payloadString(payload, 'parent_final_hash'));
      return [
        if (reason.isNotEmpty) 'Причина нового журнала: $reason',
        if (version.isNotEmpty) 'Версия журнала: $version',
        if (parentHash.isNotEmpty)
          'Связь с предыдущим журналом подтверждена',
      ].join('\n');
  }
  return 'Событие сохранено в истории журнала.';
}

String _payloadString(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value == null) {
    return '';
  }
  return value.toString();
}

String _eventReason(JournalEventRecord event, Map<String, dynamic> payload) {
  final payloadReason = _payloadString(payload, 'reason').trim();
  if (payloadReason.isNotEmpty) {
    return payloadReason;
  }
  return event.reason.trim();
}

String _payloadDate(Map<String, dynamic> payload, String key) {
  final value = _payloadString(payload, key);
  if (value.isEmpty) {
    return '';
  }
  return _dateTimeLabel(value);
}

String _shortHash(String hash) {
  if (hash.length <= 14) {
    return hash;
  }
  return '${hash.substring(0, 10)}…${hash.substring(hash.length - 4)}';
}

String _stopCategoryLabel(String value) {
  return switch (value) {
    'complication' => 'Есть признаки осложнения',
    'in_person_inspection_required' => 'Требуется очный осмотр',
    'client_reported_problem' => 'Клиент сообщил о проблеме',
    'recommendations_no_longer_valid' => 'Рекомендации больше не актуальны',
    'replacement_journal_planned' => 'Создаётся новый журнал ухода',
    'other' => 'Другое',
    _ => 'Другая причина',
  };
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Напоминания',
                  style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'Мы напомним вам о следующем шаге по уходу.',
                  style: TextStyle(color: _muted, height: 1.35),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeColor: _accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

Future<DateTime?> _pickDateTime(
  BuildContext context,
  DateTime initial,
) async {
  final now = DateTime.now();
  final firstDate = now.subtract(const Duration(days: 1));
  final lastDate = initial.isAfter(now.add(const Duration(days: 365)))
      ? initial.add(const Duration(days: 30))
      : now.add(const Duration(days: 365));
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: firstDate,
    lastDate: lastDate,
    locale: const Locale('ru', 'RU'),
    builder: _forceRussianPicker,
    helpText: 'Выберите дату',
    cancelText: 'Отмена',
    confirmText: 'ОК',
    fieldLabelText: 'Дата',
    fieldHintText: 'дд.мм.гггг',
    errorFormatText: 'Введите дату в формате дд.мм.гггг',
    errorInvalidText: 'Дата вне доступного диапазона',
  );
  if (date == null || !context.mounted) {
    return null;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: 'Выберите время',
    cancelText: 'Отмена',
    confirmText: 'ОК',
    hourLabelText: 'Часы',
    minuteLabelText: 'Минуты',
    builder: _forceRussianPicker,
  );
  if (time == null) {
    return null;
  }
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Widget _forceRussianPicker(BuildContext context, Widget? child) {
  final mediaQuery = MediaQuery.maybeOf(context);
  final content = child ?? const SizedBox.shrink();
  final localized = Localizations.override(
    context: context,
    locale: const Locale('ru', 'RU'),
    child: content,
  );
  if (mediaQuery == null) {
    return localized;
  }
  return MediaQuery(
    data: mediaQuery.copyWith(alwaysUse24HourFormat: true),
    child: localized,
  );
}

String _dialogDateTimeLabel(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString();
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day.$month.$year, $hour:$minute';
}

String _backendTimestamp(DateTime value) => value.toUtc().toIso8601String();

class _DialogDateTimeButton extends StatelessWidget {
  const _DialogDateTimeButton({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await _pickDateTime(context, value);
        if (picked != null) {
          onChanged(picked);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          _dialogDateTimeLabel(value),
          style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ClientMessageDialog extends StatefulWidget {
  const _ClientMessageDialog();

  @override
  State<_ClientMessageDialog> createState() => _ClientMessageDialogState();
}

class _ClientMessageDialogState extends State<_ClientMessageDialog> {
  late DateTime _from;
  late DateTime _until;
  final _commentController = TextEditingController();
  _ClientMessageReasonChoice _reason = _clientMessageReasonChoices.first;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = now.add(const Duration(hours: 2));
    _until = now.add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Сообщить мастеру'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<_ClientMessageReasonChoice>(
                value: _reason,
                decoration: const InputDecoration(
                  labelText: 'Причина сообщения',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final choice in _clientMessageReasonChoices)
                    DropdownMenuItem(
                      value: choice,
                      child: Text(choice.label),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _reason = value;
                    _error = null;
                  });
                },
              ),
              if (_reason.requiresAvailabilityPeriod) ...[
                const SizedBox(height: 14),
                _DialogDateTimeButton(
                  label: 'Не смогу быть на связи с',
                  value: _from,
                  onChanged: (value) => setState(() => _from = value),
                ),
                const SizedBox(height: 14),
                _DialogDateTimeButton(
                  label: 'Не смогу быть на связи до',
                  value: _until,
                  onChanged: (value) => setState(() => _until = value),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _commentController,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: _reason.requiresComment
                      ? 'Опишите ситуацию'
                      : 'Комментарий для мастера',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Отправить'),
        ),
      ],
    );
  }

  void _submit() {
    final comment = _commentController.text.trim();
    if (_reason.requiresAvailabilityPeriod && !_from.isBefore(_until)) {
      setState(() => _error = 'Дата начала должна быть раньше даты окончания.');
      return;
    }
    if (_reason.requiresComment && comment.isEmpty) {
      setState(() => _error = 'Опишите ситуацию для мастера.');
      return;
    }
    if (_reason.requiresAvailabilityPeriod) {
      Navigator.of(context).pop(
        _ClientMessageDialogResult.unavailability(
          JournalUnavailabilityPayload(
            unavailableFrom: _backendTimestamp(_from),
            unavailableUntil: _backendTimestamp(_until),
            reason: _reason.label,
            comment: comment,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      _ClientMessageDialogResult.problem(
        JournalClientProblemPayload(
          reason: _reason.label,
          comment: comment,
        ),
      ),
    );
  }
}

class _DeadlineExtensionDialog extends StatefulWidget {
  const _DeadlineExtensionDialog({
    required this.step,
    required this.clientMessages,
  });

  final _CareStep step;
  final List<_ClientJournalMessage> clientMessages;

  @override
  State<_DeadlineExtensionDialog> createState() =>
      _DeadlineExtensionDialogState();
}

class _DeadlineExtensionDialogState extends State<_DeadlineExtensionDialog> {
  late DateTime _deadline;
  final _reasonController = TextEditingController();
  String _selectedClientMessageId = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final currentDeadline = DateTime.tryParse(widget.step.deadlineRaw ?? '');
    final baseline = currentDeadline == null
        ? DateTime.now()
        : currentDeadline.toLocal().isAfter(DateTime.now())
            ? currentDeadline.toLocal()
            : DateTime.now();
    _deadline = baseline.add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Продлить срок выполнения'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.step.summary,
                style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
              ),
              if (widget.step.deadlineAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Текущий срок: ${widget.step.deadlineAt}',
                  style: const TextStyle(color: _muted),
                ),
              ],
              const SizedBox(height: 16),
              _DialogDateTimeButton(
                label: 'Новый срок',
                value: _deadline,
                onChanged: (value) => setState(() => _deadline = value),
              ),
              if (widget.clientMessages.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedClientMessageId,
                  decoration: const InputDecoration(
                    labelText: 'Причина клиента',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Не использовать'),
                    ),
                    for (final message in widget.clientMessages.take(5))
                      DropdownMenuItem(
                        value: message.id,
                        child: Text(
                          'Использовать: ${message.dropdownLabel}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedClientMessageId = value ?? '';
                      _error = null;
                    });
                  },
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: _selectedClientMessageId.isEmpty
                      ? 'Причина продления'
                      : 'Комментарий мастера',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Продлить срок'),
        ),
      ],
    );
  }

  void _submit() {
    final selectedClientMessage = _findClientMessage(
      widget.clientMessages,
      _selectedClientMessageId,
    );
    final reason = _composeMasterActionReason(
      clientMessage: selectedClientMessage,
      fallbackReason: _reasonController.text.trim(),
      masterComment:
          selectedClientMessage == null ? '' : _reasonController.text.trim(),
    );
    if (reason.isEmpty) {
      setState(() => _error = 'Укажите причину продления.');
      return;
    }
    Navigator.of(context).pop(
      JournalDeadlineExtensionPayload(
        newDeadlineAt: _backendTimestamp(_deadline),
        reason: reason,
        linkedClientNoticeEventId: selectedClientMessage?.id,
      ),
    );
  }
}

class _StopJournalDialog extends StatefulWidget {
  const _StopJournalDialog({required this.clientMessages});

  final List<_ClientJournalMessage> clientMessages;

  @override
  State<_StopJournalDialog> createState() => _StopJournalDialogState();
}

class _StopJournalDialogState extends State<_StopJournalDialog> {
  final _reasonController = TextEditingController();
  String _category = 'complication';
  String _selectedClientMessageId = '';
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Остановить журнал ухода'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'После остановки клиент больше не сможет отмечать выполнение рекомендаций. Журнал останется доступен только для просмотра.',
                style: TextStyle(color: _muted, height: 1.35),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Причина остановки',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'complication',
                    child: Text('Есть признаки осложнения'),
                  ),
                  DropdownMenuItem(
                    value: 'in_person_inspection_required',
                    child: Text('Требуется очный осмотр'),
                  ),
                  DropdownMenuItem(
                    value: 'client_reported_problem',
                    child: Text('Клиент сообщил о проблеме'),
                  ),
                  DropdownMenuItem(
                    value: 'recommendations_no_longer_valid',
                    child: Text('Рекомендации больше не актуальны'),
                  ),
                  DropdownMenuItem(
                    value: 'replacement_journal_planned',
                    child: Text('Создаётся новый журнал ухода'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Другое')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _category = value;
                      _error = null;
                    });
                  }
                },
              ),
              if (widget.clientMessages.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedClientMessageId,
                  decoration: const InputDecoration(
                    labelText: 'Причина клиента',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Не использовать'),
                    ),
                    for (final message in widget.clientMessages.take(5))
                      DropdownMenuItem(
                        value: message.id,
                        child: Text(
                          'Использовать: ${message.dropdownLabel}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedClientMessageId = value ?? '';
                      if (_selectedClientMessageId.isNotEmpty) {
                        _category = 'client_reported_problem';
                      }
                      _error = null;
                    });
                  },
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _reasonController,
                maxLines: 4,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: _category == 'other'
                      ? 'Опишите причину'
                      : 'Комментарий мастера',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF9A6700)),
          child: const Text('Остановить журнал'),
        ),
      ],
    );
  }

  void _submit() {
    final selectedClientMessage = _findClientMessage(
      widget.clientMessages,
      _selectedClientMessageId,
    );
    final fallbackReason = _category == 'other'
        ? ''
        : _stopCategoryLabel(_category);
    final reason = _composeMasterActionReason(
      clientMessage: selectedClientMessage,
      fallbackReason: fallbackReason,
      masterComment: _reasonController.text.trim(),
    );
    if (reason.isEmpty) {
      setState(() => _error = 'Укажите причину остановки.');
      return;
    }
    Navigator.of(context).pop(
      JournalStopPayload(
        reason: reason,
        stopCategory: _category,
        linkedClientNoticeEventId: selectedClientMessage?.id,
      ),
    );
  }
}

class _ReplacementJournalDialog extends StatefulWidget {
  const _ReplacementJournalDialog();

  @override
  State<_ReplacementJournalDialog> createState() =>
      _ReplacementJournalDialogState();
}

class _ReplacementJournalDialogState extends State<_ReplacementJournalDialog> {
  final _reasonController = TextEditingController();
  final List<_ReplacementStepDraft> _steps = [_ReplacementStepDraft.initial(1)];
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать новый журнал ухода'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _reasonController,
                maxLines: 2,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Причина создания нового журнала',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _steps.length; i++) ...[
                _ReplacementStepEditor(
                  index: i,
                  draft: _steps[i],
                  canRemove: _steps.length > 1,
                  onRemove: () => setState(() {
                    final removed = _steps.removeAt(i);
                    removed.dispose();
                  }),
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => setState(
                    () => _steps.add(_ReplacementStepDraft.initial(_steps.length + 1)),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить рекомендацию'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Создать журнал'),
        ),
      ],
    );
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Укажите причину создания нового журнала.');
      return;
    }

    final payloadSteps = <ReplacementJournalStepPayload>[];
    for (final step in _steps) {
      final day = int.tryParse(step.dayController.text.trim());
      final title = step.titleController.text.trim();
      final description = step.descriptionController.text.trim();
      if (day == null || day <= 0 || title.isEmpty || description.isEmpty) {
        setState(() => _error = 'Заполните день, название и описание каждой рекомендации.');
        return;
      }
      payloadSteps.add(
        ReplacementJournalStepPayload(
          dayNumber: day,
          title: title,
          description: description,
          deadlineAt: step.deadline == null ? null : _backendTimestamp(step.deadline!),
        ),
      );
    }

    Navigator.of(context).pop(
      ReplacementJournalPayload(reason: reason, steps: payloadSteps),
    );
  }
}

class _ReplacementStepDraft {
  _ReplacementStepDraft({
    required this.dayController,
    required this.titleController,
    required this.descriptionController,
    this.deadline,
  });

  factory _ReplacementStepDraft.initial(int index) {
    return _ReplacementStepDraft(
      dayController: TextEditingController(text: index == 1 ? '1' : '${index * 2 + 1}'),
      titleController: TextEditingController(),
      descriptionController: TextEditingController(),
      deadline: DateTime.now().add(Duration(days: index)),
    );
  }

  final TextEditingController dayController;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  DateTime? deadline;

  void dispose() {
    dayController.dispose();
    titleController.dispose();
    descriptionController.dispose();
  }
}

class _ReplacementStepEditor extends StatelessWidget {
  const _ReplacementStepEditor({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _ReplacementStepDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Рекомендация ${index + 1}',
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFB42318)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.dayController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'День',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.titleController,
            decoration: const InputDecoration(
              labelText: 'Название',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Описание',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickDateTime(
                      context,
                      draft.deadline ?? DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      draft.deadline = picked;
                      onChanged();
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    draft.deadline == null
                        ? 'Назначить срок'
                        : 'Срок: ${_dialogDateTimeLabel(draft.deadline!)}',
                  ),
                ),
              ),
              if (draft.deadline != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Убрать срок',
                  onPressed: () {
                    draft.deadline = null;
                    onChanged();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 40;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth < 180 ? 180 : maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
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
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: _accent, size: 21),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.shadows,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? _line),
        boxShadow: shadows ?? AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: child,
    );
  }
}
