import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/authenticated_site_header.dart';
import '../widgets/profile_image.dart';

class BookingServiceScreen extends StatefulWidget {
  const BookingServiceScreen({
    super.key,
    required this.user,
    required this.userName,
    this.api,
    this.sessionToken,
    this.masterUsername,
    this.initialServiceId,
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
    required this.onBackToProfile,
  });

  final AuthUser? user;
  final String userName;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final String? masterUsername;
  final String? initialServiceId;
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
  final VoidCallback onBackToProfile;

  @override
  State<BookingServiceScreen> createState() => _BookingServiceScreenState();
}

class _BookingServiceOption {
  const _BookingServiceOption({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.duration,
    required this.durationMinutes,
    required this.price,
    required this.note,
  });

  final String id;
  final String type;
  final String title;
  final String description;
  final String duration;
  final int durationMinutes;
  final String price;
  final String note;
}

class _BookingServiceScreenState extends State<BookingServiceScreen> {
  final TextEditingController _commentController = TextEditingController();
  DateTime _visibleMonth = _initialVisibleMonth();
  DateTime _selectedDate = _initialSelectedDate();
  String _selectedTime = '';
  _BookingServiceOption? _selectedService;
  _BookingServiceOption? _pendingService;
  late List<_BookingServiceOption> _services;
  List<AvailabilitySlot>? _availabilitySlots;
  MasterProfile? _masterProfile;
  bool _isLoadingServices = false;
  bool _isLoadingAvailability = false;
  bool _isSubmitting = false;
  String? _loadError;

  static const _background = AuthenticatedDashboardTheme.background;
  static const _card = AuthenticatedDashboardTheme.card;
  static const _accent = AuthenticatedDashboardTheme.accent;
  static const _text = AuthenticatedDashboardTheme.text;
  static const _muted = AuthenticatedDashboardTheme.muted;
  static const _line = AuthenticatedDashboardTheme.line;
  static const _image = 'assets/guest_master_profile/maria_profile.png';

  static DateTime _initialSelectedDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _initialVisibleMonth() {
    final date = _initialSelectedDate();
    return DateTime(date.year, date.month);
  }


  bool get _hasPreselectedService =>
      widget.initialServiceId != null && _selectedService != null;

  bool get _usesBackendSchedule =>
      _masterProfile != null;

