import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';

const _background = AuthenticatedDashboardTheme.background;
const _card = AuthenticatedDashboardTheme.card;
const _accent = AuthenticatedDashboardTheme.accent;
const _text = AuthenticatedDashboardTheme.text;
const _muted = AuthenticatedDashboardTheme.muted;
const _line = AuthenticatedDashboardTheme.line;
const _soft = AuthenticatedDashboardTheme.soft;

class CareStepConfirmationScreen extends StatefulWidget {
  const CareStepConfirmationScreen({
    super.key,
    required this.user,
    required this.userName,
    required this.journalId,
    required this.stepId,
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
    required this.completedStepIds,
    required this.onStepConfirmed,
    required this.onBack,
  });

  final AuthUser? user;
  final String userName;
  final String journalId;
  final String stepId;
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
  final Set<String> completedStepIds;
  final ValueChanged<String> onStepConfirmed;
  final VoidCallback onBack;

  @override
  State<CareStepConfirmationScreen> createState() =>
      _CareStepConfirmationScreenState();
}

class _CareStepConfirmationScreenState
    extends State<CareStepConfirmationScreen> {
  final TextEditingController _questionController = TextEditingController();
  CareJournalDetail? _backendDetail;
  bool _loading = true;
  bool _confirmed = false;
  bool _showFull = true;
  String? _loadError;

  _StepInfo get _step {
    final backendStep = _backendStep;
    return _stepInfoFromBackend(backendStep!);
  }

  CareJournalStep? get _backendStep {
    final detail = _backendDetail;
    if (detail == null) {
      return null;
    }
    for (final step in detail.steps) {
      if (step.id == widget.stepId) {
        return step;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _confirmed = false;
    _questionController.addListener(() => setState(() {}));
    _loadJournal();
  }

  @override
  void didUpdateWidget(CareStepConfirmationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepId != widget.stepId ||
        oldWidget.completedStepIds != widget.completedStepIds ||
        oldWidget.journalId != widget.journalId) {
      _confirmed = _backendStep?.isConfirmed ?? false;
      _loadJournal();
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
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
    if (_loading && _backendDetail == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_loadError != null || _backendDetail == null || _backendStep == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _BackendErrorState(
            message: _loadError ?? 'Шаг ухода не найден в журнале ухода.',
            onRetry: _loadJournal,
          ),
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
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackLink(onTap: widget.onBack),
              const SizedBox(height: 24),
              _StepHeader(step: _step),
              const SizedBox(height: 26),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _RecommendationCard(
                        step: _step,
                        showFull: _showFull,
                        onToggle: () =>
                            setState(() => _showFull = !_showFull),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          _ConfirmCard(
                            confirmed: _confirmed,
                            onConfirm: _confirmStep,
                            onAsk: _focusQuestion,
                          ),
                          const SizedBox(height: 16),
                          _QuestionForm(
                            controller: _questionController,
                            onSend: _sendQuestion,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _RecommendationCard(
                  step: _step,
                  showFull: _showFull,
                  onToggle: () => setState(() => _showFull = !_showFull),
                ),
                const SizedBox(height: 14),
                _ConfirmCard(
                  confirmed: _confirmed,
                  onConfirm: _confirmStep,
                  onAsk: _focusQuestion,
                ),
                const SizedBox(height: 14),
                _QuestionForm(
                  controller: _questionController,
                  onSend: _sendQuestion,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadJournal() async {
    final api = widget.api;
    final token = widget.sessionToken;
    final journalId = widget.journalId.trim();
    if (api == null ||
        token == null ||
        token.isEmpty ||
        journalId.isEmpty ||
        journalId == 'mock' ||
        journalId == 'journal') {
      setState(() {
        _backendDetail = null;
        _loading = false;
        _confirmed = false;
        _loadError =
            'Не удалось загрузить шаг ухода: нет активной сессии или выбранного журнала.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final detail = await api.careJournal(
        sessionToken: token,
        journalId: journalId,
      );
      if (!mounted || widget.journalId.trim() != journalId) {
        return;
      }
      CareJournalStep? step;
      for (final item in detail.steps) {
        if (item.id == widget.stepId) {
          step = item;
          break;
        }
      }
      setState(() {
        _backendDetail = detail;
        _confirmed = step?.isConfirmed ?? false;
        _loading = false;
        _loadError = step == null ? 'Шаг ухода не найден в журнале ухода.' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _backendDetail = null;
        _confirmed = false;
        _loading = false;
        _loadError = 'Не удалось загрузить шаг ухода: $error';
      });
    }
  }

  Future<void> _confirmStep() async {
    final api = widget.api;
    final token = widget.sessionToken;
    final detail = _backendDetail;
    if (api != null && token != null && token.isNotEmpty && detail != null) {
      try {
        final nextDetail = await api.confirmCareJournalStep(
          sessionToken: token,
          journalId: detail.journal.id,
          stepId: widget.stepId,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _backendDetail = nextDetail;
          _confirmed = true;
          _loadError = null;
        });
        widget.onStepConfirmed(widget.stepId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Шаг отмечен выполненным'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      } catch (error) {
        if (!mounted) {
          return;
        }
        _showMockAction('Не удалось подтвердить шаг. Попробуйте открыть журнал заново.');
        return;
      }
    }
    _showMockAction('Не удалось подтвердить шаг: журнал не загружен.');
  }

  void _focusQuestion() {
    FocusScope.of(context).requestFocus(FocusNode());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Опишите вопрос в поле ниже'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _sendQuestion() {
    final text = _questionController.text.trim();
    if (text.isEmpty) {
      _focusQuestion();
      return;
    }
    _questionController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Вопрос отправлен мастеру'),
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

class _StepInfo {
  const _StepInfo({
    required this.number,
    required this.title,
    required this.shortText,
    required this.details,
    required this.reason,
  });

  final int number;
  final String title;
  final String shortText;
  final List<String> details;
  final String reason;
}

_StepInfo _stepInfoFromBackend(CareJournalStep step) {
  final title = step.dueOffsetDays == null
      ? 'Шаг ${step.stepNumber}'
      : 'День ${step.dueOffsetDays == 0 ? 1 : step.dueOffsetDays}';
  return _StepInfo(
    number: step.stepNumber,
    title: title,
    shortText: step.title,
    details: [step.description],
    reason: 'Рекомендация мастера сохранена в журнале ухода.',
  );
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
              'Назад к журналу ухода',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final _StepInfo step;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 620;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: TextStyle(
                  color: _text,
                  fontSize: isNarrow ? 26 : 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                step.shortText,
                style: const TextStyle(color: _muted, fontSize: 16, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _StepBadge(text: 'Шаг ${step.number} из 5'),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.step,
    required this.showFull,
    required this.onToggle,
  });

  final _StepInfo step;
  final bool showFull;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final visibleDetails = showFull ? step.details : step.details.take(2);

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Подробная рекомендация от мастера',
            style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          for (final paragraph in visibleDetails) ...[
            Text(paragraph, style: const TextStyle(color: _text, height: 1.55)),
            const SizedBox(height: 16),
          ],
          TextButton.icon(
            onPressed: onToggle,
            icon: Icon(
              showFull ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: _accent,
            ),
            label: Text(showFull ? 'Свернуть' : 'Показать полностью'),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F6F1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, color: _accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Почему это важно?',
                        style: TextStyle(color: _text, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        step.reason,
                        style: const TextStyle(color: _muted, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.confirmed,
    required this.onConfirm,
    required this.onAsk,
  });

  final bool confirmed;
  final VoidCallback onConfirm;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            confirmed
                ? 'Шаг уже подтвержден'
                : 'Подтвердите выполнение шага',
            style: const TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            confirmed
                ? 'Ваше подтверждение зафиксировано и будет доступно мастеру.'
                : 'Пожалуйста, подтвердите, что вы выполнили рекомендацию выше.',
            style: const TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: confirmed ? null : onConfirm,
              icon: Icon(confirmed ? Icons.check_circle : Icons.check),
              label: Text(
                confirmed ? 'Выполнение подтверждено' : 'Подтвердить выполнение',
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(child: Divider(color: _line)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text('или', style: TextStyle(color: _muted)),
              ),
              Expanded(child: Divider(color: _line)),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAsk,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('У меня есть вопрос / уточнение'),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, color: _muted, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ваше подтверждение будет зафиксировано и доступно мастеру.',
                  style: TextStyle(color: _muted, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionForm extends StatelessWidget {
  const _QuestionForm({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Возникли сложности?',
            style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Опишите, что вызывает сомнение, и мастер вам поможет.',
            style: TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            minLines: 5,
            maxLines: 5,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'Опишите ваш вопрос или проблему...',
              counterText: '${controller.text.length} / 500',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _accent, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(onPressed: onSend, child: const Text('Отправить мастеру')),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F6F1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, color: _accent),
                    SizedBox(width: 10),
                    Text(
                      'Мастер получит ваш вопрос',
                      style: TextStyle(color: _text, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
  }
}
