import 'dart:async';

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
const _warningBg = AuthenticatedDashboardTheme.warningBg;
const _warning = AuthenticatedDashboardTheme.warning;

class RecommendationApprovalScreen extends StatefulWidget {
  const RecommendationApprovalScreen({
    super.key,
    required this.user,
    required this.userName,
    required this.appointmentId,
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
    required this.onApproved,
  });

  final AuthUser? user;
  final String userName;
  final String appointmentId;
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
  final void Function(String appointmentId, String journalId) onApproved;

  @override
  State<RecommendationApprovalScreen> createState() =>
      _RecommendationApprovalScreenState();
}

class _RecommendationApprovalScreenState
    extends State<RecommendationApprovalScreen> {
  late final AutoRefreshController _chatAutoRefresh;
  final TextEditingController _questionController = TextEditingController();
  final FocusNode _questionFocusNode = FocusNode();
  RecommendationsPlan? _plan;
  AppointmentRecord? _appointment;
  ChatThreadSummary? _chatThread;
  List<ChatMessage> _chatMessages = const <ChatMessage>[];
  bool _approved = false;
  bool _showAll = false;
  bool _loading = true;
  bool _approving = false;
  bool _chatLoading = false;
  bool _chatSending = false;
  String? _loadError;
  String? _chatError;

  static const _background = AuthenticatedDashboardTheme.background;
  static const _card = AuthenticatedDashboardTheme.card;
  static const _accent = AuthenticatedDashboardTheme.accent;
  static const _text = AuthenticatedDashboardTheme.text;
  static const _muted = AuthenticatedDashboardTheme.muted;
  static const _line = AuthenticatedDashboardTheme.line;
  static const _soft = AuthenticatedDashboardTheme.soft;
  static const _warningBg = AuthenticatedDashboardTheme.warningBg;
  static const _warning = AuthenticatedDashboardTheme.warning;

  @override
  void initState() {
    super.initState();
    _chatAutoRefresh = AutoRefreshController(
      interval: const Duration(seconds: 3),
      onRefresh: () => _loadChat(silent: true),
    )..start();
    _loadRecommendations();
  }

  @override
  void didUpdateWidget(covariant RecommendationApprovalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.appointmentId != widget.appointmentId) {
      _loadRecommendations();
    }
  }

  @override
  void dispose() {
    _chatAutoRefresh.dispose();
    _questionController.dispose();
    _questionFocusNode.dispose();
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
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 40 : 16,
        isDesktop ? 30 : 18,
        isDesktop ? 40 : 16,
        isDesktop ? 42 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackLink(onTap: widget.onOpenAppointments),
              const SizedBox(height: 20),
              const _PageTitle(),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_loadError != null) ...[
                const SizedBox(height: 12),
                _BackendErrorState(
                  message: _loadError!,
                  onRetry: _loadRecommendations,
                ),
              ],
              if (_loadError == null) ...[
                const SizedBox(height: 20),
                if (isDesktop)
                  Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: [
                          _AppointmentCard(
                            appointment: _appointment,
                            recommendationStatus: _plan?.status ?? 'sent',
                            approved: _approved,
                          ),
                          const SizedBox(height: 16),
                          _RecommendationsCard(
                            items: _recommendations,
                            showAll: _showAll,
                            onToggleShowAll: () =>
                                setState(() => _showAll = !_showAll),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          _DecisionCard(
                            approved: _approved,
                            onApprove: () => _approve(),
                            onAsk: _focusQuestionInput,
                          ),
                          const SizedBox(height: 16),
                          _DialogCard(
                            masterName: _masterName,
                            currentUserId: widget.user?.id ?? '',
                            messages: _chatMessages,
                            loading: _chatLoading,
                            sending: _chatSending,
                            errorText: _chatError,
                            controller: _questionController,
                            focusNode: _questionFocusNode,
                            onRetry: () => _loadChat(),
                            onSend: _sendQuestion,
                          ),
                          const SizedBox(height: 16),
                          const _SecurityNote(),
                        ],
                      ),
                    ),
                  ],
                )
                else ...[
                  _AppointmentCard(
                    appointment: _appointment,
                    recommendationStatus: _plan?.status ?? 'sent',
                    approved: _approved,
                  ),
                  const SizedBox(height: 14),
                  _RecommendationsCard(
                    items: _recommendations,
                    showAll: _showAll,
                    onToggleShowAll: () => setState(() => _showAll = !_showAll),
                  ),
                  const SizedBox(height: 14),
                  _DecisionCard(
                    approved: _approved,
                    onApprove: () => _approve(),
                    onAsk: _focusQuestionInput,
                  ),
                  const SizedBox(height: 14),
                  _DialogCard(
                    masterName: _masterName,
                    currentUserId: widget.user?.id ?? '',
                    messages: _chatMessages,
                    loading: _chatLoading,
                    sending: _chatSending,
                    errorText: _chatError,
                    controller: _questionController,
                    focusNode: _questionFocusNode,
                    onRetry: () => _loadChat(),
                    onSend: _sendQuestion,
                  ),
                  const SizedBox(height: 14),
                  const _SecurityNote(),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<_CareRecommendation> get _recommendations {
    final steps = _plan?.steps ?? const <RecommendationStep>[];
    if (steps.isEmpty) {
      return const <_CareRecommendation>[];
    }
    return steps
        .map(
          (step) => _CareRecommendation(
            summary: step.title,
            details: step.description,
            deadlineLabel: _deadlineLabelForStep(step),
          ),
        )
        .toList();
  }

  String? _deadlineLabelForStep(RecommendationStep step) {
    final explicit = DateTime.tryParse(step.dueAt)?.toLocal();
    final start = DateTime.tryParse(_appointment?.scheduledAt ?? '')?.toLocal();
    final day = step.dueOffsetDays ?? step.stepNumber;
    final deadline = explicit ??
        (start != null && day > 0 ? start.add(Duration(days: day)) : null);
    if (deadline == null) {
      return null;
    }
    return 'Выполнить до: ${_formatDeadline(deadline)}';
  }

  static String _formatDeadline(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.${value.year}, $hour:$minute';
  }

  String get _masterName {
    final item = _appointment;
    if (item == null) {
      return '@master';
    }
    final displayName = item.master.displayName.trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final username = item.master.username.trim();
    if (username.isEmpty) {
      return '@master';
    }
    return username.startsWith('@') ? username : '@$username';
  }

  Future<void> _loadRecommendations() async {
    final api = widget.api;
    final token = widget.sessionToken;
    final appointmentId = widget.appointmentId.trim();
    if (api == null ||
        token == null ||
        token.isEmpty ||
        appointmentId.isEmpty ||
        appointmentId == 'mock') {
      setState(() {
        _appointment = null;
        _plan = null;
        _chatThread = null;
        _chatMessages = const <ChatMessage>[];
        _chatLoading = false;
        _chatError = null;
        _approved = false;
        _loading = false;
        _loadError =
            'Не удалось загрузить рекомендации: нет реальной backend-сессии или appointmentId.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
      _chatThread = null;
      _chatMessages = const <ChatMessage>[];
      _chatLoading = false;
      _chatError = null;
    });
    try {
      final response = await api.clientAppointmentRecommendations(
        sessionToken: token,
        appointmentId: appointmentId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _appointment = response.appointment;
        _plan = response.recommendations;
        _approved = response.recommendations.isApproved;
        _loading = false;
        _loadError = null;
      });
      unawaited(_loadChat());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _appointment = null;
        _plan = null;
        _chatThread = null;
        _chatMessages = const <ChatMessage>[];
        _chatLoading = false;
        _chatError = null;
        _approved = false;
        _loading = false;
        _loadError = 'Не удалось загрузить рекомендации: $error';
      });
    }
  }

  Future<void> _approve() async {
    if (_approved || _approving) {
      return;
    }

    final api = widget.api;
    final token = widget.sessionToken;
    final appointmentId = widget.appointmentId.trim();
    if (api == null ||
        token == null ||
        token.isEmpty ||
        appointmentId.isEmpty ||
        appointmentId == 'mock') {
      _showMockAction(
        'Не удалось подтвердить рекомендации: нет реальной backend-сессии или appointmentId',
      );
      return;
    }

    setState(() => _approving = true);
    try {
      final response = await api.approveAppointmentRecommendations(
        sessionToken: token,
        appointmentId: appointmentId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _appointment = response.appointment;
        _plan = response.recommendations;
        _approved = true;
        _approving = false;
        _loadError = null;
      });
      widget.onApproved(
        appointmentId,
        response.appointment?.journalId ?? '',
      );
      _showMockAction('Рекомендации подтверждены. Можно открыть журнал ухода.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _approving = false);
      _showMockAction('Не удалось подтвердить рекомендации через backend: $error');
    }
  }

  void _focusQuestionInput() {
    _questionFocusNode.requestFocus();
    if (_chatThread == null && !_chatLoading) {
      unawaited(_loadChat());
    }
  }

  Future<ChatThreadSummary?> _ensureChatThread() async {
    final existing = _chatThread;
    if (existing != null) {
      return existing;
    }

    final api = widget.api;
    final token = widget.sessionToken;
    final masterId = _appointment?.master.id.trim() ?? '';
    if (api == null || token == null || token.isEmpty || masterId.isEmpty) {
      return null;
    }

    final thread = await api.getOrCreateChatWithUser(
      sessionToken: token,
      userId: masterId,
    );
    if (mounted) {
      setState(() => _chatThread = thread);
    }
    return thread;
  }

  Future<void> _loadChat({bool silent = false}) async {
    final api = widget.api;
    final token = widget.sessionToken;
    final masterId = _appointment?.master.id.trim() ?? '';
    if (api == null || token == null || token.isEmpty || masterId.isEmpty) {
      if (mounted) {
        if (silent) {
          return;
        }
        setState(() {
          _chatLoading = false;
          _chatMessages = const <ChatMessage>[];
          _chatError = null;
        });
      }
      return;
    }

    if (!silent) {
      setState(() {
        _chatLoading = true;
        _chatError = null;
      });
    }
    try {
      final thread = await _ensureChatThread();
      if (thread == null) {
        throw StateError('chat thread is unavailable');
      }
      final messages = await api.getChatMessages(
        sessionToken: token,
        threadId: thread.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _chatThread = thread;
        _chatMessages = messages;
        _chatLoading = false;
        _chatError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _chatLoading = false;
        _chatError = 'Не удалось загрузить диалог';
      });
    }
  }

  Future<void> _sendQuestion() async {
    final text = _questionController.text.trim();
    if (text.isEmpty) {
      _showMockAction('Напишите вопрос или уточнение для мастера');
      return;
    }

    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      widget.onOpenChat('messages');
      return;
    }

    setState(() => _chatSending = true);
    try {
      final thread = await _ensureChatThread();
      if (thread == null) {
        throw StateError('chat thread is unavailable');
      }
      final message = await api.sendChatMessage(
        sessionToken: token,
        threadId: thread.id,
        text: text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _chatMessages = [..._chatMessages, message];
        _questionController.clear();
        _chatSending = false;
        _chatError = null;
      });
      _showMockAction('Сообщение отправлено мастеру');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _chatSending = false;
        _chatError = 'Не удалось отправить сообщение';
      });
      _showMockAction('Не удалось отправить сообщение');
    }
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

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Подтверждение рекомендаций',
          style: TextStyle(
            color: _RecommendationApprovalScreenState._text,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Мастер подготовил рекомендации по уходу для вашей татуировки. Ознакомьтесь и подтвердите их или задайте вопрос.',
          style: TextStyle(
            color: _RecommendationApprovalScreenState._muted,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.recommendationStatus,
    required this.approved,
  });

  final AppointmentRecord? appointment;
  final String recommendationStatus;
  final bool approved;

  @override
  Widget build(BuildContext context) {
    final item = appointment;
    final masterHandle = item == null ? '@master' : _handle(item.master.username);
    final masterFullName = item?.master.displayName.trim() ?? '';
    final avatarFallback = masterFullName.isNotEmpty ? masterFullName : masterHandle;
    final serviceName = item == null
        ? 'Услуга не загружена'
        : _nonEmpty(item.service.name, fallback: 'Услуга');
    final serviceDetails = item == null
        ? 'Детали записи не загружены'
        : _serviceDetails(item);
    final date = item == null ? 'Дата не загружена' : _dateLabel(item.scheduledAt);
    final place = item == null
        ? 'Локация не загружена'
        : _nonEmpty(item.master.city, fallback: 'Локация уточняется');
    final status = _statusLabel(recommendationStatus, approved);

    return _SurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        masterHandle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _RecommendationApprovalScreenState._text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (item?.master.isMaster ?? true)
                      const Icon(
                        Icons.verified,
                        color: _RecommendationApprovalScreenState._accent,
                        size: 18,
                      ),
                  ],
                ),
                if (masterFullName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    masterFullName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _RecommendationApprovalScreenState._muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  serviceName,
                  style: const TextStyle(
                    color: _RecommendationApprovalScreenState._muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  serviceDetails,
                  style: const TextStyle(
                    color: _RecommendationApprovalScreenState._muted,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    _InfoLine(icon: Icons.calendar_today_outlined, text: date),
                    _InfoLine(icon: Icons.place_outlined, text: place),
                  ],
                ),
                const SizedBox(height: 14),
                _StatusNote(
                  label: status,
                  icon: approved
                      ? Icons.check_circle_outline
                      : Icons.hourglass_bottom_outlined,
                ),
            ],
          );

          if (isCompact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _avatar(
                  size: 72,
                  avatarUrl: item?.master.avatarUrl ?? '',
                  letterFallback: avatarFallback,
                ),
                const SizedBox(width: 14),
                Expanded(child: info),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(
                size: 96,
                avatarUrl: item?.master.avatarUrl ?? '',
                letterFallback: avatarFallback,
              ),
              const SizedBox(width: 20),
              Expanded(child: info),
            ],
          );
        },
      ),
    );
  }

  static String _handle(String username) {
    final handle = username.trim();
    if (handle.isEmpty) {
      return '@master';
    }
    return handle.startsWith('@') ? handle : '@$handle';
  }

  static String _nonEmpty(String value, {required String fallback}) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  static String _serviceDetails(AppointmentRecord item) {
    final note = item.clientNote.trim();
    if (note.isNotEmpty) {
      return note;
    }
    final details = [
      item.service.category.trim(),
      item.service.style.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    return details.isEmpty ? 'Детали записи уточняются' : details;
  }

  static String _dateLabel(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) {
      return 'Дата уточняется';
    }
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  static String _statusLabel(String status, bool approved) {
    if (approved || status == 'approved') {
      return 'Рекомендации подтверждены';
    }
    return 'Ожидает вашего подтверждения';
  }

  Widget _avatar({
    required double size,
    required String avatarUrl,
    required String letterFallback,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: ProfileImage(
        avatarUrl: avatarUrl,
        letterFallback: letterFallback,
        width: size,
        height: size,
        borderRadius: 14,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({
    required this.items,
    required this.showAll,
    required this.onToggleShowAll,
  });

  final List<_CareRecommendation> items;
  final bool showAll;
  final VoidCallback onToggleShowAll;


  @override
  Widget build(BuildContext context) {
    final visible = showAll ? items : items.take(4).toList();

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Рекомендации мастера',
                  style: TextStyle(
                    color: _RecommendationApprovalScreenState._text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _SmallPill(
                label: showAll ? 'Скрыть' : 'Показать все (${items.length})',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            const Text(
              'Рекомендации пока не добавлены',
              style: TextStyle(color: _RecommendationApprovalScreenState._muted),
            )
          else
            for (var index = 0; index < visible.length; index++) ...[
              _RecommendationLine(number: index + 1, item: visible[index]),
              if (index != visible.length - 1) const Divider(height: 22),
            ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onToggleShowAll,
              icon: Icon(showAll
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down),
              label: Text(showAll
                  ? 'Скрыть часть рекомендаций'
                  : 'Показать полностью'),
              style: TextButton.styleFrom(
                foregroundColor: _RecommendationApprovalScreenState._accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CareRecommendation {
  const _CareRecommendation({
    required this.summary,
    required this.details,
    required this.deadlineLabel,
  });

  final String summary;
  final String details;
  final String? deadlineLabel;
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.approved,
    required this.onApprove,
    required this.onAsk,
  });

  final bool approved;
  final VoidCallback onApprove;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Что вы хотите сделать?',
            style: TextStyle(
              color: _RecommendationApprovalScreenState._text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Пожалуйста, подтвердите рекомендации или задайте вопрос мастеру.',
            style: TextStyle(
              color: _RecommendationApprovalScreenState._muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: approved ? null : onApprove,
            icon: Icon(approved ? Icons.check_circle : Icons.check),
            label: Text(approved ? 'Рекомендации подтверждены' : 'Подтвердить рекомендации'),
            style: FilledButton.styleFrom(
              backgroundColor: _RecommendationApprovalScreenState._accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'или',
              style: TextStyle(color: _RecommendationApprovalScreenState._muted),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onAsk,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Задать вопрос / уточнить'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _RecommendationApprovalScreenState._accent,
              minimumSize: const Size(0, 48),
              side: const BorderSide(color: _RecommendationApprovalScreenState._line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            approved
                ? 'Журнал ухода можно создать и отслеживать по шагам.'
                : 'После подтверждения мастер сможет создать журнал ухода.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _RecommendationApprovalScreenState._muted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogCard extends StatelessWidget {
  const _DialogCard({
    required this.masterName,
    required this.currentUserId,
    required this.messages,
    required this.loading,
    required this.sending,
    required this.errorText,
    required this.controller,
    required this.focusNode,
    required this.onRetry,
    required this.onSend,
  });

  final String masterName;
  final String currentUserId;
  final List<ChatMessage> messages;
  final bool loading;
  final bool sending;
  final String? errorText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final visibleMessages = messages.length > 6
        ? messages.sublist(messages.length - 6)
        : messages;
    return _SurfaceCard(
      maxWidth: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Диалог с мастером',
                  style: TextStyle(
                    color: _RecommendationApprovalScreenState._text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _SmallPill(
                label: loading
                    ? 'Загружаем'
                    : _dialogCountLabel(messages.length),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (loading) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 12),
          ],
          if (errorText != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF2D48A)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 18,
                    color: Color(0xFF9A6700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorText!,
                      style: const TextStyle(
                        color: Color(0xFF7A4D00),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(onRetry()),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (visibleMessages.isEmpty && !loading)
            _MessageBubble(
              author: masterName,
              time: '',
              text:
                  'Если у вас есть вопрос по рекомендациям, напишите мастеру в этом диалоге.',
            )
          else
            for (final message in visibleMessages) ...[
              _MessageBubble(
                author: message.senderId == currentUserId ? 'Вы' : masterName,
                time: _shortDialogTime(message.createdAt),
                text: message.body,
                mine: message.senderId == currentUserId,
                deleted: message.isDeleted,
              ),
              const SizedBox(height: 10),
            ],
          if (messages.length > visibleMessages.length) ...[
            const SizedBox(height: 2),
            Center(
              child: TextButton(
                onPressed: () => unawaited(onRetry()),
                child: const Text('Обновить диалог'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Опишите ваш вопрос или уточнение...',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accent),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!sending) {
                      unawaited(onSend());
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: sending ? null : () => unawaited(onSend()),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.author,
    required this.time,
    required this.text,
    this.mine = false,
    this.deleted = false,
  });

  final String author;
  final String time;
  final String text;
  final bool mine;
  final bool deleted;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 450),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFFF2F7F4) : _soft,
            borderRadius: BorderRadius.circular(14),
            border: deleted ? Border.all(color: _line) : null,
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      author,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (time.trim().isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text(
                      time,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                text,
                style: TextStyle(
                  color: _text,
                  height: 1.45,
                  fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dialogCountLabel(int count) {
  if (count == 0) {
    return 'Диалог открыт';
  }
  final mod100 = count % 100;
  final mod10 = count % 10;
  final word = mod100 >= 11 && mod100 <= 14
      ? 'сообщений'
      : mod10 == 1
          ? 'сообщение'
          : mod10 >= 2 && mod10 <= 4
              ? 'сообщения'
              : 'сообщений';
  return '$count $word';
}

String _shortDialogTime(String raw) {
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) {
    return '';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(parsed.day)}.${two(parsed.month)}, ${two(parsed.hour)}:${two(parsed.minute)}';
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        children: const [
          Icon(Icons.lock_outline, size: 18, color: _muted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'После вашего подтверждения мастер сможет создать журнал ухода и отслеживать процесс заживления.',
              style: TextStyle(color: _muted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationLine extends StatefulWidget {
  const _RecommendationLine({required this.number, required this.item});

  final int number;
  final _CareRecommendation item;

  @override
  State<_RecommendationLine> createState() => _RecommendationLineState();
}

class _RecommendationLineState extends State<_RecommendationLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _soft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${widget.number}',
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.summary,
                style: const TextStyle(color: _muted, height: 1.45),
              ),
              if (widget.item.deadlineLabel != null) ...[
                const SizedBox(height: 6),
                _RecommendationDeadlineLine(
                  label: widget.item.deadlineLabel!,
                ),
              ],
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAF8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Подробная рекомендация от мастера',
                        style: TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.item.details,
                        style: const TextStyle(color: _text, height: 1.55),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
            _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          ),
          color: _muted,
          tooltip: _expanded ? 'Свернуть' : 'Показать подробно',
        ),
      ],
    );
  }
}

class _RecommendationDeadlineLine extends StatelessWidget {
  const _RecommendationDeadlineLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.event_available_outlined,
          size: 15,
          color: _accent,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _warningBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _warning,
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

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
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
        Icon(icon, size: 16, color: _muted),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: child,
    );
    final width = maxWidth;
    if (width == null) {
      return card;
    }
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: card,
      ),
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.arrow_back, size: 18),
      label: const Text('Назад к записи'),
      style: TextButton.styleFrom(foregroundColor: _muted),
    );
  }
}