  @override
  void initState() {
    super.initState();
    final shouldLoadBackend =
        widget.api != null && (widget.masterUsername ?? '').trim().isNotEmpty;
    _services = <_BookingServiceOption>[];
    _isLoadingServices = shouldLoadBackend;
    _loadError = shouldLoadBackend
        ? null
        : 'Не удалось открыть запись: не передан реальный username мастера.';
    _selectedService = _serviceById(widget.initialServiceId);
    _loadBookingData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedPageShell(
      user: widget.user,
      userName: widget.userName,
      activeSidebarItem: null,
      activeMobileNavItem: AuthenticatedMobileNavItem.search,
      headerSection: AuthenticatedHeaderSection.search,
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
    final horizontalPadding = isDesktop ? 32.0 : 16.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isDesktop ? 32 : 18,
        horizontalPadding,
        isDesktop ? 48 : 96,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: _loadError != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BackToProfile(onTap: widget.onBackToProfile),
                    const SizedBox(height: 18),
                    _BackendErrorState(
                      message: _loadError!,
                      onRetry: _loadBookingData,
                    ),
                  ],
                )
              : isDesktop
              ? _DesktopBookingLayout(
                  masterProfile: _masterProfile,
                  visibleMonth: _visibleMonth,
                  selectedDate: _selectedDate,
                  selectedTime: _selectedTime,
                  commentController: _commentController,
                  onSelectDate: _selectDate,
                  onChangeMonth: _changeMonth,
                  onSelectTime: _selectTime,
                  services: _services,
                  availabilitySlots: _availabilitySlots,
                  isLoadingAvailability: _isLoadingAvailability,
                  masterSchedule: _masterProfile?.schedule ?? const [],
                  useBackendSchedule: _usesBackendSchedule,
                  isLoadingServices: _isLoadingServices,
                  isSubmitting: _isSubmitting,
                  selectedService: _selectedService,
                  pendingService: _pendingService,
                  hasPreselectedService: _hasPreselectedService,
                  onSelectService: _selectService,
                  onConfirmServiceSelection: _confirmServiceSelection,
                  onChangeService: _clearSelectedService,
                  onSubmit: () {
                    _submitBooking();
                  },
                  onBackToProfile: widget.onBackToProfile,
                )
              : _MobileBookingLayout(
                  masterProfile: _masterProfile,
                  visibleMonth: _visibleMonth,
                  selectedDate: _selectedDate,
                  selectedTime: _selectedTime,
                  commentController: _commentController,
                  onSelectDate: _selectDate,
                  onChangeMonth: _changeMonth,
                  onSelectTime: _selectTime,
                  services: _services,
                  availabilitySlots: _availabilitySlots,
                  isLoadingAvailability: _isLoadingAvailability,
                  masterSchedule: _masterProfile?.schedule ?? const [],
                  useBackendSchedule: _usesBackendSchedule,
                  isLoadingServices: _isLoadingServices,
                  isSubmitting: _isSubmitting,
                  selectedService: _selectedService,
                  pendingService: _pendingService,
                  hasPreselectedService: _hasPreselectedService,
                  onSelectService: _selectService,
                  onConfirmServiceSelection: _confirmServiceSelection,
                  onChangeService: _clearSelectedService,
                  onSubmit: () {
                    _submitBooking();
                  },
                  onBackToProfile: widget.onBackToProfile,
                ),
        ),
      ),
    );
  }
  void _selectDate(DateTime date) {
    if (!_isSelectableDate(date)) {
      return;
    }
    setState(() => _selectedDate = date);
    _loadAvailability();
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
    setState(() {
      _visibleMonth = nextMonth;
      if (_selectedDate.year != nextMonth.year ||
          _selectedDate.month != nextMonth.month) {
        _selectedDate = _selectableDateForMonth(
          nextMonth,
          preferredDay: _selectedDate.day.clamp(1, lastDay).toInt(),
        );
      }
      _availabilitySlots = null;
      _selectedTime = '';
    });
    _loadAvailability();
  }

  void _selectTime(String time) {
    setState(() => _selectedTime = time);
  }

  void _selectService(_BookingServiceOption service) {
    setState(() => _pendingService = service);
  }

  void _confirmServiceSelection() {
    final service = _pendingService;
    if (service == null) {
      return;
    }

    setState(() {
      _selectedService = service;
      if (!_isSelectableDate(_selectedDate)) {
        _selectedDate = _selectableDateForMonth(_visibleMonth);
      }
      _availabilitySlots = const [];
      _isLoadingAvailability = true;
      _selectedTime = '';
    });
    _loadAvailability();
  }

  void _clearSelectedService() {
    final current = _selectedService;
    setState(() {
      _selectedService = null;
      _pendingService = current;
      _availabilitySlots = null;
      _isLoadingAvailability = false;
      _selectedTime = '';
    });
  }

  static int _durationMinutes(_BookingServiceOption service) {
    return service.durationMinutes;
  }

  _BookingServiceOption? _serviceById(String? id) {
    if (id == null) {
      return null;
    }
    for (final service in _services) {
      if (service.id == id) {
        return service;
      }
    }
    return null;
  }

  Future<void> _loadBookingData() async {
    final api = widget.api;
    final username = widget.masterUsername?.trim();
    if (api == null || username == null || username.isEmpty) {
      setState(() {
        _services = const <_BookingServiceOption>[];
        _masterProfile = null;
        _isLoadingServices = false;
        _loadError =
            'Не удалось открыть запись: не передан реальный username мастера.';
      });
      return;
    }

    setState(() {
      _isLoadingServices = true;
      _loadError = null;
    });
    try {
      final profile = await api.publicMasterProfile(username);
      if (!mounted) {
        return;
      }
      final services = profile.services.map(_serviceFromBackend).toList();
      final preselectedService = widget.initialServiceId == null
          ? null
          : _serviceByIdFromList(services, widget.initialServiceId);
      setState(() {
        _masterProfile = profile;
        _services = services;
        _isLoadingServices = false;
        _loadError = null;
        _selectedService = preselectedService;
        _pendingService = preselectedService;
        _selectedDate = _selectableDateForMonth(
          _visibleMonth,
          preferredDay: _selectedDate.day,
        );
        _availabilitySlots = preselectedService == null ? null : const [];
        _isLoadingAvailability = preselectedService != null;
        _selectedTime = '';
      });
      if (preselectedService != null) {
        await _loadAvailability();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _services = const <_BookingServiceOption>[];
        _masterProfile = null;
        _isLoadingServices = false;
        _isLoadingAvailability = false;
        _selectedService = null;
        _pendingService = null;
        _selectedTime = '';
        _loadError = 'Не удалось загрузить профиль мастера для записи: $error';
      });
    }
  }

  _BookingServiceOption? _serviceByIdFromList(
    List<_BookingServiceOption> services,
    String? id,
  ) {
    if (id == null) {
      return null;
    }
    for (final service in services) {
      if (service.id == id) {
        return service;
      }
    }
    return null;
  }

  Future<void> _loadAvailability() async {
    final api = widget.api;
    final username = widget.masterUsername?.trim();
    final service = _selectedService;
    if (api == null ||
        username == null ||
        username.isEmpty ||
        service == null) {
      return;
    }

    if (!_isSelectableDate(_selectedDate)) {
      setState(() {
        _availabilitySlots = const [];
        _isLoadingAvailability = false;
        _selectedTime = '';
      });
      return;
    }

    setState(() {
      _isLoadingAvailability = true;
      _availabilitySlots = const [];
      _selectedTime = '';
    });

    try {
      final slots = await api.masterAvailability(
        username: username,
        date: _dateParam(_selectedDate),
        serviceId: service.id,
      );
      final available = slots
          .where((slot) => slot.available && slot.time.isNotEmpty)
          .map((slot) => slot.time)
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _availabilitySlots = slots;
        _isLoadingAvailability = false;
        if (available.isEmpty) {
          _selectedTime = '';
        } else if (!available.contains(_selectedTime)) {
          _selectedTime = available.first;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availabilitySlots = const [];
        _selectedTime = '';
        _isLoadingAvailability = false;
        _loadError = 'Не удалось загрузить доступное время: $error';
      });
    }
  }

  bool _isSelectableDate(DateTime date) {
    final normalized = DateUtils.dateOnly(date);
    final today = DateUtils.dateOnly(DateTime.now());
    if (normalized.isBefore(today)) {
      return false;
    }
    if (_usesBackendSchedule && !_hasWorkOnDate(date)) {
      return false;
    }
    return true;
  }

  DateTime _selectableDateForMonth(
    DateTime month, {
    int? preferredDay,
  }) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final preferred = DateTime(
      month.year,
      month.month,
      (preferredDay ?? 1).clamp(1, lastDay).toInt(),
    );
    if (_isSelectableDate(preferred)) {
      return preferred;
    }
    for (var day = 1; day <= lastDay; day++) {
      final candidate = DateTime(month.year, month.month, day);
      if (_isSelectableDate(candidate)) {
        return candidate;
      }
    }
    return preferred;
  }

  bool _hasWorkOnDate(DateTime date) {
    return _scheduleHasWorkOnDate(_masterProfile?.schedule ?? const [], date);
  }

  _BookingServiceOption _serviceFromBackend(MasterServiceSettings service) {
    return _BookingServiceOption(
      id: service.id,
      type: _serviceTypeLabel(service.type),
      title: service.name,
      description: service.description,
      duration: _durationLabelFromHours(service.durationHours),
      durationMinutes: _durationMinutesFromHours(service.durationHours),
      price: service.fromPrice
          ? 'от ${_formatRubles(service.price)} ₽'
          : '${_formatRubles(service.price)} ₽',
      note: service.description,
    );
  }

  Future<void> _submitBooking() async {
    final api = widget.api;
    final token = widget.sessionToken;
    final username = widget.masterUsername?.trim();
    final service = _selectedService;
    if (api == null ||
        token == null ||
        token.isEmpty ||
        username == null ||
        username.isEmpty ||
        service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось создать запись: нет активной backend-сессии или услуги.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await api.createAppointment(
        sessionToken: token,
        payload: AppointmentCreatePayload(
          masterUsername: username,
          serviceId: service.id,
          scheduledAt: _scheduledAtIso(_selectedDate, _selectedTime),
          clientNote: _commentController.text.trim(),
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Запись создана: ${_dateLabel(_selectedDate)} в $_selectedTime, ожидает подтверждения мастера',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onOpenAppointments();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось создать запись: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  static String _scheduledAtIso(DateTime date, String time) {
    final parts = time.split(':');
    final local = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    return local.toUtc().toIso8601String();
  }

  static String _dateParam(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String _serviceTypeLabel(String type) {
    return switch (type) {
      'consultation' => 'Консультация',
      'sketch' => 'Эскиз',
      _ => 'Сеанс',
    };
  }

  static String _durationLabelFromHours(double? hours) {
    if (hours == null || hours <= 0) {
      return '—';
    }
    if (hours < 1) {
      return '~ ${(hours * 60).round()} мин';
    }
    if (hours == hours.roundToDouble()) {
      return '~ ${hours.round()} ч';
    }
    return '~ ${hours.toStringAsFixed(1)} ч';
  }

  static int _durationMinutesFromHours(double? hours) {
    if (hours == null || hours <= 0) {
      return 60;
    }
    final minutes = (hours * 60).round();
    return minutes < 30 ? 30 : minutes;
  }

  static String _formatRubles(int value) {
    final source = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      final remaining = source.length - i;
      buffer.write(source[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  void _showMockAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: экран будет подключён следующим шагом'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    return '${date.day} ${_monthName(date.month).toLowerCase()}';
  }

  static String _monthName(int month) {
    const names = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    return names[month - 1];
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

class _DesktopBookingLayout extends StatelessWidget {
  const _DesktopBookingLayout({
    required this.masterProfile,
    required this.visibleMonth,
    required this.selectedDate,
    required this.selectedTime,
    required this.commentController,
    required this.onSelectDate,
    required this.onChangeMonth,
    required this.onSelectTime,
    required this.services,
    required this.availabilitySlots,
    required this.isLoadingAvailability,
    required this.masterSchedule,
    required this.useBackendSchedule,
    required this.isLoadingServices,
    required this.isSubmitting,
    required this.selectedService,
    required this.pendingService,
    required this.hasPreselectedService,
    required this.onSelectService,
    required this.onConfirmServiceSelection,
    required this.onChangeService,
    required this.onSubmit,
    required this.onBackToProfile,
  });

  final MasterProfile? masterProfile;
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final String selectedTime;
  final TextEditingController commentController;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<int> onChangeMonth;
  final ValueChanged<String> onSelectTime;
  final List<_BookingServiceOption> services;
  final List<AvailabilitySlot>? availabilitySlots;
  final bool isLoadingAvailability;
  final List<MasterScheduleDay> masterSchedule;
  final bool useBackendSchedule;
  final bool isLoadingServices;
  final bool isSubmitting;
  final _BookingServiceOption? selectedService;
  final _BookingServiceOption? pendingService;
  final bool hasPreselectedService;
  final ValueChanged<_BookingServiceOption> onSelectService;
  final VoidCallback onConfirmServiceSelection;
  final VoidCallback onChangeService;
  final VoidCallback onSubmit;
  final VoidCallback onBackToProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackToProfile(onTap: onBackToProfile),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 300,
              child: _MasterSummaryCard(profile: masterProfile),
            ),
            const SizedBox(width: 36),
            Expanded(
              child: _BookingForm(
                visibleMonth: visibleMonth,
                selectedDate: selectedDate,
                selectedTime: selectedTime,
                commentController: commentController,
                onSelectDate: onSelectDate,
                onChangeMonth: onChangeMonth,
                onSelectTime: onSelectTime,
                services: services,
                availabilitySlots: availabilitySlots,
                isLoadingAvailability: isLoadingAvailability,
                masterSchedule: masterSchedule,
                useBackendSchedule: useBackendSchedule,
                isLoadingServices: isLoadingServices,
                isSubmitting: isSubmitting,
                selectedService: selectedService,
                pendingService: pendingService,
                hasPreselectedService: hasPreselectedService,
                onSelectService: onSelectService,
                onConfirmServiceSelection: onConfirmServiceSelection,
                onChangeService: onChangeService,
                onSubmit: onSubmit,
                compact: false,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MobileBookingLayout extends StatelessWidget {
  const _MobileBookingLayout({
    required this.masterProfile,
    required this.visibleMonth,
    required this.selectedDate,
    required this.selectedTime,
    required this.commentController,
    required this.onSelectDate,
    required this.onChangeMonth,
    required this.onSelectTime,
    required this.services,
    required this.availabilitySlots,
    required this.isLoadingAvailability,
    required this.masterSchedule,
    required this.useBackendSchedule,
    required this.isLoadingServices,
    required this.isSubmitting,
    required this.selectedService,
    required this.pendingService,
    required this.hasPreselectedService,
    required this.onSelectService,
    required this.onConfirmServiceSelection,
    required this.onChangeService,
    required this.onSubmit,
    required this.onBackToProfile,
  });

  final MasterProfile? masterProfile;
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final String selectedTime;
  final TextEditingController commentController;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<int> onChangeMonth;
  final ValueChanged<String> onSelectTime;
  final List<_BookingServiceOption> services;
  final List<AvailabilitySlot>? availabilitySlots;
  final bool isLoadingAvailability;
  final List<MasterScheduleDay> masterSchedule;
  final bool useBackendSchedule;
  final bool isLoadingServices;
  final bool isSubmitting;
  final _BookingServiceOption? selectedService;
  final _BookingServiceOption? pendingService;
  final bool hasPreselectedService;
  final ValueChanged<_BookingServiceOption> onSelectService;
  final VoidCallback onConfirmServiceSelection;
  final VoidCallback onChangeService;
  final VoidCallback onSubmit;
  final VoidCallback onBackToProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackToProfile(onTap: onBackToProfile),
        const SizedBox(height: 18),
        const _MobileTitle(),
        const SizedBox(height: 18),
        _MobileMasterStrip(profile: masterProfile),
        const SizedBox(height: 12),
        _BookingForm(
          visibleMonth: visibleMonth,
          selectedDate: selectedDate,
          selectedTime: selectedTime,
          commentController: commentController,
          onSelectDate: onSelectDate,
          onChangeMonth: onChangeMonth,
          onSelectTime: onSelectTime,
          services: services,
          availabilitySlots: availabilitySlots,
          isLoadingAvailability: isLoadingAvailability,
          masterSchedule: masterSchedule,
          useBackendSchedule: useBackendSchedule,
          isLoadingServices: isLoadingServices,
          isSubmitting: isSubmitting,
          selectedService: selectedService,
          pendingService: pendingService,
          hasPreselectedService: hasPreselectedService,
          onSelectService: onSelectService,
          onConfirmServiceSelection: onConfirmServiceSelection,
          onChangeService: onChangeService,
          onSubmit: onSubmit,
          compact: true,
        ),
      ],
    );
  }
}

class _BookingForm extends StatelessWidget {
  const _BookingForm({
    required this.visibleMonth,
    required this.selectedDate,
    required this.selectedTime,
    required this.commentController,
    required this.onSelectDate,
    required this.onChangeMonth,
    required this.onSelectTime,
    required this.services,
    required this.availabilitySlots,
    required this.isLoadingAvailability,
    required this.masterSchedule,
    required this.useBackendSchedule,
    required this.isLoadingServices,
    required this.isSubmitting,
    required this.selectedService,
    required this.pendingService,
    required this.hasPreselectedService,
    required this.onSelectService,
    required this.onConfirmServiceSelection,
    required this.onChangeService,
    required this.onSubmit,
    required this.compact,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final String selectedTime;
  final TextEditingController commentController;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<int> onChangeMonth;
  final ValueChanged<String> onSelectTime;
  final List<_BookingServiceOption> services;
  final List<AvailabilitySlot>? availabilitySlots;
  final bool isLoadingAvailability;
  final List<MasterScheduleDay> masterSchedule;
  final bool useBackendSchedule;
  final bool isLoadingServices;
  final bool isSubmitting;
  final _BookingServiceOption? selectedService;
  final _BookingServiceOption? pendingService;
  final bool hasPreselectedService;
  final ValueChanged<_BookingServiceOption> onSelectService;
  final VoidCallback onConfirmServiceSelection;
  final VoidCallback onChangeService;
  final VoidCallback onSubmit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          const Text(
            'Запись на услугу',
            style: TextStyle(
              color: _BookingServiceScreenState._text,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 22),
        ],
        _StepProgress(
          compact: compact,
          hasPreselectedService: hasPreselectedService,
          serviceSelected: selectedService != null,
        ),
        const SizedBox(height: 20),
        if (selectedService == null) ...[
          _ServiceSelector(
            services: services,
            selectedService: pendingService,
            isLoading: isLoadingServices,
            onSelectService: onSelectService,
            compact: compact,
          ),
          const SizedBox(height: 18),
          const _BookingInfoNote(),
          const SizedBox(height: 18),
        ] else ...[
          _SelectedServiceBlock(
            service: selectedService!,
            onChange: onChangeService,
          ),
          const SizedBox(height: 20),
          compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CalendarSection(
                      visibleMonth: visibleMonth,
                      selectedDate: selectedDate,
                      onSelectDate: onSelectDate,
                      onChangeMonth: onChangeMonth,
                      masterSchedule: masterSchedule,
                      useBackendSchedule: useBackendSchedule,
                      compact: true,
                    ),
                    const SizedBox(height: 12),
                    _TimeSection(
                      selectedDate: selectedDate,
                      selectedTime: selectedTime,
                      selectedService: selectedService,
                      availabilitySlots: availabilitySlots,
                      isLoading: isLoadingAvailability,
                      useBackendAvailability: useBackendSchedule,
                      onSelectTime: onSelectTime,
                      compact: true,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CalendarSection(
                        visibleMonth: visibleMonth,
                        selectedDate: selectedDate,
                        onSelectDate: onSelectDate,
                        onChangeMonth: onChangeMonth,
                        masterSchedule: masterSchedule,
                        useBackendSchedule: useBackendSchedule,
                        compact: false,
                      ),
                    ),
                    const SizedBox(width: 34),
                    SizedBox(
                      width: 330,
                      child: _TimeSection(
                        selectedDate: selectedDate,
                        selectedTime: selectedTime,
                        selectedService: selectedService,
                        availabilitySlots: availabilitySlots,
                        isLoading: isLoadingAvailability,
                        useBackendAvailability: useBackendSchedule,
                        onSelectTime: onSelectTime,
                        compact: false,
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 18),
          _CommentField(controller: commentController, compact: compact),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: selectedService == null
                ? pendingService == null
                    ? null
                    : onConfirmServiceSelection
                : selectedTime.isEmpty || isSubmitting
                    ? null
                    : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: _BookingServiceScreenState._accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              selectedService == null
                  ? 'Продолжить'
                  : isSubmitting
                      ? 'Создаём запись...'
                      : 'Записаться',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Icon(
                Icons.lock_outline,
                size: 14,
                color: _BookingServiceScreenState._muted,
              ),
              Text(
                'Нажимая «Записаться», вы соглашаетесь с политикой конфиденциальности',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _BookingServiceScreenState._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (compact) {
      return content;
    }

    return _Surface(padding: const EdgeInsets.all(28), child: content);
  }
}

class _SelectedServiceBlock extends StatelessWidget {
  const _SelectedServiceBlock({
    required this.service,
    required this.onChange,
  });

  final _BookingServiceOption service;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service.title,
              style: const TextStyle(
                color: _BookingServiceScreenState._text,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              service.description,
              style: const TextStyle(
                color: _BookingServiceScreenState._muted,
                fontSize: 13,
              ),
            ),
            if (service.note.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                service.note,
                style: const TextStyle(
                  color: _BookingServiceScreenState._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        );
        final meta = Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _CompactServiceMeta(
              icon: Icons.schedule_outlined,
              text: service.duration,
            ),
            _CompactServiceMeta(
              icon: Icons.payments_outlined,
              text: service.price,
            ),
            TextButton(
              onPressed: onChange,
              style: TextButton.styleFrom(
                foregroundColor: _BookingServiceScreenState._accent,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Изменить'),
            ),
          ],
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F5F1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _BookingServiceScreenState._line),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: 12),
                    meta,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 12),
                    meta,
                  ],
                ),
        );
      },
    );
  }
}

class _ServiceSelector extends StatelessWidget {
  const _ServiceSelector({
    required this.services,
    required this.selectedService,
    required this.isLoading,
    required this.onSelectService,
    required this.compact,
  });

  final List<_BookingServiceOption> services;
  final _BookingServiceOption? selectedService;
  final bool isLoading;
  final ValueChanged<_BookingServiceOption> onSelectService;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Выберите услугу',
          style: TextStyle(
            color: _BookingServiceScreenState._text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        if (isLoading) ...[
          const _BookingServiceNotice(
            icon: Icons.sync_rounded,
            text: 'Загружаем услуги выбранного мастера...',
          ),
        ] else if (services.isEmpty) ...[
          const _BookingServiceNotice(
            icon: Icons.info_outline_rounded,
            text: 'Мастер пока не добавил услуги. Выберите другого мастера или попробуйте позже.',
          ),
        ] else ...[
        ...services.map(
          (service) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ServiceSelectCard(
              service: service,
              selected: selectedService?.id == service.id,
              compact: compact,
              onTap: () => onSelectService(service),
            ),
          ),
        ),
        ],
      ],
    );
  }
}

