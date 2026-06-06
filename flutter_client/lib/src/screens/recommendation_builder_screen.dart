import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/profile_image.dart';

final TextInputFormatter _dayNumberInputFormatter =
    TextInputFormatter.withFunction((oldValue, newValue) {
  if (newValue.text.isEmpty) {
    return newValue;
  }
  final day = int.tryParse(newValue.text);
  if (day == null || day <= 0 || day > 99) {
    return oldValue;
  }
  return newValue;
});

class RecommendationBuilderScreen extends StatefulWidget {
  const RecommendationBuilderScreen({
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
    this.onOpenAccountProfile,
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
  final void Function(String username, bool isMaster)? onOpenAccountProfile;

  @override
  State<RecommendationBuilderScreen> createState() =>
      _RecommendationBuilderScreenState();
}

class _RecommendationBuilderScreenState
    extends State<RecommendationBuilderScreen> {
  late List<_RecommendationStepDraft> _steps;
  AppointmentRecord? _appointment;
  String _planStatus = 'draft';
  bool _sent = false;
  bool _draftSaved = false;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  static const _background = AuthenticatedDashboardTheme.background;
  static const _card = AuthenticatedDashboardTheme.card;
  static const _accent = AuthenticatedDashboardTheme.accent;
  static const _text = AuthenticatedDashboardTheme.text;
  static const _muted = AuthenticatedDashboardTheme.muted;
  static const _line = AuthenticatedDashboardTheme.line;
  static const _soft = AuthenticatedDashboardTheme.soft;
  static const _image = AuthenticatedDashboardTheme.appointmentImage;

  @override
  void initState() {
    super.initState();
    _steps = _sortStepsByDay(_initialSteps);
    _loadRecommendations();
  }

  bool get _isMaster => widget.user?.role == 'master';

  @override
  void didUpdateWidget(covariant RecommendationBuilderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.appointmentId != widget.appointmentId) {
      _loadRecommendations();
    }
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
        isDesktop ? 40 : 12,
        isDesktop ? 30 : 14,
        isDesktop ? 40 : 12,
        isDesktop ? 42 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackLink(onTap: widget.onOpenMasterAppointments),
              const SizedBox(height: 20),
              _HeaderBlock(
                isDesktop: isDesktop,
                status: _planStatus,
                sent: _sent,
                draftSaved: _draftSaved,
                onSaveDraft: () => _saveDraft(),
                onSend: () => _sendToClient(),
              ),
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
                    SizedBox(
                      width: 320,
                      child: _AppointmentSummaryCard(
                        appointment: _appointment,
                        recommendationStatus: _planStatus,
                        onOpenAccountProfile: widget.onOpenAccountProfile,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: _stepsPanel(isDesktop: true)),
                  ],
                )
                else ...[
                  _AppointmentSummaryCard(
                    appointment: _appointment,
                    recommendationStatus: _planStatus,
                    onOpenAccountProfile: widget.onOpenAccountProfile,
                  ),
                  const SizedBox(height: 16),
                  _stepsPanel(isDesktop: false),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepsPanel({required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDesktop)
                Row(
                  children: [
                    const Expanded(child: _StepsPanelTitle()),
                    _AddStepButton(onPressed: _sent ? null : _addStep),
                  ],
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const _StepsPanelTitle(),
                    _AddStepButton(onPressed: _sent ? null : _addStep),
                  ],
                ),
              const SizedBox(height: 6),
              const Text(
                'Короткая рекомендация видна клиенту сразу. Подробная инструкция раскрывается внутри шага.',
                style: TextStyle(color: _muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Column(
                  key: ValueKey(_steps.length),
                  children: [
                    for (var index = 0; index < _steps.length; index++) ...[
                      _RecommendationStepCard(
                        key: ValueKey(_steps[index].id),
                        step: _steps[index],
                        deadlineLabel:
                            _deadlineLabelForStep(_steps[index]),
                        locked: _sent,
                        onToggle: () => _toggleStep(_steps[index].id),
                        onEditDeadline: () =>
                            _editStepDeadline(_steps[index].id),
                        onUpdateDay: (value) =>
                            _updateStepDay(_steps[index].id, value),
                        onUpdateSummary: (value) =>
                            _updateStep(_steps[index].id, summary: value),
                        onUpdateDetails: (value) =>
                            _updateStep(_steps[index].id, details: value),
                        onRemove: () => _removeStep(_steps[index].id),
                      ),
                      if (index != _steps.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _FooterActions(
          sent: _sent,
          onSaveDraft: () => _saveDraft(),
          onSend: () => _sendToClient(),
        ),
      ],
    );
  }

  void _toggleStep(String id) {
    setState(() {
      _steps = _steps
          .map((step) =>
              step.id == id ? step.copyWith(expanded: !step.expanded) : step)
          .toList();
    });
  }

  void _updateStep(String id, {String? summary, String? details}) {
    setState(() {
      _draftSaved = false;
      _steps = _steps
          .map(
            (step) => step.id == id
                ? step.copyWith(summary: summary, details: details)
                : step,
          )
          .toList();
    });
  }

  void _updateStepDay(String id, String value) {
    final day = int.tryParse(value);
    if (day == null || day <= 0 || day > 99) {
      return;
    }
    setState(() {
      _draftSaved = false;
      _steps = _sortStepsByDay(
        _steps.map(
          (step) =>
              step.id == id ? step.copyWith(dueOffsetDays: day, dueAt: '') : step,
        ),
      );
    });
  }

  Future<void> _editStepDeadline(String id) async {
    if (_sent) {
      return;
    }
    final step = _steps.firstWhere((step) => step.id == id);
    final initial = _deadlineDateForStep(step) ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
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
    if (pickedDate == null || !mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Выберите время',
      cancelText: 'Отмена',
      confirmText: 'ОК',
      hourLabelText: 'Часы',
      minuteLabelText: 'Минуты',
      builder: _forceRussianPicker,
    );
    if (pickedTime == null || !mounted) {
      return;
    }
    final deadline = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() {
      _draftSaved = false;
      _steps = _sortStepsByDay(
        _steps.map(
          (step) => step.id == id
              ? step.copyWith(dueAt: deadline.toUtc().toIso8601String())
              : step,
        ),
      );
    });
  }

  Future<void> _addStep() async {
    final day = await _askStepDay();
    if (day == null || !mounted) {
      return;
    }
    final nextNumber = _steps.length + 1;
    setState(() {
      _draftSaved = false;
      _steps = _sortStepsByDay([
        ..._steps,
        _RecommendationStepDraft(
          id: 'step-$nextNumber-${DateTime.now().millisecondsSinceEpoch}',
          dayLabel: 'День $day',
          summary: 'Опишите короткую рекомендацию для клиента.',
          details:
              'Добавьте подробную инструкцию: чем пользоваться, чего избегать и когда связаться с мастером.',
          dueOffsetDays: day,
          expanded: true,
        ),
      ]);
    });
  }

  void _removeStep(String id) {
    if (_steps.length == 1) {
      _showMockAction('Должен остаться хотя бы один шаг ухода');
      return;
    }

    setState(() {
      _draftSaved = false;
      _steps = _steps.where((step) => step.id != id).toList();
    });
  }

  int _suggestNextDay() {
    if (_steps.isEmpty) {
      return 1;
    }
    final next = _steps
            .map((step) => step.dayNumber)
            .fold<int>(0, (max, day) => day > max ? day : max) +
        1;
    return next > 99 ? 99 : next;
  }

  DateTime? _deadlineDateForStep(_RecommendationStepDraft step) {
    final explicit = DateTime.tryParse(step.dueAt)?.toLocal();
    if (explicit != null) {
      return explicit;
    }
    final start = DateTime.tryParse(_appointment?.scheduledAt ?? '')?.toLocal();
    if (start == null || step.dayNumber <= 0) {
      return null;
    }
    return start.add(Duration(days: step.dayNumber));
  }

  String? _deadlineLabelForStep(_RecommendationStepDraft step) {
    final deadline = _deadlineDateForStep(step);
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

  Future<int?> _askStepDay() async {
    final controller = TextEditingController(text: _suggestNextDay().toString());
    String? errorText;
    try {
      return await showDialog<int>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              int? parseDay() {
                final day = int.tryParse(controller.text.trim());
                if (day == null || day <= 0 || day > 99) {
                  setDialogState(() {
                    errorText = 'Введите число от 1 до 99';
                  });
                  return null;
                }
                return day;
              }

              void submit() {
                final day = parseDay();
                if (day != null) {
                  Navigator.of(context).pop(day);
                }
              }

              return AlertDialog(
                title: const Text('На какой день добавить шаг?'),
                content: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text(
                        'День',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 88,
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                          _dayNumberInputFormatter,
                        ],
                        onChanged: (_) {
                          if (errorText != null) {
                            setDialogState(() => errorText = null);
                          }
                        },
                        onSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          errorText: errorText,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  FilledButton(
                    onPressed: submit,
                    child: const Text('Добавить'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  List<_RecommendationStepDraft> _sortStepsByDay(
    Iterable<_RecommendationStepDraft> steps,
  ) {
    final indexed = steps.toList().asMap().entries.toList();
    indexed.sort((a, b) {
      final dayCompare = a.value.dayNumber.compareTo(b.value.dayNumber);
      if (dayCompare != 0) {
        return dayCompare;
      }
      return a.key.compareTo(b.key);
    });
    return indexed.map((entry) => entry.value).toList();
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
        _loading = false;
        _loadError =
            'Не удалось загрузить рекомендации: нет активной сессии или выбранной записи.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await api.masterAppointmentRecommendations(
        sessionToken: token,
        appointmentId: appointmentId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyResponse(response);
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _appointment = null;
        _loadError = 'Не удалось загрузить рекомендации: $error';
      });
    }
  }

  void _applyResponse(RecommendationsResponse response) {
    _appointment = response.appointment;
    _applyPlan(response.recommendations);
  }

  void _applyPlan(RecommendationsPlan plan) {
    if (plan.steps.isNotEmpty) {
      _steps = _sortStepsByDay(plan.steps.map(_draftFromStep));
    }
    _planStatus = plan.status.isEmpty ? 'draft' : plan.status;
    _sent = plan.isSent || plan.isApproved;
    _draftSaved = plan.steps.isNotEmpty;
  }

  _RecommendationStepDraft _draftFromStep(RecommendationStep step) {
    final day = step.dueOffsetDays ?? step.stepNumber;
    return _RecommendationStepDraft(
      id: step.id.isEmpty ? 'step-${step.stepNumber}' : step.id,
      dayLabel: 'День $day',
      summary: step.title,
      details: step.description,
      dueOffsetDays: day,
      dueAt: step.dueAt,
    );
  }

  RecommendationsSavePayload _payload() {
    final steps = <RecommendationStep>[];
    for (var index = 0; index < _steps.length; index++) {
      final draft = _steps[index];
      final title = draft.summary.trim().isEmpty
          ? draft.displayDayLabel
          : draft.summary.trim();
      final description = draft.details.trim().isEmpty
          ? title
          : draft.details.trim();
      steps.add(
        RecommendationStep(
          id: draft.id,
          stepNumber: index + 1,
          title: title,
          description: description,
          dueOffsetDays: draft.dayNumber,
          dueAt: draft.dueAt,
        ),
      );
    }
    return RecommendationsSavePayload(steps: steps);
  }

  Future<bool> _saveDraft({bool showMessage = true}) async {
    if (_loading || _saving) {
      return false;
    }

    final api = widget.api;
    final token = widget.sessionToken;
    final appointmentId = widget.appointmentId.trim();
    if (api == null ||
        token == null ||
        token.isEmpty ||
        appointmentId.isEmpty ||
        appointmentId == 'mock') {
      if (showMessage) {
        _showMockAction(
          'Не удалось сохранить черновик: нет активной сессии или выбранной записи.',
        );
      }
      return false;
    }

    setState(() => _saving = true);
    try {
      final response = await api.saveMasterAppointmentRecommendations(
        sessionToken: token,
        appointmentId: appointmentId,
        payload: _payload(),
      );
      if (!mounted) {
        return true;
      }
      setState(() {
        _applyResponse(response);
        _saving = false;
        _loadError = null;
      });
      if (showMessage) {
        _showMockAction('Черновик рекомендаций сохранен');
      }
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() => _saving = false);
      if (showMessage) {
        _showMockAction('Не удалось сохранить черновик. Повторите попытку позже.');
      }
      return false;
    }
  }
  Future<void> _sendToClient() async {
    if (_loading || _saving) {
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
        'Не удалось отправить рекомендации: нет активной сессии или выбранной записи.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await api.saveMasterAppointmentRecommendations(
        sessionToken: token,
        appointmentId: appointmentId,
        payload: _payload(),
      );
      final response = await api.sendMasterAppointmentRecommendations(
        sessionToken: token,
        appointmentId: appointmentId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyResponse(response);
        _steps = _steps.map((step) => step.copyWith(expanded: false)).toList();
        _saving = false;
        _loadError = null;
      });
      _showMockAction('Рекомендации отправлены клиенту на подтверждение');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      _showMockAction('Не удалось отправить рекомендации. Повторите попытку позже.');
    }
  }
  void _showMockAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), behavior: SnackBarBehavior.floating),
    );
  }
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

class _StepsPanelTitle extends StatelessWidget {
  const _StepsPanelTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Рекомендации по уходу',
      style: TextStyle(
        color: _RecommendationBuilderScreenState._text,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _AddStepButton extends StatelessWidget {
  const _AddStepButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Добавить шаг'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _RecommendationBuilderScreenState._accent,
        side: const BorderSide(color: _RecommendationBuilderScreenState._line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
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

class _RecommendationStepDraft {
  const _RecommendationStepDraft({
    required this.id,
    required this.dayLabel,
    required this.summary,
    required this.details,
    this.dueOffsetDays,
    this.dueAt = '',
    this.expanded = false,
  });

  final String id;
  final String dayLabel;
  final String summary;
  final String details;
  final int? dueOffsetDays;
  final String dueAt;
  final bool expanded;

  int get dayNumber {
    final parsedLabel = RegExp(r'\d+').firstMatch(dayLabel)?.group(0);
    return dueOffsetDays ?? int.tryParse(parsedLabel ?? '') ?? 1;
  }

  String get displayDayLabel => 'День $dayNumber';

  _RecommendationStepDraft copyWith({
    String? summary,
    String? details,
    int? dueOffsetDays,
    String? dueAt,
    bool? expanded,
  }) {
    return _RecommendationStepDraft(
      id: id,
      dayLabel: dayLabel,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      dueOffsetDays: dueOffsetDays ?? this.dueOffsetDays,
      dueAt: dueAt ?? this.dueAt,
      expanded: expanded ?? this.expanded,
    );
  }
}

const _initialSteps = [
  _RecommendationStepDraft(
    id: 'day-1',
    dayLabel: 'День 1',
    summary: 'Первые 24 часа не снимайте защитную пленку.',
    details:
        'Следите, чтобы пленка плотно прилегала к коже и не была повреждена. Не распаривайте татуировку и не трите область одеждой. Если под пленкой появится много жидкости, напишите мастеру перед самостоятельной заменой.',
    expanded: true,
  ),
  _RecommendationStepDraft(
    id: 'day-3',
    dayLabel: 'День 3',
    summary:
        'Аккуратно промойте тату теплой водой с мылом без отдушек. Промокните бумажным полотенцем.',
    details:
        'Промойте татуировку теплой водой с мягким мылом без отдушек, например детским или специальным мылом для тату. Делайте это мягкими круговыми движениями пальцев. После промывания промокните татуировку бумажным полотенцем, не трите. Дайте коже высохнуть на воздухе 5-10 минут перед нанесением уходового средства.',
  ),
  _RecommendationStepDraft(
    id: 'day-7',
    dayLabel: 'День 7',
    summary: 'Наносите тонкий слой заживляющего крема 2 раза в день.',
    details:
        'Используйте только рекомендованное средство. Наносите очень тонкий слой, чтобы кожа дышала. Избегайте спиртосодержащих кремов, агрессивных лосьонов и плотных повязок.',
  ),
  _RecommendationStepDraft(
    id: 'day-14',
    dayLabel: 'День 14',
    summary: 'Кожа может немного шелушиться, не срывайте корочки.',
    details:
        'Шелушение нормально для этого этапа. Не чесать, не срывать корочки и не использовать скрабы. Если появилось сильное покраснение, боль или выделения, свяжитесь с мастером.',
  ),
  _RecommendationStepDraft(
    id: 'day-30',
    dayLabel: 'День 30',
    summary:
        'Окончательная оценка заживления. При необходимости свяжитесь с мастером.',
    details:
        'Оцените яркость и ровность заживления при дневном свете. Продолжайте защищать татуировку от солнца. Если нужен осмотр или коррекция, напишите мастеру и приложите фото.',
  ),
];

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({
    required this.isDesktop,
    required this.status,
    required this.sent,
    required this.draftSaved,
    required this.onSaveDraft,
    required this.onSend,
  });

  final bool isDesktop;
  final String status;
  final bool sent;
  final bool draftSaved;
  final VoidCallback onSaveDraft;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final actions = [
      OutlinedButton.icon(
        onPressed: sent ? null : onSaveDraft,
        icon: const Icon(Icons.save_outlined, size: 18),
        label: const Text('Сохранить черновик'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _RecommendationBuilderScreenState._accent,
          side: const BorderSide(color: _RecommendationBuilderScreenState._line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(180, 44),
        ),
      ),
      FilledButton.icon(
        onPressed: sent ? null : onSend,
        icon: const Icon(Icons.send_outlined, size: 18),
        label: Text(
          status == 'approved'
              ? 'Подтверждено клиентом'
              : sent
                  ? 'Отправлено клиенту'
                  : 'Отправить клиенту',
        ),
        style: FilledButton.styleFrom(
          backgroundColor: _RecommendationBuilderScreenState._accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(190, 44),
        ),
      ),
    ];

    return isDesktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _title(
                  status: status,
                  sent: sent,
                  draftSaved: draftSaved,
                ),
              ),
              const SizedBox(width: 18),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(status: status, sent: sent, draftSaved: draftSaved),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  actions[0],
                  const SizedBox(height: 10),
                  actions[1],
                ],
              ),
            ],
          );
  }

  Widget _title({
    required String status,
    required bool sent,
    required bool draftSaved,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Сформировать рекомендации',
              style: TextStyle(
                color: _RecommendationBuilderScreenState._text,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            _StateBadge(
              label: status == 'approved'
                  ? 'Подтверждено клиентом'
                  : sent
                      ? 'Отправлено клиенту'
                      : draftSaved
                          ? 'Черновик сохранен'
                          : 'Черновик',
              color: sent
                  ? const Color(0xFFEAF2FF)
                  : const Color(0xFFFFF4D8),
              textColor: sent
                  ? const Color(0xFF2457A6)
                  : const Color(0xFF9A6700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Подготовьте короткие шаги ухода и подробные инструкции, которые клиент сможет развернуть перед подтверждением.',
          style: TextStyle(
            color: _RecommendationBuilderScreenState._muted,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _AppointmentSummaryCard extends StatelessWidget {
  const _AppointmentSummaryCard({
    required this.appointment,
    required this.recommendationStatus,
    required this.onOpenAccountProfile,
  });

  final AppointmentRecord? appointment;
  final String recommendationStatus;
  final void Function(String username, bool isMaster)? onOpenAccountProfile;

  @override
  Widget build(BuildContext context) {
    final item = appointment;
    final clientName = item == null
        ? 'Клиент не загружен'
        : _displayName(item.client.displayName, item.client.username);
    final city = item == null
        ? 'Город не загружен'
        : _nonEmpty(item.client.city, fallback: 'Город скрыт');
    final service = item == null
        ? 'Услуга не загружена'
        : _serviceLabel(item.service);
    final date = item == null ? 'Дата не загружена' : _dateLabel(item.scheduledAt);
    final duration = item == null ? 'Длительность не загружена' : _durationLabel(item);
    final status = item == null
        ? 'Запись не загружена'
        : _recommendationStatusLabel(recommendationStatus);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 190,
            child: ProfileImage(
              avatarUrl: item?.client.avatarUrl ?? '',
              fallbackAssetPath: _RecommendationBuilderScreenState._image,
              letterFallback: clientName,
              height: 190,
              borderRadius: 14,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: item == null
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: item == null
                        ? null
                        : () => onOpenAccountProfile?.call(
                              item.client.username,
                              item.client.isMaster,
                            ),
                    child: Text(
                      clientName,
                      style: const TextStyle(
                        color: _RecommendationBuilderScreenState._text,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              if (item?.client.isMaster ?? true)
                const Icon(
                  Icons.verified,
                  size: 18,
                  color: _RecommendationBuilderScreenState._accent,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoLine(icon: Icons.location_on_outlined, text: city),
          const SizedBox(height: 8),
          _InfoLine(icon: Icons.brush_outlined, text: service),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _RecommendationBuilderScreenState._soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _InfoLine(icon: Icons.calendar_today_outlined, text: date),
                const SizedBox(height: 10),
                _InfoLine(icon: Icons.schedule, text: duration),
                const SizedBox(height: 10),
                _InfoLine(icon: Icons.person_outline, text: status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _displayName(String displayName, String username) {
    final name = displayName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final handle = username.trim();
    if (handle.isEmpty) {
      return '@client';
    }
    return handle.startsWith('@') ? handle : '@$handle';
  }

  static String _nonEmpty(String value, {required String fallback}) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  static String _serviceLabel(MasterServiceSettings service) {
    final title = service.name.trim();
    final details = [
      service.category.trim(),
      service.style.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    if (title.isEmpty) {
      return details.isEmpty ? 'Услуга' : details;
    }
    return details.isEmpty ? title : '$title · $details';
  }

  static String _dateLabel(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) {
      return 'Дата уточняется';
    }
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  static String _durationLabel(AppointmentRecord item) {
    final start = DateTime.tryParse(item.scheduledAt)?.toLocal();
    final end = DateTime.tryParse(item.scheduledEndAt)?.toLocal();
    var minutes = item.durationMinutes;
    if (minutes <= 0 && start != null && end != null) {
      minutes = end.difference(start).inMinutes;
    }
    if (minutes <= 0 && item.service.durationHours != null) {
      minutes = (item.service.durationHours! * 60).round();
    }
    if (minutes <= 0) {
      return 'Длительность уточняется';
    }
    if (minutes < 60) {
      return 'Сеанс: $minutes мин';
    }
    final hours = minutes / 60;
    if (minutes % 60 == 0) {
      return 'Сеанс: ${hours.round()} ч';
    }
    return 'Сеанс: ${hours.toStringAsFixed(1)} ч';
  }

  static String _recommendationStatusLabel(String status) {
    return switch (status) {
      'approved' => 'Рекомендации подтверждены клиентом',
      'sent' => 'Рекомендации отправлены клиенту',
      _ => 'Черновик рекомендаций',
    };
  }
}

class _RecommendationStepCard extends StatelessWidget {
  const _RecommendationStepCard({
    super.key,
    required this.step,
    required this.deadlineLabel,
    required this.locked,
    required this.onToggle,
    required this.onEditDeadline,
    required this.onUpdateDay,
    required this.onUpdateSummary,
    required this.onUpdateDetails,
    required this.onRemove,
  });

  final _RecommendationStepDraft step;
  final String? deadlineLabel;
  final bool locked;
  final VoidCallback onToggle;
  final VoidCallback onEditDeadline;
  final ValueChanged<String> onUpdateDay;
  final ValueChanged<String> onUpdateSummary;
  final ValueChanged<String> onUpdateDetails;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    if (compact) {
      return _buildCompact(context);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _RecommendationBuilderScreenState._line),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepNumber(label: step.displayDayLabel),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DayLabelEditor(
                      key: ValueKey('${step.id}-day-editor'),
                      stepId: step.id,
                      dayNumber: step.dayNumber,
                      locked: locked,
                      onCommitted: onUpdateDay,
                    ),
                    const SizedBox(height: 4),
                    _StepDeadlineLine(
                      label: deadlineLabel ?? 'Назначить дедлайн',
                      enabled: !locked,
                      onTap: locked ? null : onEditDeadline,
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      key: ValueKey('${step.id}-summary-inline'),
                      enabled: !locked,
                      initialValue: step.summary,
                      minLines: 1,
                      maxLines: 3,
                      onChanged: onUpdateSummary,
                      style: const TextStyle(
                        color: _RecommendationBuilderScreenState._muted,
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: locked ? null : onRemove,
                tooltip: 'Удалить шаг',
                icon: const Icon(Icons.delete_outline, size: 20),
                color: const Color(0xFFD92D20),
              ),
              IconButton(
                onPressed: onToggle,
                tooltip: step.expanded ? 'Свернуть' : 'Развернуть',
                icon: Icon(
                  step.expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
                color: _RecommendationBuilderScreenState._muted,
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: step.expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAF8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _RecommendationBuilderScreenState._line,
                  ),
                ),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                        const Text(
                          'Подробная рекомендация от мастера',
                          style: TextStyle(
                            color: _RecommendationBuilderScreenState._text,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: ValueKey('${step.id}-details-inline'),
                          enabled: !locked,
                          initialValue: step.details,
                          minLines: 4,
                          maxLines: 10,
                          onChanged: onUpdateDetails,
                          style: const TextStyle(
                            color: _RecommendationBuilderScreenState._text,
                            height: 1.55,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _RecommendationBuilderScreenState._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepNumber(label: step.displayDayLabel, compact: true),
              const SizedBox(width: 12),
              Expanded(
                child: _DayLabelEditor(
                  key: ValueKey('${step.id}-day-editor-compact'),
                  stepId: step.id,
                  dayNumber: step.dayNumber,
                  locked: locked,
                  onCommitted: onUpdateDay,
                ),
              ),
              IconButton(
                onPressed: locked ? null : onRemove,
                visualDensity: VisualDensity.compact,
                tooltip: 'Удалить шаг',
                icon: const Icon(Icons.delete_outline, size: 20),
                color: const Color(0xFFD92D20),
              ),
              IconButton(
                onPressed: onToggle,
                visualDensity: VisualDensity.compact,
                tooltip: step.expanded ? 'Свернуть' : 'Развернуть',
                icon: Icon(
                  step.expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
                color: _RecommendationBuilderScreenState._muted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StepDeadlineLine(
            label: deadlineLabel ?? 'Назначить дедлайн',
            enabled: !locked,
            onTap: locked ? null : onEditDeadline,
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('${step.id}-summary-compact'),
            enabled: !locked,
            initialValue: step.summary,
            minLines: 2,
            maxLines: 4,
            onChanged: onUpdateSummary,
            style: const TextStyle(
              color: _RecommendationBuilderScreenState._muted,
              height: 1.4,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: step.expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAF8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _RecommendationBuilderScreenState._line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Подробная рекомендация от мастера',
                      style: TextStyle(
                        color: _RecommendationBuilderScreenState._text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey('${step.id}-details-compact'),
                      enabled: !locked,
                      initialValue: step.details,
                      minLines: 4,
                      maxLines: 10,
                      onChanged: onUpdateDetails,
                      style: const TextStyle(
                        color: _RecommendationBuilderScreenState._text,
                        height: 1.55,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepDeadlineLine extends StatelessWidget {
  const _StepDeadlineLine({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Icon(
          Icons.event_available_outlined,
          size: 16,
          color: enabled
              ? _RecommendationBuilderScreenState._accent
              : _RecommendationBuilderScreenState._muted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: enabled
                  ? _RecommendationBuilderScreenState._text
                  : _RecommendationBuilderScreenState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (enabled) ...[
          const SizedBox(width: 4),
          const Icon(
            Icons.edit_calendar_outlined,
            size: 16,
            color: _RecommendationBuilderScreenState._accent,
          ),
        ],
      ],
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: content,
      ),
    );
  }
}

class _FooterActions extends StatelessWidget {
  const _FooterActions({
    required this.sent,
    required this.onSaveDraft,
    required this.onSend,
  });

  final bool sent;
  final VoidCallback onSaveDraft;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;
          final note = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(
                Icons.lock_outline,
                size: 18,
                color: _RecommendationBuilderScreenState._muted,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'После отправки клиент увидит рекомендации на экране подтверждения.',
                  style: TextStyle(
                    color: _RecommendationBuilderScreenState._muted,
                  ),
                ),
              ),
            ],
          );
          final actions = [
            OutlinedButton(
              onPressed: sent ? null : onSaveDraft,
              child: const Text('Черновик'),
            ),
            FilledButton(
              onPressed: sent ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: _RecommendationBuilderScreenState._accent,
                foregroundColor: Colors.white,
              ),
              child: Text(sent ? 'Отправлено' : 'Отправить'),
            ),
          ];

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                note,
                const SizedBox(height: 14),
                actions[0],
                const SizedBox(height: 8),
                actions[1],
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: note),
              const SizedBox(width: 12),
              actions[0],
              const SizedBox(width: 8),
              actions[1],
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: _RecommendationBuilderScreenState._card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _RecommendationBuilderScreenState._line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: child,
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
      label: const Text('Назад к записям'),
      style: TextButton.styleFrom(
        foregroundColor: _RecommendationBuilderScreenState._muted,
      ),
    );
  }
}

class _DayLabelEditor extends StatefulWidget {
  const _DayLabelEditor({
    super.key,
    required this.stepId,
    required this.dayNumber,
    required this.locked,
    required this.onCommitted,
  });

  final String stepId;
  final int dayNumber;
  final bool locked;
  final ValueChanged<String> onCommitted;

  @override
  State<_DayLabelEditor> createState() => _DayLabelEditorState();
}

class _DayLabelEditorState extends State<_DayLabelEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.dayNumber.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_restoreDayOnBlur);
  }

  @override
  void didUpdateWidget(covariant _DayLabelEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayNumber != widget.dayNumber && !_focusNode.hasFocus) {
      _controller.text = widget.dayNumber.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_restoreDayOnBlur);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _restoreDayOnBlur() {
    if (!_focusNode.hasFocus) {
      _commitDay();
    }
  }

  void _commitDay() {
    final value = _controller.text.trim();
    final day = int.tryParse(value);
    if (day == null || day <= 0 || day > 99) {
      _controller.text = widget.dayNumber.toString();
      return;
    }
    final normalized = day.toString();
    if (_controller.text != normalized) {
      _controller.text = normalized;
    }
    if (day != widget.dayNumber) {
      widget.onCommitted(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      color: _RecommendationBuilderScreenState._text,
      fontSize: 16,
      height: 1.2,
      fontWeight: FontWeight.w900,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('День', style: labelStyle),
        const SizedBox(width: 5),
        SizedBox(
          width: 28,
          height: 20,
          child: IgnorePointer(
            ignoring: widget.locked,
            child: EditableText(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
                _dayNumberInputFormatter,
              ],
              onSubmitted: (_) => _commitDay(),
              style: labelStyle,
              cursorColor: _RecommendationBuilderScreenState._accent,
              backgroundCursorColor: Colors.transparent,
              selectionColor:
                  _RecommendationBuilderScreenState._accent.withOpacity(0.18),
              selectionControls: materialTextSelectionControls,
              readOnly: widget.locked,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final digits = RegExp(r'\d+').firstMatch(label)?.group(0) ?? label;

    return Container(
      width: compact ? 36 : 42,
      height: compact ? 36 : 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _RecommendationBuilderScreenState._accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        digits,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
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
        Icon(icon, size: 16, color: _RecommendationBuilderScreenState._muted),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: _RecommendationBuilderScreenState._muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MasterOnlyScreen extends StatelessWidget {
  const _MasterOnlyScreen({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _RecommendationBuilderScreenState._background,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _RecommendationBuilderScreenState._line),
            boxShadow: AuthenticatedDashboardTheme.cardShadow(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                color: _RecommendationBuilderScreenState._accent,
                size: 42,
              ),
              const SizedBox(height: 14),
              const Text(
                'Доступно только мастерам',
                style: TextStyle(
                  color: _RecommendationBuilderScreenState._text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Формирование рекомендаций доступно только пользователям с ролью master.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _RecommendationBuilderScreenState._muted),
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