class _BookingServiceNotice extends StatelessWidget {
  const _BookingServiceNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _BookingServiceScreenState._line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _BookingServiceScreenState._accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _BookingServiceScreenState._muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceSelectCard extends StatelessWidget {
  const _ServiceSelectCard({
    required this.service,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _BookingServiceOption service;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.all(compact ? 14 : 16),
        decoration: BoxDecoration(
          color: selected
              ? _BookingServiceScreenState._accent.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _BookingServiceScreenState._accent
                : _BookingServiceScreenState._line,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? _BookingServiceScreenState._accent
                  : _BookingServiceScreenState._muted,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.title,
                    style: const TextStyle(
                      color: _BookingServiceScreenState._text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service.description,
                    style: const TextStyle(
                      color: _BookingServiceScreenState._muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service.note,
                    style: const TextStyle(
                      color: _BookingServiceScreenState._muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!compact) ...[
              _CompactServiceMeta(icon: Icons.schedule_outlined, text: service.duration),
              const SizedBox(width: 16),
            ],
            Text(
              service.price,
              style: const TextStyle(
                color: _BookingServiceScreenState._text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactServiceMeta extends StatelessWidget {
  const _CompactServiceMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _BookingServiceScreenState._muted),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: _BookingServiceScreenState._text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _BookingInfoNote extends StatelessWidget {
  const _BookingInfoNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _BookingServiceScreenState._line),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: _BookingServiceScreenState._accent,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Точная стоимость зависит от сложности и деталей. Все нюансы можно обсудить на консультации.',
              style: TextStyle(
                color: _BookingServiceScreenState._muted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _bookingMasterName(MasterProfile? profile) {
  final username = profile?.username.trim() ?? '';
  if (username.isNotEmpty) {
    return username.startsWith('@') ? username : '@$username';
  }
  return 'Мастер';
}

String _bookingMasterFullName(MasterProfile? profile) {
  final displayName = profile?.displayName.trim() ?? '';
  if (displayName.isEmpty || displayName == _bookingMasterName(profile)) {
    return '';
  }
  return displayName;
}

String _bookingMasterStudioName(MasterProfile? profile) {
  return profile?.studioName.trim() ?? '';
}

String _bookingMasterCity(MasterProfile? profile) {
  final city = profile?.city.trim() ?? '';
  return city.isEmpty ? 'Город скрыт' : city;
}

double _bookingMasterRating(MasterProfile? profile) {
  return profile?.rating ?? 0;
}

String _bookingMasterReviewText(MasterProfile? profile) {
  final count = profile?.reviewCount ?? 0;
  return '$count';
}

String? _bookingMasterPriceLabel(MasterProfile? profile) {
  final minPrice = profile?.minSessionPrice ?? 0;
  if (minPrice <= 0) {
    return null;
  }
  return 'от ${_BookingServiceScreenState._formatRubles(minPrice)} ₽';
}

class _MasterSummaryCard extends StatelessWidget {
  const _MasterSummaryCard({this.profile});

  final MasterProfile? profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _BookingServiceScreenState._line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BookingProfileHeroImage(avatarUrl: profile?.avatarUrl ?? ''),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MasterNameRow(profile: profile, fontSize: 18),
                finalText(_bookingMasterFullName(profile)),
                finalText(_bookingMasterStudioName(profile), prefix: 'Студия или рабочее имя: '),
                const SizedBox(height: 10),
                _RatingLine(
                  rating: _bookingMasterRating(profile),
                  reviewText: _bookingMasterReviewText(profile),
                ),
                const SizedBox(height: 12),
                _MetaRow(
                  icon: Icons.location_on_outlined,
                  text: _bookingMasterCity(profile),
                ),
                finalPrice(_bookingMasterPriceLabel(profile)),
                finalStyles(profile?.styles ?? const <String>[]),
                const SizedBox(height: 18),
                const Text(
                  'Перед отправкой заявки:',
                  style: TextStyle(
                    color: _BookingServiceScreenState._text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'выберите услугу, дату и свободное время',
                  style: TextStyle(
                    color: _BookingServiceScreenState._muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget finalText(String text, {String prefix = ''}) {
    final value = text.trim();
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$prefix$value',
        style: const TextStyle(
          color: Color(0xFF4A5565),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget finalPrice(String? price) {
    if (price == null || price.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        price,
        style: const TextStyle(
          color: _BookingServiceScreenState._text,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget finalStyles(List<String> styles) {
    final visibleStyles = styles.where((style) => style.trim().isNotEmpty).take(6).toList();
    if (visibleStyles.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final style in visibleStyles) _BookingProfileChip(style),
        ],
      ),
    );
  }
}

class _MobileMasterStrip extends StatelessWidget {
  const _MobileMasterStrip({this.profile});

  final MasterProfile? profile;

  @override
  Widget build(BuildContext context) {
    final price = _bookingMasterPriceLabel(profile);
    return _Surface(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ProfileImage(
            avatarUrl: profile?.avatarUrl ?? '',
            fallbackAssetPath: _BookingServiceScreenState._image,
            width: 104,
            height: 130,
            borderRadius: 10,
            fit: BoxFit.cover,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MasterNameRow(profile: profile, fontSize: 16),
                finalText(_bookingMasterFullName(profile)),
                finalText(_bookingMasterStudioName(profile), prefix: 'Студия: '),
                const SizedBox(height: 8),
                _RatingLine(
                  rating: _bookingMasterRating(profile),
                  reviewText: _bookingMasterReviewText(profile),
                  small: true,
                ),
                const SizedBox(height: 8),
                _MetaRow(
                  icon: Icons.location_on_outlined,
                  text: _bookingMasterCity(profile),
                  small: true,
                ),
                if (price != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    price,
                    style: const TextStyle(
                      color: _BookingServiceScreenState._text,
                      fontWeight: FontWeight.w800,
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

  Widget finalText(String text, {String prefix = ''}) {
    final value = text.trim();
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        '$prefix$value',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _BookingServiceScreenState._muted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _BookingProfileHeroImage extends StatelessWidget {
  const _BookingProfileHeroImage({required this.avatarUrl});

  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProfileImage(
            avatarUrl: avatarUrl,
            fallbackAssetPath: _BookingServiceScreenState._image,
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.02),
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.62),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              children: const [
                _BookingRoundIconButton(icon: Icons.bookmark_border_rounded),
                SizedBox(width: 8),
                _BookingRoundIconButton(icon: Icons.share_outlined),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xEE102017),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFF2DD4BF),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(width: 6, height: 6),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Онлайн',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
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

class _BookingRoundIconButton extends StatelessWidget {
  const _BookingRoundIconButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        shape: BoxShape.circle,
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: Icon(icon, color: const Color(0xFF14213D), size: 22),
    );
  }
}

class _BookingProfileChip extends StatelessWidget {
  const _BookingProfileChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1D2A3A),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({
    required this.visibleMonth,
    required this.selectedDate,
    required this.onSelectDate,
    required this.onChangeMonth,
    required this.masterSchedule,
    required this.useBackendSchedule,
    required this.compact,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<int> onChangeMonth;
  final List<MasterScheduleDay> masterSchedule;
  final bool useBackendSchedule;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final calendar = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Выберите дату',
          style: TextStyle(
            color: _BookingServiceScreenState._text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        _CalendarHeader(
          visibleMonth: visibleMonth,
          onPrevious: () => onChangeMonth(-1),
          onNext: () => onChangeMonth(1),
        ),
        const SizedBox(height: 18),
        _CalendarGrid(
          visibleMonth: visibleMonth,
          selectedDate: selectedDate,
          onSelectDate: onSelectDate,
          masterSchedule: masterSchedule,
          useBackendSchedule: useBackendSchedule,
        ),
      ],
    );

    return compact
        ? _Surface(padding: const EdgeInsets.all(16), child: calendar)
        : calendar;
  }
}

class _TimeSection extends StatelessWidget {
  const _TimeSection({
    required this.selectedDate,
    required this.selectedTime,
    required this.selectedService,
    required this.availabilitySlots,
    required this.isLoading,
    required this.useBackendAvailability,
    required this.onSelectTime,
    required this.compact,
  });

  final DateTime selectedDate;
  final String selectedTime;
  final _BookingServiceOption? selectedService;
  final List<AvailabilitySlot>? availabilitySlots;
  final bool isLoading;
  final bool useBackendAvailability;
  final ValueChanged<String> onSelectTime;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final slots = availabilitySlots ?? const <AvailabilitySlot>[];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Выберите время',
          style: TextStyle(
            color: _BookingServiceScreenState._text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        if (isLoading) ...[
          const _BookingServiceNotice(
            icon: Icons.schedule_outlined,
            text: 'Загружаем свободное время мастера по его графику работы.',
          ),
        ] else if (slots.isEmpty) ...[
          const _BookingServiceNotice(
            icon: Icons.event_busy_outlined,
            text: 'На выбранную дату нет доступного времени. Выберите другую дату.',
          ),
        ] else ...[
          Wrap(
            spacing: compact ? 8 : 10,
            runSpacing: compact ? 8 : 10,
            children: slots.map((slot) {
              final disabled = !slot.available;
              return _TimeChip(
                label: slot.time,
                selected: slot.time == selectedTime,
                disabled: disabled,
                reason: slot.reason,
                compact: compact,
                onTap: disabled ? null : () => onSelectTime(slot.time),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (selectedTime.isNotEmpty)
            _SelectedTimeNote(
              selectedDate: selectedDate,
              selectedTime: selectedTime,
            ),
        ],
      ],
    );

    return compact
        ? _Surface(padding: const EdgeInsets.all(16), child: content)
        : content;
  }

}

class _CommentField extends StatelessWidget {
  const _CommentField({required this.controller, required this.compact});

  final TextEditingController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text.rich(
          TextSpan(
            text: 'Комментарий',
            style: TextStyle(
              color: _BookingServiceScreenState._text,
              fontWeight: FontWeight.w800,
            ),
            children: [
              TextSpan(
                text: ' (необязательно)',
                style: TextStyle(
                  color: _BookingServiceScreenState._muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 150,
          decoration: const InputDecoration(
            constraints: BoxConstraints(minHeight: 96),
            labelText: 'Комментарий',
            hintText: 'Расскажите немного о записи...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 15,
              color: _BookingServiceScreenState._muted,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Комментарий поможет мастеру подготовиться к сеансу',
                style: TextStyle(
                  color: _BookingServiceScreenState._muted,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

bool _scheduleHasWorkOnDate(List<MasterScheduleDay> schedule, DateTime date) {
  final dayIndex = (date.weekday + 6) % 7;
  for (final day in schedule) {
    if (day.dayIndex == dayIndex) {
      return day.enabled &&
          day.intervals.any(
            (interval) =>
                interval.type == 'work' &&
                interval.endMinute > interval.startMinute,
          );
    }
  }
  return false;
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.visibleMonth,
    required this.selectedDate,
    required this.onSelectDate,
    required this.masterSchedule,
    required this.useBackendSchedule,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final List<MasterScheduleDay> masterSchedule;
  final bool useBackendSchedule;

  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    return Column(
      children: [
        Row(
          children: _weekdays
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: const TextStyle(
                        color: _BookingServiceScreenState._muted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        ...List.generate(6, (row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: List.generate(7, (column) {
                final date = _dateForCell(row * 7 + column);
                final normalized = DateUtils.dateOnly(date);
                final inMonth = date.month == visibleMonth.month;
                final workingDay = !useBackendSchedule ||
                    _scheduleHasWorkOnDate(masterSchedule, date);
                final disabled = !inMonth ||
                    normalized.isBefore(today) ||
                    !workingDay;
                final selected = DateUtils.isSameDay(date, selectedDate);
                final canSelect = !disabled;
                return Expanded(
                  child: Center(
                    child: _CalendarDay(
                      day: date.day,
                      disabled: disabled,
                      selected: selected,
                      available: inMonth &&
                          !normalized.isBefore(today) &&
                          workingDay &&
                          useBackendSchedule,
                      onTap: canSelect ? () => onSelectDate(date) : null,
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  DateTime _dateForCell(int index) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final offsetFromMonday = firstDay.weekday - DateTime.monday;
    return firstDay.add(Duration(days: index - offsetFromMonday));
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.disabled,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  final int day;
  final bool disabled;
  final bool selected;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 34,
        height: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? _BookingServiceScreenState._accent
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : disabled
                          ? const Color(0xFFC4C7CE)
                          : _BookingServiceScreenState._text,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: available && !selected
                    ? _BookingServiceScreenState._accent
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: _BookingServiceScreenState._muted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.reason,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final String reason;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _timeChipColors(reason);
    return SizedBox(
      width: compact ? 82 : 96,
      height: compact ? 44 : 46,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          disabledBackgroundColor: colors.background,
          disabledForegroundColor: colors.foreground,
          backgroundColor: selected
              ? _BookingServiceScreenState._accent
              : disabled
                  ? colors.background
                  : Colors.white,
          foregroundColor: selected
              ? Colors.white
              : disabled
                  ? colors.foreground
                  : _BookingServiceScreenState._text,
          side: BorderSide(
            color: selected
                ? _BookingServiceScreenState._accent
                : disabled
                    ? colors.border
                    : _BookingServiceScreenState._line,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  _TimeChipColors _timeChipColors(String reason) {
    return switch (reason) {
      'break' => const _TimeChipColors(
          background: Color(0xFFFFF3D8),
          foreground: Color(0xFF9A5A00),
          border: Color(0xFFFFD48A),
        ),
      'busy' => const _TimeChipColors(
          background: Color(0xFFECEFF3),
          foreground: Color(0xFF7A8190),
          border: Color(0xFFD7DCE3),
        ),
      'too_short' => const _TimeChipColors(
          background: Color(0xFFF2F3F5),
          foreground: Color(0xFFA3A8B2),
          border: Color(0xFFE2E5EA),
        ),
      'outside_schedule' => const _TimeChipColors(
          background: Color(0xFFF7F5F1),
          foreground: Color(0xFFB8BDC7),
          border: Color(0xFFECE8E1),
        ),
      _ => const _TimeChipColors(
          background: Color(0xFFF7F5F1),
          foreground: Color(0xFFB8BDC7),
          border: Color(0xFFECE8E1),
        ),
    };
  }
}

class _TimeChipColors {
  const _TimeChipColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

class _SelectedTimeNote extends StatelessWidget {
  const _SelectedTimeNote({
    required this.selectedDate,
    required this.selectedTime,
  });

  final DateTime selectedDate;
  final String selectedTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F3ED),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE8E1D8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.schedule,
            color: _BookingServiceScreenState._accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Вы выбрали: ${_BookingServiceScreenState._dateLabel(selectedDate)} в $selectedTime',
                  style: const TextStyle(
                    color: _BookingServiceScreenState._text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox.shrink(),
                const Text(
                  '',
                  style: TextStyle(
                    color: _BookingServiceScreenState._muted,
                    fontSize: 0,
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

class _StepProgress extends StatelessWidget {
  const _StepProgress({
    required this.compact,
    required this.hasPreselectedService,
    required this.serviceSelected,
  });

  final bool compact;
  final bool hasPreselectedService;
  final bool serviceSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Выбор даты и времени', 'Подтверждение', 'Готово'];
    final stepLabels = hasPreselectedService
        ? ['Выбор даты и времени', 'Подтверждение', 'Готово']
        : ['Выбор услуги', 'Выбор даты и времени', 'Подтверждение'];
    final activeIndex = hasPreselectedService
        ? 0
        : serviceSelected
            ? 1
            : 0;
    final progress = Row(
      children: [
        _StepBubble(index: 1, active: activeIndex == 0, label: stepLabels[0]),
        Expanded(
          child: Container(height: 1, color: _BookingServiceScreenState._line),
        ),
        _StepBubble(index: 2, active: activeIndex == 1, label: stepLabels[1]),
        Expanded(
          child: Container(height: 1, color: _BookingServiceScreenState._line),
        ),
        _StepBubble(index: 3, active: activeIndex == 2, label: stepLabels[2]),
      ],
    );

    if (!compact) {
      return progress;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: 560, child: progress),
    );
  }
}

class _StepBubble extends StatelessWidget {
  const _StepBubble({
    required this.index,
    required this.active,
    required this.label,
  });

  final int index;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _BookingServiceScreenState._accent : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? _BookingServiceScreenState._accent
                  : _BookingServiceScreenState._line,
            ),
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: active ? Colors.white : _BookingServiceScreenState._muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: active
                  ? _BookingServiceScreenState._text
                  : _BookingServiceScreenState._muted,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _PriceInfoCard extends StatelessWidget {
  const _PriceInfoCard({this.profile});

  final MasterProfile? profile;

  @override
  Widget build(BuildContext context) {
    final hourlyRate = profile?.hourlyRate ?? 0;
    final minSessionPrice = profile?.minSessionPrice ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9E2D9)),
      ),
      child: Column(
        children: [
          _InfoLine(
            icon: Icons.spa_outlined,
            title: hourlyRate > 0
                ? '${_BookingServiceScreenState._formatRubles(hourlyRate)} ₽ / час'
                : 'Стоимость за час не указана',
            subtitle: 'Стоимость за час работы',
          ),
          const Divider(height: 20, color: Color(0xFFE9E2D9)),
          _InfoLine(
            icon: Icons.verified_user_outlined,
            title: minSessionPrice > 0
                ? 'Минимальная стоимость — ${_BookingServiceScreenState._formatRubles(minSessionPrice)} ₽'
                : 'Минимальная стоимость не указана',
            subtitle: 'Ориентир перед подтверждением записи',
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _BookingServiceScreenState._accent.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: _BookingServiceScreenState._accent,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _BookingServiceScreenState._text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _BookingServiceScreenState._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _BookingServiceScreenState._card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _BookingServiceScreenState._line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: child,
    );
  }
}

class _BackToProfile extends StatelessWidget {
  const _BackToProfile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _BookingServiceScreenState._muted,
        padding: EdgeInsets.zero,
      ),
      icon: const Icon(Icons.arrow_back, size: 18),
      label: const Text('Назад к профилю'),
    );
  }
}

class _MobileTitle extends StatelessWidget {
  const _MobileTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Запись на услугу',
      style: TextStyle(
        color: _BookingServiceScreenState._text,
        fontSize: 24,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _MasterNameRow extends StatelessWidget {
  const _MasterNameRow({required this.fontSize, this.profile});

  final double fontSize;
  final MasterProfile? profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            _bookingMasterName(profile),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _BookingServiceScreenState._text,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.verified,
          color: _BookingServiceScreenState._accent,
          size: 18,
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text, this.small = false});

  final IconData icon;
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: small ? 14 : 16,
          color: _BookingServiceScreenState._muted,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: _BookingServiceScreenState._muted,
            fontSize: small ? 12 : 14,
          ),
        ),
      ],
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({
    required this.reviewText,
    required this.rating,
    this.small = false,
  });

  final String reviewText;
  final double rating;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.star, color: Color(0xFFF6A623), size: 18),
        const SizedBox(width: 5),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            color: _BookingServiceScreenState._text,
            fontSize: small ? 13 : 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '($reviewText)',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _BookingServiceScreenState._muted,
              fontSize: small ? 12 : 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.visibleMonth,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime visibleMonth;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          splashRadius: 20,
          icon: const Icon(
            Icons.chevron_left,
            color: _BookingServiceScreenState._text,
          ),
        ),
        Expanded(
          child: Center(
            child: Text(
              '${_BookingServiceScreenState._monthName(visibleMonth.month)} ${visibleMonth.year}',
              style: const TextStyle(
                color: _BookingServiceScreenState._text,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          splashRadius: 20,
          icon: const Icon(
            Icons.chevron_right,
            color: _BookingServiceScreenState._text,
          ),
        ),
      ],
    );
  }
}

class _AvailableHint extends StatelessWidget {
  const _AvailableHint();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.circle, size: 8, color: _BookingServiceScreenState._accent),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Доступные даты выделены зелёным',
            style: TextStyle(
              color: _BookingServiceScreenState._muted,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
