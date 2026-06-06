import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../api/api_client.dart';
import '../city/city_catalog.dart';
import '../models.dart';
import '../style_options.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../validators.dart' as validators;
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/city_autocomplete_field.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/remote_or_asset_image.dart';

enum ServiceType { session, consultation, sketch }

enum SettingsSection {
  profile,
  servicesPrices,
  schedule,
  notifications,
  security,
}

const _card = AuthenticatedDashboardTheme.card;
const _accent = AuthenticatedDashboardTheme.accent;
const _text = AuthenticatedDashboardTheme.text;
const _muted = AuthenticatedDashboardTheme.muted;
const _line = AuthenticatedDashboardTheme.line;
const _soft = AuthenticatedDashboardTheme.soft;
const _profileSaveDisabled = Color(0x52306B5F);
const _profileSaveDisabledText = Color(0xFFF8FCFA);
const _maxAvatarBytes = 5 * 1024 * 1024;
final _moneyInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  const _SingleLeadingZeroInputFormatter(),
];
const _tattooStyles = inkConnectTattooStyles;

class _SingleLeadingZeroInputFormatter extends TextInputFormatter {
  const _SingleLeadingZeroInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final normalized = RegExp(r'^0+$').hasMatch(digitsOnly)
        ? '0'
        : digitsOnly.replaceFirst(RegExp(r'^0+'), '');

    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}

class MasterService {
  const MasterService({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.durationHours,
    required this.price,
    required this.useAutoPrice,
    this.fromPrice = false,
  });

  final String id;
  final String name;
  final String description;
  final ServiceType type;
  final double? durationHours;
  final int price;
  final bool useAutoPrice;
  final bool fromPrice;

  MasterService copyWith({
    String? id,
    String? name,
    String? description,
    ServiceType? type,
    double? durationHours,
    bool clearDuration = false,
    int? price,
    bool? useAutoPrice,
    bool? fromPrice,
  }) {
    return MasterService(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      durationHours: clearDuration ? null : durationHours ?? this.durationHours,
      price: price ?? this.price,
      useAutoPrice: useAutoPrice ?? this.useAutoPrice,
      fromPrice: fromPrice ?? this.fromPrice,
    );
  }
}

class ServicesPricesScreen extends StatefulWidget {
  const ServicesPricesScreen({
    super.key,
    required this.user,
    required this.userName,
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
    required this.onLogout,
    this.api,
    this.sessionToken,
    this.initialMasterSettings,
    this.initialServices,
    this.initialSection = SettingsSection.servicesPrices,
    this.initialShowFullName = true,
    this.initialShowCity = true,
    this.onProfileChanged,
    this.onMasterSettingsChanged,
    this.onServicesChanged,
    this.onShowFullNameChanged,
    this.onShowCityChanged,
  });

  final AuthUser? user;
  final String userName;
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
  final Future<void> Function() onLogout;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final MasterSettings? initialMasterSettings;
  final List<MasterServiceSettings>? initialServices;
  final SettingsSection initialSection;
  final bool initialShowFullName;
  final bool initialShowCity;
  final ValueChanged<UserProfile>? onProfileChanged;
  final ValueChanged<MasterSettings>? onMasterSettingsChanged;
  final ValueChanged<List<MasterServiceSettings>>? onServicesChanged;
  final ValueChanged<bool>? onShowFullNameChanged;
  final ValueChanged<bool>? onShowCityChanged;

  @override
  State<ServicesPricesScreen> createState() => _ServicesPricesScreenState();
}

class _ServicesPricesScreenState extends State<ServicesPricesScreen> {
  final TextEditingController _minPriceController = TextEditingController(
    text: '5000',
  );
  final TextEditingController _hourlyRateController = TextEditingController(
    text: '2500',
  );
  final TextEditingController _lastNameController = TextEditingController(
    text: 'Козлова',
  );
  final TextEditingController _firstNameController = TextEditingController(
    text: 'Мария',
  );
  final TextEditingController _middleNameController = TextEditingController(
    text: 'Андреевна',
  );
  final TextEditingController _studioController = TextEditingController();
  final TextEditingController _cityController = TextEditingController(
    text: 'Москва',
  );
  final TextEditingController _bioController = TextEditingController(
    text:
        'Тату-мастер с вниманием к деталям. Специализируюсь на графичных композициях, японских мотивах и леттеринге.',
  );

  late SettingsSection _selectedSection;
  int _minSessionPrice = 5000;
  int _hourlyRate = 2500;
  String _breakBetweenClients = '30 минут';
  String _masterCategory = 'Тату-мастер';
  final List<String> _selectedTattooStyles = [..._tattooStyles];
  bool _saved = false;
  bool _profileSaved = false;
  bool _showFullName = true;
  bool _showCity = true;
  bool _hasPhoto = true;
  bool _useUploadedPreview = false;
  String _avatarUrl = '';
  bool _avatarBusy = false;
  String? _loadedProfileToken;
  String _savedProfileLastName = '';
  String _savedProfileFirstName = '';
  String _savedProfileMiddleName = '';
  String _savedProfileStudioName = '';
  String _savedProfileCity = '';
  String _savedProfileBio = '';
  bool _savedProfileShowFullName = true;
  bool _savedProfileShowCity = true;
  CityOption? _selectedProfileCity;
  String? _profileCityError;
  String? _loadedServicesToken;
  String? _loadedMasterSettingsToken;
  Set<String> _backendServiceIds = <String>{};

  bool get _isMaster => widget.user?.role == 'master';

  bool get _profileHasChanges =>
      _lastNameController.text != _savedProfileLastName ||
      _firstNameController.text != _savedProfileFirstName ||
      _middleNameController.text != _savedProfileMiddleName ||
      (_isMaster && _studioController.text != _savedProfileStudioName) ||
      _cityController.text != _savedProfileCity ||
      _bioController.text != _savedProfileBio ||
      _showFullName != _savedProfileShowFullName ||
      _showCity != _savedProfileShowCity;

  List<SettingsSection> get _visibleSections =>
      _settingsSectionsFor(widget.user);

  late List<MasterService> _services = [
    const MasterService(
      id: 'minimal',
      name: 'Минимальная тату',
      description: 'Небольшие татуировки до 5 см',
      type: ServiceType.session,
      durationHours: 1,
      price: 5000,
      useAutoPrice: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    final sections = _settingsSectionsFor(widget.user);
    _selectedSection = sections.contains(widget.initialSection)
        ? widget.initialSection
        : SettingsSection.profile;
    _showFullName = widget.initialShowFullName;
    _showCity = widget.initialShowCity;
    _studioController.text = widget.user?.studioName.trim() ?? '';
    final initialMasterSettings = widget.initialMasterSettings;
    if (initialMasterSettings != null) {
      _applyMasterSettings(initialMasterSettings, saved: true, notify: false);
    }
    final initialServices = widget.initialServices;
    if (initialServices != null) {
      _applyServiceSettings(initialServices, saved: true, notify: false);
    }
    _rememberSavedProfileSnapshot();
    _loadProfile();
    _loadMasterSettings();
    _loadServices();
  }

  @override
  void didUpdateWidget(covariant ServicesPricesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_visibleSections.contains(_selectedSection)) {
      _selectedSection = SettingsSection.profile;
    }
    if (oldWidget.sessionToken != widget.sessionToken) {
      _loadedProfileToken = null;
      _loadedMasterSettingsToken = null;
      _loadedServicesToken = null;
      _loadProfile();
      _loadMasterSettings();
      _loadServices();
    }
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _hourlyRateController.dispose();
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _studioController.dispose();
    _cityController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedPageShell(
      user: widget.user,
      userName: widget.userName,
      activeSidebarItem: AuthenticatedSidebarItem.settings,
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
    return Container(
      color: Colors.white,
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsSidebar(
                  selected: _selectedSection,
                  sections: _visibleSections,
                  onSelected: _selectSection,
                ),
                Expanded(child: _settingsBody(isDesktop: true)),
              ],
            )
          : _settingsBody(isDesktop: false),
    );
  }

  Widget _settingsBody({required bool isDesktop}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 40 : 16,
        isDesktop ? 30 : 18,
        isDesktop ? 40 : 16,
        isDesktop ? 48 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isDesktop) ...[
                _MobileSettingsTabs(
                  selected: _selectedSection,
                  sections: _visibleSections,
                  onSelected: _selectSection,
                ),
                const SizedBox(height: 18),
              ],
              if (_selectedSection == SettingsSection.profile) ...[
                _ProfileSettingsCard(
                  userName: widget.userName,
                  hasPhoto: _hasPhoto,
                  useUploadedPreview: _useUploadedPreview,
                  avatarUrl: _avatarUrl,
                  avatarBusy: _avatarBusy,
                  lastNameController: _lastNameController,
                  firstNameController: _firstNameController,
                  middleNameController: _middleNameController,
                  isMaster: _isMaster,
                  studioController: _studioController,
                  cityController: _cityController,
                  selectedCity: _selectedProfileCity,
                  cityErrorText: _profileCityError,
                  bioController: _bioController,
                  showFullName: _showFullName,
                  showCity: _showCity,
                  saved: _profileSaved,
                  onUploadPhoto: _uploadPhoto,
                  onDeletePhoto: _deletePhoto,
                  onShowFullNameChanged: (value) {
                    setState(() {
                      _showFullName = value;
                      _profileSaved = !_profileHasChanges;
                    });
                    widget.onShowFullNameChanged?.call(value);
                  },
                  onShowCityChanged: (value) {
                    setState(() {
                      _showCity = value;
                      _profileSaved = !_profileHasChanges;
                    });
                    widget.onShowCityChanged?.call(value);
                  },
                  onCitySelected: (option) {
                    setState(() {
                      _selectedProfileCity = option;
                      _profileCityError = null;
                      _profileSaved = !_profileHasChanges;
                    });
                  },
                  onChanged: _handleProfileChanged,
                  onSave: _profileHasChanges ? _saveProfileChanges : null,
                ),
              ] else if (_selectedSection == SettingsSection.schedule &&
                  _isMaster) ...[
                _WorkScheduleSettingsScreen(
                  api: widget.api,
                  sessionToken: widget.sessionToken,
                ),
              ] else if (_selectedSection == SettingsSection.security) ...[
                SecuritySettingsScreen(
                  user: widget.user,
                  api: widget.api,
                  sessionToken: widget.sessionToken,
                  onLogout: widget.onLogout,
                ),
              ] else if (_selectedSection !=
                  SettingsSection.servicesPrices) ...[
                _PlaceholderSettingsCard(section: _selectedSection),
              ] else ...[
                _HeaderRow(saved: _saved),
                const SizedBox(height: 22),
                _MasterCategoryCard(
                  isDesktop: isDesktop,
                  category: _masterCategory,
                  selectedStyles: _selectedTattooStyles,
                  onCategoryChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _masterCategory = value;
                      _saved = false;
                    });
                    _notifyMasterSettingsChanged();
                  },
                  onAddStyle: (style) {
                    setState(() {
                      if (!_selectedTattooStyles.contains(style)) {
                        _selectedTattooStyles.add(style);
                      }
                      _saved = false;
                    });
                    _notifyMasterSettingsChanged();
                  },
                  onRemoveStyle: (style) {
                    setState(() {
                      _selectedTattooStyles.remove(style);
                      _saved = false;
                    });
                    _notifyMasterSettingsChanged();
                  },
                ),
                const SizedBox(height: 18),
                _WorkTermsCard(
                  isDesktop: isDesktop,
                  minPriceController: _minPriceController,
                  hourlyRateController: _hourlyRateController,
                  breakValue: _breakBetweenClients,
                  onMinPriceChanged: _updateMinPrice,
                  onHourlyRateChanged: _updateHourlyRate,
                  onBreakChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _breakBetweenClients = value;
                      _saved = false;
                    });
                    _notifyMasterSettingsChanged();
                  },
                ),
                const SizedBox(height: 18),
                _ServicesCard(
                  services: _services,
                  minSessionPrice: _minSessionPrice,
                  hourlyRate: _hourlyRate,
                  onAdd: () => _openServiceEditor(),
                  onEdit: _openServiceEditor,
                  onDelete: _deleteService,
                  onDurationChanged: _changeDuration,
                  onPriceChanged: _changePrice,
                ),
                const SizedBox(height: 16),
                const _InfoBlock(),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveChanges,
                    child: const Text('Сохранить изменения'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _selectSection(SettingsSection section) {
    if (!_visibleSections.contains(section)) {
      return;
    }
    setState(() => _selectedSection = section);
    if (section != SettingsSection.profile &&
        section != SettingsSection.servicesPrices &&
        section != SettingsSection.schedule &&
        section != SettingsSection.security) {
      _showMockAction('${_settingsLabel(section)} будет добавлен позже');
    }
  }

  Future<void> _loadProfile() async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      return;
    }
    if (_loadedProfileToken == token) {
      return;
    }
    _loadedProfileToken = token;

    try {
      final profile = await api.currentProfile(token);
      if (!mounted) {
        return;
      }
      _applyProfile(profile, saved: true);
    } catch (_) {
      // Keep the current local/mock values until the profile endpoint is ready.
    }
  }

  void _applyProfile(UserProfile profile, {required bool saved}) {
    setState(() {
      _lastNameController.text = profile.lastName;
      _firstNameController.text = profile.firstName;
      _middleNameController.text = profile.middleName;
      _studioController.text = profile.studioName;
      _cityController.text = profile.city;
      _bioController.text = profile.bio;
      _showFullName = profile.showFullNameInProfile;
      _showCity = profile.showCityInProfile;
      _avatarUrl = profile.avatarUrl;
      if (_avatarUrl.trim().isNotEmpty) {
        _hasPhoto = true;
        _useUploadedPreview = false;
      }
      _selectedProfileCity = null;
      _profileCityError = null;
      _profileSaved = saved;
      _rememberSavedProfileSnapshot();
    });
    widget.onProfileChanged?.call(profile);
    widget.onShowFullNameChanged?.call(profile.showFullNameInProfile);
    widget.onShowCityChanged?.call(profile.showCityInProfile);
  }

  Future<void> _loadMasterSettings() async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (!_isMaster || api == null || token == null || token.isEmpty) {
      return;
    }
    if (_loadedMasterSettingsToken == token) {
      return;
    }
    _loadedMasterSettingsToken = token;

    try {
      final settings = await api.currentMasterSettings(token);
      if (!mounted) {
        return;
      }
      _applyMasterSettings(settings, saved: true, notify: true);
    } catch (_) {
      // Keep the current local/mock master settings until the endpoint is ready.
    }
  }

  void _applyMasterSettings(
    MasterSettings settings, {
    required bool saved,
    required bool notify,
  }) {
    setState(() {
      _masterCategory = settings.category;
      _selectedTattooStyles
        ..clear()
        ..addAll(settings.styles);
      _minSessionPrice = settings.minSessionPrice;
      _hourlyRate = settings.hourlyRate;
      _breakBetweenClients = settings.breakBetweenClients;
      _minPriceController.text = settings.minSessionPrice.toString();
      _hourlyRateController.text = settings.hourlyRate.toString();
      _syncAutoPrices();
      _saved = saved;
    });
    if (notify) {
      widget.onMasterSettingsChanged?.call(settings);
      _notifyServicesChanged();
    }
  }

  MasterSettings _currentMasterSettingsPayload() {
    return MasterSettings(
      category: _masterCategory,
      styles: List.unmodifiable(_selectedTattooStyles),
      minSessionPrice: _minSessionPrice,
      hourlyRate: _hourlyRate,
      breakBetweenClients: _breakBetweenClients,
    );
  }

  MasterSettingsPayload _masterSettingsPayload() {
    return MasterSettingsPayload(
      category: _masterCategory,
      styles: List.unmodifiable(_selectedTattooStyles),
      minSessionPrice: _minSessionPrice,
      hourlyRate: _hourlyRate,
      breakBetweenClients: _breakBetweenClients,
    );
  }

  void _notifyMasterSettingsChanged() {
    widget.onMasterSettingsChanged?.call(_currentMasterSettingsPayload());
  }

  Future<void> _loadServices() async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (!_isMaster || api == null || token == null || token.isEmpty) {
      return;
    }
    if (_loadedServicesToken == token) {
      return;
    }
    _loadedServicesToken = token;

    try {
      final services = await api.currentMasterServices(token);
      if (!mounted) {
        return;
      }
      _applyServiceSettings(services, saved: true, notify: true);
    } catch (_) {
      // Keep the current local/mock services until the master services endpoint is ready.
    }
  }

  void _applyServiceSettings(
    List<MasterServiceSettings> services, {
    required bool saved,
    required bool notify,
  }) {
    setState(() {
      _services = services.map(_serviceFromSettings).toList();
      _backendServiceIds = {
        for (final service in services)
          if (_isBackendServiceId(service.id)) service.id,
      };
      _saved = saved;
    });
    if (notify) {
      widget.onServicesChanged?.call(services);
    }
  }

  void _notifyServicesChanged() {
    widget.onServicesChanged?.call(
      _services.map(_settingsFromService).toList(),
    );
  }

  void _rememberSavedProfileSnapshot() {
    _savedProfileLastName = _lastNameController.text;
    _savedProfileFirstName = _firstNameController.text;
    _savedProfileMiddleName = _middleNameController.text;
    _savedProfileStudioName = _studioController.text;
    _savedProfileCity = _cityController.text;
    _savedProfileBio = _bioController.text;
    _savedProfileShowFullName = _showFullName;
    _savedProfileShowCity = _showCity;
  }

  void _handleProfileChanged() {
    setState(() {
      if (_selectedProfileCity?.displayName != _cityController.text.trim()) {
        _selectedProfileCity = null;
      }
      _profileCityError = null;
      _profileSaved = !_profileHasChanges;
    });
  }

  void _updateMinPrice(String value) {
    setState(() {
      _minSessionPrice = _parseMoney(value);
      _syncAutoPrices();
      _saved = false;
    });
    _notifyMasterSettingsChanged();
    _notifyServicesChanged();
  }

  void _updateHourlyRate(String value) {
    setState(() {
      _hourlyRate = _parseMoney(value);
      _syncAutoPrices();
      _saved = false;
    });
    _notifyMasterSettingsChanged();
    _notifyServicesChanged();
  }

  void _changeDuration(MasterService service, double? duration) {
    setState(() {
      _services = _services.map((item) {
        if (item.id != service.id) return item;
        final updated = item.copyWith(
          durationHours: duration,
          clearDuration: duration == null,
        );
        if (updated.useAutoPrice && updated.type == ServiceType.session) {
          return updated.copyWith(price: _recommendedPrice(updated));
        }
        return updated;
      }).toList();
      _saved = false;
    });
    _notifyServicesChanged();
  }

  void _changePrice(MasterService service, String value) {
    setState(() {
      _services = _services.map((item) {
        if (item.id != service.id) return item;
        return item.copyWith(price: _parseMoney(value), useAutoPrice: false);
      }).toList();
      _saved = false;
    });
    _notifyServicesChanged();
  }

  Future<void> _openServiceEditor([MasterService? service]) async {
    final result = await showModalBottomSheet<MasterService>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ServiceEditorSheet(
          service: service,
          minSessionPrice: _minSessionPrice,
          hourlyRate: _hourlyRate,
        );
      },
    );

    if (result == null) return;

    if (service == null) {
      await _createService(result);
      return;
    }

    await _updateService(service, result);
  }

  Future<void> _createService(MasterService service) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api != null && token != null && token.isNotEmpty && _isMaster) {
      try {
        final created = await api.createMasterService(
          sessionToken: token,
          payload: _payloadFromService(service),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _services = [..._services, _serviceFromSettings(created)];
          _backendServiceIds.add(created.id);
          _saved = true;
        });
        _notifyServicesChanged();
        _showMockAction('Услуга добавлена');
        return;
      } catch (_) {
        if (!mounted) {
          return;
        }
      }
    }

    setState(() {
      _services = [..._services, service];
      _saved = false;
    });
    _notifyServicesChanged();
    _showMockAction(
      'Не удалось сохранить услугу в backend. Услуга добавлена локально.',
    );
  }

  Future<void> _updateService(
    MasterService original,
    MasterService next,
  ) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api != null &&
        token != null &&
        token.isNotEmpty &&
        _isMaster &&
        _backendServiceIds.contains(original.id)) {
      try {
        final updated = await api.updateMasterService(
          sessionToken: token,
          serviceId: original.id,
          payload: _payloadFromService(next),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _services = _services
              .map(
                (item) => item.id == original.id
                    ? _serviceFromSettings(updated)
                    : item,
              )
              .toList();
          _backendServiceIds
            ..remove(original.id)
            ..add(updated.id);
          _saved = true;
        });
        _notifyServicesChanged();
        _showMockAction('Услуга обновлена');
        return;
      } catch (_) {
        if (!mounted) {
          return;
        }
      }
    }

    setState(() {
      _services = _services
          .map((item) => item.id == original.id ? next : item)
          .toList();
      _saved = false;
    });
    _notifyServicesChanged();
    _showMockAction(
      'Не удалось сохранить услугу в backend. Изменение оставлено локально.',
    );
  }

  Future<void> _deleteService(MasterService service) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api != null &&
        token != null &&
        token.isNotEmpty &&
        _isMaster &&
        _backendServiceIds.contains(service.id)) {
      try {
        await api.deleteMasterService(
          sessionToken: token,
          serviceId: service.id,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _services = _services.where((item) => item.id != service.id).toList();
          _backendServiceIds.remove(service.id);
          _saved = true;
        });
        _notifyServicesChanged();
        _showMockAction('Услуга удалена');
        return;
      } catch (_) {
        if (!mounted) {
          return;
        }
      }
    }

    setState(() {
      _services = _services.where((item) => item.id != service.id).toList();
      _backendServiceIds.remove(service.id);
      _saved = false;
    });
    _notifyServicesChanged();
    _showMockAction('Услуга удалена локально');
  }

  Future<void> _saveChanges() async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty || !_isMaster) {
      setState(() => _saved = true);
      _notifyMasterSettingsChanged();
      _notifyServicesChanged();
      _showMockAction('Изменения сохранены');
      return;
    }

    try {
      final savedSettings = await api.updateMasterSettings(
        sessionToken: token,
        payload: _masterSettingsPayload(),
      );
      final savedServices = <MasterService>[];
      final savedIds = <String>{};
      for (final service in _services) {
        final savedService = _backendServiceIds.contains(service.id)
            ? await api.updateMasterService(
                sessionToken: token,
                serviceId: service.id,
                payload: _payloadFromService(service),
              )
            : await api.createMasterService(
                sessionToken: token,
                payload: _payloadFromService(service),
              );
        savedServices.add(_serviceFromSettings(savedService));
        savedIds.add(savedService.id);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _masterCategory = savedSettings.category;
        _selectedTattooStyles
          ..clear()
          ..addAll(savedSettings.styles);
        _minSessionPrice = savedSettings.minSessionPrice;
        _hourlyRate = savedSettings.hourlyRate;
        _breakBetweenClients = savedSettings.breakBetweenClients;
        _minPriceController.text = savedSettings.minSessionPrice.toString();
        _hourlyRateController.text = savedSettings.hourlyRate.toString();
        _services = savedServices;
        _backendServiceIds = savedIds;
        _saved = true;
      });
      widget.onMasterSettingsChanged?.call(savedSettings);
      _notifyServicesChanged();
      _showMockAction('Изменения услуг сохранены');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _saved = false);
      _notifyServicesChanged();
      _showMockAction(
        'Не удалось сохранить услуги. Локальные данные не потеряны.',
      );
    }
  }

  Future<void> _uploadPhoto() async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      _showMockAction('Фото доступно после входа');
      return;
    }
    if (_avatarBusy) {
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
        withData: true,
      );
    } catch (_) {
      _showMockAction('Не удалось открыть выбор файла');
      return;
    }
    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showMockAction('Не удалось прочитать файл');
      return;
    }
    if (file.size > _maxAvatarBytes || bytes.length > _maxAvatarBytes) {
      _showMockAction('Фото должно быть не больше 5 МБ');
      return;
    }
    if (!_isSupportedAvatarExtension(file.extension ?? file.name)) {
      _showMockAction('Поддерживаются JPG, PNG и WEBP');
      return;
    }

    setState(() => _avatarBusy = true);
    try {
      final profile = await api.uploadProfileAvatar(
        sessionToken: token,
        bytes: bytes,
        filename: file.name.trim().isEmpty ? 'avatar.png' : file.name.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _hasPhoto = profile.avatarUrl.trim().isNotEmpty;
        _useUploadedPreview = false;
        _avatarUrl = profile.avatarUrl;
        _avatarBusy = false;
        _profileSaved = !_profileHasChanges;
      });
      widget.onProfileChanged?.call(profile);
      _showMockAction('Фото профиля обновлено');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _avatarBusy = false);
      _showMockAction(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _avatarBusy = false);
      _showMockAction('Не удалось загрузить фото');
    }
  }

  Future<void> _deletePhoto() async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      _showMockAction('Удаление фото доступно после входа');
      return;
    }
    if (_avatarBusy) {
      return;
    }

    setState(() => _avatarBusy = true);
    try {
      final profile = await api.deleteProfileAvatar(sessionToken: token);
      if (!mounted) {
        return;
      }
      setState(() {
        _hasPhoto = false;
        _useUploadedPreview = false;
        _avatarUrl = '';
        _avatarBusy = false;
        _profileSaved = !_profileHasChanges;
      });
      widget.onProfileChanged?.call(profile);
      _showMockAction('Фото профиля удалено');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _avatarBusy = false);
      _showMockAction(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _avatarBusy = false);
      _showMockAction('Не удалось удалить фото');
    }
  }

  bool _isSupportedAvatarExtension(String value) {
    final normalized = value.trim().toLowerCase();
    final extension = normalized.contains('.')
        ? normalized.split('.').last
        : normalized;
    return extension == 'jpg' ||
        extension == 'jpeg' ||
        extension == 'png' ||
        extension == 'webp';
  }

  Future<bool> _validateProfileCity() async {
    final city = _cityController.text.trim();
    if (city.isEmpty) {
      setState(() => _profileCityError = 'Укажите город');
      return false;
    }

    try {
      await CityCatalog.instance.load();
    } catch (_) {
      setState(() => _profileCityError = 'Не удалось загрузить список городов');
      return false;
    }

    final option = CityCatalog.instance.findByDisplayName(city);
    if (option == null) {
      setState(() => _profileCityError = 'Выберите город из списка');
      return false;
    }

    setState(() {
      _selectedProfileCity = option;
      _cityController.text = option.displayName;
      _profileCityError = null;
    });
    return true;
  }

  Future<void> _saveProfileChanges() async {
    if (!await _validateProfileCity()) {
      return;
    }

    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      setState(() {
        _rememberSavedProfileSnapshot();
        _profileSaved = true;
      });
      _showMockAction('Изменения профиля сохранены локально');
      return;
    }

    try {
      final profile = await api.updateProfile(
        sessionToken: token,
        payload: ProfileUpdatePayload(
          lastName: _lastNameController.text,
          firstName: _firstNameController.text,
          middleName: _middleNameController.text,
          studioName: _studioController.text,
          city: _cityController.text,
          bio: _bioController.text,
          showFullNameInProfile: _showFullName,
          showCityInProfile: _showCity,
        ),
      );
      if (!mounted) {
        return;
      }
      _applyProfile(profile, saved: true);
      _showMockAction('Изменения профиля сохранены');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showMockAction(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMockAction(
        'Не удалось сохранить профиль. Локальные данные не потеряны.',
      );
    }
  }

  void _syncAutoPrices() {
    _services = _services.map((item) {
      if (!item.useAutoPrice || item.type != ServiceType.session) {
        return item;
      }
      return item.copyWith(price: _recommendedPrice(item));
    }).toList();
  }

  int _recommendedPrice(MasterService service) {
    if (service.type != ServiceType.session || service.durationHours == null) {
      return service.price;
    }
    final duration = service.durationHours!;
    if (duration <= 1) {
      return _minSessionPrice;
    }
    return (_minSessionPrice + ((duration - 1) * _hourlyRate)).round();
  }

  MasterService _serviceFromSettings(MasterServiceSettings service) {
    return MasterService(
      id: service.id,
      name: service.name,
      description: service.description,
      type: _serviceTypeFromValue(service.type),
      durationHours: service.durationHours,
      price: service.price,
      useAutoPrice: service.useAutoPrice,
      fromPrice: service.fromPrice,
    );
  }

  MasterServiceSettings _settingsFromService(MasterService service) {
    return MasterServiceSettings(
      id: service.id,
      name: service.name,
      description: service.description,
      type: _serviceTypeValue(service.type),
      durationHours: service.durationHours,
      price: service.price,
      useAutoPrice: service.useAutoPrice,
      fromPrice: service.fromPrice,
    );
  }

  MasterServicePayload _payloadFromService(MasterService service) {
    return MasterServicePayload(
      name: service.name,
      description: service.description,
      type: _serviceTypeValue(service.type),
      durationHours: service.durationHours,
      price: service.price,
      useAutoPrice: service.useAutoPrice,
      fromPrice: service.fromPrice,
    );
  }

  void _showMockAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), behavior: SnackBarBehavior.floating),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.selected,
    required this.sections,
    required this.onSelected,
  });

  final SettingsSection selected;
  final List<SettingsSection> sections;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 30, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Настройки',
            style: TextStyle(
              color: _text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 24),
          for (final item in sections)
            _SettingsNavItem(
              section: item,
              active: item == selected,
              onTap: () => onSelected(item),
            ),
        ],
      ),
    );
  }
}

class _MobileSettingsTabs extends StatelessWidget {
  const _MobileSettingsTabs({
    required this.selected,
    required this.sections,
    required this.onSelected,
  });

  final SettingsSection selected;
  final List<SettingsSection> sections;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final item = sections[index];
          return _SettingsNavItem(
            section: item,
            active: item == selected,
            compact: true,
            onTap: () => onSelected(item),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: sections.length,
      ),
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.section,
    required this.active,
    required this.onTap,
    this.compact = false,
  });

  final SettingsSection section;
  final bool active;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? _soft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: active ? null : onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 14,
              vertical: compact ? 10 : 11,
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Icon(
                  _settingsIcon(section),
                  size: 17,
                  color: active ? _accent : _muted,
                ),
                const SizedBox(width: 9),
                Text(
                  _settingsLabel(section),
                  style: TextStyle(
                    color: active ? _accent : _text,
                    fontSize: compact ? 13 : 14,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSettingsCard extends StatelessWidget {
  const _ProfileSettingsCard({
    required this.userName,
    required this.hasPhoto,
    required this.useUploadedPreview,
    required this.avatarUrl,
    required this.avatarBusy,
    required this.lastNameController,
    required this.firstNameController,
    required this.middleNameController,
    required this.isMaster,
    required this.studioController,
    required this.cityController,
    required this.selectedCity,
    required this.cityErrorText,
    required this.bioController,
    required this.showFullName,
    required this.showCity,
    required this.saved,
    required this.onUploadPhoto,
    required this.onDeletePhoto,
    required this.onShowFullNameChanged,
    required this.onShowCityChanged,
    required this.onCitySelected,
    required this.onChanged,
    required this.onSave,
  });

  final String userName;
  final bool hasPhoto;
  final bool useUploadedPreview;
  final String avatarUrl;
  final bool avatarBusy;
  final TextEditingController lastNameController;
  final TextEditingController firstNameController;
  final TextEditingController middleNameController;
  final bool isMaster;
  final TextEditingController studioController;
  final TextEditingController cityController;
  final CityOption? selectedCity;
  final String? cityErrorText;
  final TextEditingController bioController;
  final bool showFullName;
  final bool showCity;
  final bool saved;
  final VoidCallback onUploadPhoto;
  final VoidCallback onDeletePhoto;
  final ValueChanged<bool> onShowFullNameChanged;
  final ValueChanged<bool> onShowCityChanged;
  final ValueChanged<CityOption?> onCitySelected;
  final VoidCallback onChanged;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 720;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: _ProfileSettingsTitle(saved: false)),
              if (saved) const _SavedBadge(),
            ],
          ),
          const SizedBox(height: 24),
          _ProfilePhotoSection(
            userName: userName,
            hasPhoto: hasPhoto,
            useUploadedPreview: useUploadedPreview,
            avatarUrl: avatarUrl,
            avatarBusy: avatarBusy,
            onUploadPhoto: onUploadPhoto,
            onDeletePhoto: onDeletePhoto,
          ),
          const SizedBox(height: 28),
          const _FieldGroupLabel('Основная информация'),
          const SizedBox(height: 12),
          if (isNarrow)
            Column(
              children: [
                _SettingsTextField(
                  label: 'Фамилия',
                  controller: lastNameController,
                  onChanged: onChanged,
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: 'Имя',
                  controller: firstNameController,
                  onChanged: onChanged,
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: 'Отчество',
                  controller: middleNameController,
                  onChanged: onChanged,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _SettingsTextField(
                    label: 'Фамилия',
                    controller: lastNameController,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SettingsTextField(
                    label: 'Имя',
                    controller: firstNameController,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SettingsTextField(
                    label: 'Отчество',
                    controller: middleNameController,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          CityAutocompleteField(
            controller: cityController,
            selectedOption: selectedCity,
            isRequired: true,
            labelText: 'Город',
            hintText: 'Начните вводить город',
            errorText: cityErrorText,
            onSelected: onCitySelected,
            onChanged: onChanged,
          ),
          if (isMaster) ...[
            const SizedBox(height: 14),
            _SettingsTextField(
              label: 'Студия',
              controller: studioController,
              onChanged: onChanged,
            ),
          ],
          const SizedBox(height: 14),
          _BioField(controller: bioController, onChanged: onChanged),
          const SizedBox(height: 24),
          const _FieldGroupLabel('Настройки видимости'),
          const SizedBox(height: 10),
          _VisibilityToggle(
            label: 'Показывать ФИО в профиле',
            value: showFullName,
            onChanged: onShowFullNameChanged,
          ),
          _VisibilityToggle(
            label: 'Показывать город в профиле',
            value: showCity,
            onChanged: onShowCityChanged,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSave,
              style: _profileSaveButtonStyle(),
              child: const Text('Сохранить изменения'),
            ),
          ),
        ],
      ),
    );
  }
}

ButtonStyle _profileSaveButtonStyle() {
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    backgroundColor: _accent,
    foregroundColor: Colors.white,
    disabledBackgroundColor: _profileSaveDisabled,
    disabledForegroundColor: _profileSaveDisabledText,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    elevation: 0,
  ).copyWith(
    shadowColor: const WidgetStatePropertyAll(Color(0x26000000)),
    elevation: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return 0;
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return 2;
      }
      return 1;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return _accent.withValues(alpha: 0.1);
      }
      return null;
    }),
  );
}

class _ProfileSettingsTitle extends StatelessWidget {
  const _ProfileSettingsTitle({required this.saved});

  final bool saved;

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Профиль',
          style: TextStyle(
            color: _text,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Настройте фото, имя, город и описание, которые видны в профиле.',
          style: TextStyle(color: _muted, height: 1.45),
        ),
      ],
    );
  }
}

class _ProfilePhotoSection extends StatelessWidget {
  const _ProfilePhotoSection({
    required this.userName,
    required this.hasPhoto,
    required this.useUploadedPreview,
    required this.avatarUrl,
    required this.avatarBusy,
    required this.onUploadPhoto,
    required this.onDeletePhoto,
  });

  final String userName;
  final bool hasPhoto;
  final bool useUploadedPreview;
  final String avatarUrl;
  final bool avatarBusy;
  final VoidCallback onUploadPhoto;
  final VoidCallback onDeletePhoto;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 620;
    final avatar = _ProfileAvatar(
      userName: userName,
      hasPhoto: hasPhoto,
      useUploadedPreview: useUploadedPreview,
      avatarUrl: avatarUrl,
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: avatarBusy ? null : onUploadPhoto,
          icon: const Icon(Icons.file_upload_outlined, size: 18),
          label: const Text('Загрузить фото'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _accent),
          ),
        ),
        OutlinedButton.icon(
          onPressed: avatarBusy ? null : onDeletePhoto,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Удалить фото'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB42318),
            side: const BorderSide(color: Color(0xFFF0B8B0)),
          ),
        ),
        if (avatarBusy)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(height: 14),
          actions,
          const SizedBox(height: 8),
          const _PhotoHint(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        avatar,
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [actions, const SizedBox(height: 10), const _PhotoHint()],
          ),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.userName,
    required this.hasPhoto,
    required this.useUploadedPreview,
    required this.avatarUrl,
  });

  final String userName;
  final bool hasPhoto;
  final bool useUploadedPreview;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    if (!hasPhoto) {
      return CircleAvatar(
        radius: 54,
        backgroundColor: _accent,
        child: Text(
          userName.isEmpty ? 'А' : userName.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return ClipOval(
      child: RemoteOrAssetImage(
        assetPath: useUploadedPreview
            ? AuthenticatedDashboardTheme.mariaImage
            : AuthenticatedDashboardTheme.appointmentImage,
        imageUrl: avatarUrl,
        width: 108,
        height: 108,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _PhotoHint extends StatelessWidget {
  const _PhotoHint();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Рекомендуемый размер: 400x400px, JPG, PNG до 5 МБ.',
      style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
    );
  }
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      decoration: _inputDecoration(label),
    );
  }
}

class _BioField extends StatelessWidget {
  const _BioField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      maxLines: 4,
      maxLength: 150,
      keyboardType: TextInputType.multiline,
      decoration: _inputDecoration('О себе').copyWith(
        constraints: const BoxConstraints(minHeight: 132),
        hintText: 'Расскажите немного о себе...',
        alignLabelWithHint: true,
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (next) => onChanged(next ?? false),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: _accent,
      title: Text(
        label,
        style: const TextStyle(
          color: _text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FieldGroupLabel extends StatelessWidget {
  const _FieldGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _text,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _SavedBadge extends StatelessWidget {
  const _SavedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Сохранено',
        style: TextStyle(
          color: _accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _ScheduleIntervalType { work, breakTime }

class _ScheduleInterval {
  const _ScheduleInterval({
    required this.id,
    required this.type,
    required this.startMinute,
    required this.endMinute,
  });

  final String id;
  final _ScheduleIntervalType type;
  final int startMinute;
  final int endMinute;

  _ScheduleInterval copyWith({
    _ScheduleIntervalType? type,
    int? startMinute,
    int? endMinute,
  }) {
    return _ScheduleInterval(
      id: id,
      type: type ?? this.type,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
    );
  }
}

class _ScheduleEditorResult {
  const _ScheduleEditorResult.save(this.interval) : delete = false;
  const _ScheduleEditorResult.delete() : interval = null, delete = true;

  final _ScheduleInterval? interval;
  final bool delete;
}

class _WorkScheduleSettingsScreen extends StatefulWidget {
  const _WorkScheduleSettingsScreen({
    required this.api,
    required this.sessionToken,
  });

  final InkConnectApiClient? api;
  final String? sessionToken;

  @override
  State<_WorkScheduleSettingsScreen> createState() =>
      _WorkScheduleSettingsScreenState();
}

class _WorkScheduleSettingsScreenState
    extends State<_WorkScheduleSettingsScreen> {
  static const _workColor = Color(0xFFE2F1E6);
  static const _workBorder = Color(0xFFB7D9C0);
  static const _breakColor = Color(0xFFFFF3D8);
  static const _breakBorder = Color(0xFFFFCF74);

  static const _days = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  late final Map<int, bool> _enabled = {
    for (var index = 0; index < _days.length; index++) index: index == 0,
  };

  late final Map<int, List<_ScheduleInterval>> _intervals = {
    0: _defaultDay('mon', includeEvening: true),
    1: const <_ScheduleInterval>[],
    2: const <_ScheduleInterval>[],
    3: const <_ScheduleInterval>[],
    4: const <_ScheduleInterval>[],
    5: const <_ScheduleInterval>[],
    6: const <_ScheduleInterval>[],
  };
  String? _loadedScheduleToken;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  @override
  void didUpdateWidget(covariant _WorkScheduleSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionToken != widget.sessionToken) {
      _loadedScheduleToken = null;
      _loadSchedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(22),
            child: _ScheduleHeaderText(),
          ),
          const Divider(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ScheduleLegend(),
                const SizedBox(height: 18),
                for (var index = 0; index < _days.length; index++) ...[
                  _ScheduleDayRow(
                    dayIndex: index,
                    day: _days[index],
                    enabled: _enabled[index] ?? false,
                    intervals: _sortedIntervals(index),
                    onToggle: (value) {
                      setState(() {
                        _enabled[index] = value;
                        if (!value) {
                          _intervals[index] = <_ScheduleInterval>[];
                        }
                        _saved = false;
                      });
                    },
                    onAdd: () => _openIntervalEditor(index),
                    onEdit: (interval) =>
                        _openIntervalEditor(index, interval: interval),
                    onCopy: () => _copyDaySchedule(index),
                    onClear: () => _clearDayIntervals(index),
                    onDayOff: () => _makeDayOff(index),
                  ),
                  if (index != _days.length - 1) const SizedBox(height: 14),
                ],
                const SizedBox(height: 20),
                const _ScheduleInfoBlock(),
                const SizedBox(height: 18),
                if (_saved) ...[
                  const Text(
                    'График сохранён',
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveSchedule,
                    child: const Text('Сохранить изменения'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_ScheduleInterval> _sortedIntervals(int dayIndex) {
    final items = [...(_intervals[dayIndex] ?? const <_ScheduleInterval>[])];
    items.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return items;
  }

  Future<void> _loadSchedule() async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      return;
    }
    if (_loadedScheduleToken == token) {
      return;
    }
    _loadedScheduleToken = token;

    try {
      final schedule = await api.currentMasterSchedule(token);
      if (!mounted) {
        return;
      }
      _applySchedule(schedule, saved: true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _saved = false);
    }
  }

  Future<void> _saveSchedule() async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      setState(() => _saved = true);
      _showMessage('График сохранён');
      return;
    }

    try {
      final schedule = await api.updateMasterSchedule(
        sessionToken: token,
        payload: _schedulePayload(),
      );
      if (!mounted) {
        return;
      }
      _applySchedule(schedule, saved: true);
      _showMessage('График сохранён');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _saved = false);
      _showMessage(
        'Не удалось сохранить график. Локальные изменения не потеряны.',
      );
    }
  }

  void _applySchedule(MasterSchedule schedule, {required bool saved}) {
    setState(() {
      for (var index = 0; index < _days.length; index++) {
        _enabled[index] = false;
        _intervals[index] = <_ScheduleInterval>[];
      }

      for (final day in schedule.days) {
        if (day.dayIndex < 0 || day.dayIndex >= _days.length) {
          continue;
        }
        _enabled[day.dayIndex] = day.enabled;
        _intervals[day.dayIndex] = day.enabled
            ? [
                for (
                  var intervalIndex = 0;
                  intervalIndex < day.intervals.length;
                  intervalIndex++
                )
                  _scheduleIntervalFromModel(
                    day.intervals[intervalIndex],
                    day.dayIndex,
                    intervalIndex,
                  ),
              ]
            : [];
      }
      _saved = saved;
    });
  }

  MasterSchedule _schedulePayload() {
    return MasterSchedule(
      days: [
        for (var index = 0; index < _days.length; index++)
          MasterScheduleDay(
            dayIndex: index,
            enabled: _enabled[index] ?? false,
            intervals: (_enabled[index] ?? false)
                ? _sortedIntervals(index).map(_scheduleIntervalToModel).toList()
                : const <MasterScheduleInterval>[],
          ),
      ],
    );
  }

  _ScheduleInterval _scheduleIntervalFromModel(
    MasterScheduleInterval interval,
    int dayIndex,
    int intervalIndex,
  ) {
    return _ScheduleInterval(
      id: 'backend-$dayIndex-$intervalIndex',
      type: interval.type == 'break'
          ? _ScheduleIntervalType.breakTime
          : _ScheduleIntervalType.work,
      startMinute: interval.startMinute,
      endMinute: interval.endMinute,
    );
  }

  MasterScheduleInterval _scheduleIntervalToModel(_ScheduleInterval interval) {
    return MasterScheduleInterval(
      type: interval.type == _ScheduleIntervalType.breakTime ? 'break' : 'work',
      startMinute: interval.startMinute,
      endMinute: interval.endMinute,
    );
  }

  Future<void> _openIntervalEditor(
    int dayIndex, {
    _ScheduleInterval? interval,
  }) async {
    final isMobile = MediaQuery.sizeOf(context).width < 620;
    final result = isMobile
        ? await showModalBottomSheet<_ScheduleEditorResult>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (sheetContext) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: _ScheduleIntervalEditor(
                  dayName: _days[dayIndex],
                  interval: interval,
                  validate: (candidate) => _validateInterval(
                    dayIndex,
                    candidate,
                    editingId: interval?.id,
                  ),
                ),
              );
            },
          )
        : await showDialog<_ScheduleEditorResult>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _ScheduleIntervalEditor(
                  dayName: _days[dayIndex],
                  interval: interval,
                  validate: (candidate) => _validateInterval(
                    dayIndex,
                    candidate,
                    editingId: interval?.id,
                  ),
                ),
              ),
            ),
          );

    if (result == null) {
      return;
    }
    if (result.delete) {
      setState(() {
        _intervals[dayIndex] = _sortedIntervals(
          dayIndex,
        ).where((item) => item.id != interval?.id).toList();
        _saved = false;
      });
      _showMessage('Интервал удалён');
      return;
    }
    final next = result.interval;
    if (next == null) {
      return;
    }
    setState(() {
      final withoutCurrent = _sortedIntervals(
        dayIndex,
      ).where((item) => item.id != next.id).toList();
      _intervals[dayIndex] = [...withoutCurrent, next]
        ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
      _enabled[dayIndex] = true;
      _saved = false;
    });
    _showMessage(interval == null ? 'Интервал добавлен' : 'Интервал обновлён');
  }

  Future<void> _copyDaySchedule(int dayIndex) async {
    final targetDays = await showDialog<List<int>>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _CopyScheduleDialog(sourceDayIndex: dayIndex, days: _days),
        ),
      ),
    );

    if (targetDays == null || targetDays.isEmpty) {
      return;
    }

    final source = _sortedIntervals(dayIndex);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    setState(() {
      for (final target in targetDays) {
        _intervals[target] = [
          for (var index = 0; index < source.length; index++)
            _ScheduleInterval(
              id: 'copy-$target-$stamp-$index',
              type: source[index].type,
              startMinute: source[index].startMinute,
              endMinute: source[index].endMinute,
            ),
        ];
        _enabled[target] = source.isNotEmpty;
      }
      _saved = false;
    });
    _showMessage('График дня скопирован');
  }

  void _clearDayIntervals(int dayIndex) {
    setState(() {
      _enabled[dayIndex] = true;
      _intervals[dayIndex] = <_ScheduleInterval>[];
      _saved = false;
    });
    _showMessage('Интервалы очищены');
  }

  void _makeDayOff(int dayIndex) {
    setState(() {
      _enabled[dayIndex] = false;
      _intervals[dayIndex] = <_ScheduleInterval>[];
      _saved = false;
    });
    _showMessage('День отмечен выходным');
  }

  String? _validateInterval(
    int dayIndex,
    _ScheduleInterval candidate, {
    String? editingId,
  }) {
    if (candidate.startMinute < 0 ||
        candidate.endMinute > 1440 ||
        candidate.endMinute <= candidate.startMinute) {
      return 'Время окончания должно быть позже времени начала';
    }

    final others = _sortedIntervals(
      dayIndex,
    ).where((item) => item.id != editingId).toList();
    final hasOverlap = others.any(
      (item) =>
          candidate.startMinute < item.endMinute &&
          candidate.endMinute > item.startMinute,
    );
    if (hasOverlap) {
      return 'Интервалы не должны пересекаться';
    }

    if (candidate.type == _ScheduleIntervalType.breakTime) {
      final nearWork = others.any(
        (item) =>
            item.type == _ScheduleIntervalType.work &&
            (item.endMinute == candidate.startMinute ||
                item.startMinute == candidate.endMinute),
      );
      if (!nearWork) {
        return 'Перерыв должен быть рядом с рабочим интервалом';
      }
    }

    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  static List<_ScheduleInterval> _defaultDay(
    String prefix, {
    bool includeEvening = false,
  }) {
    return [
      _work('$prefix-1', 9, 0, 13, 0),
      _break('$prefix-2', 13, 0, 14, 0),
      _work('$prefix-3', 14, 0, 16, 0),
      if (includeEvening) _work('$prefix-4', 18, 0, 20, 0),
    ];
  }

  static _ScheduleInterval _work(
    String id,
    int startHour,
    int startMinute,
    int endHour,
    int endMinute,
  ) {
    return _ScheduleInterval(
      id: id,
      type: _ScheduleIntervalType.work,
      startMinute: _minutes(startHour, startMinute),
      endMinute: _minutes(endHour, endMinute),
    );
  }

  static _ScheduleInterval _break(
    String id,
    int startHour,
    int startMinute,
    int endHour,
    int endMinute,
  ) {
    return _ScheduleInterval(
      id: id,
      type: _ScheduleIntervalType.breakTime,
      startMinute: _minutes(startHour, startMinute),
      endMinute: _minutes(endHour, endMinute),
    );
  }

  static int _minutes(int hour, int minute) => hour * 60 + minute;
}

class _ScheduleHeaderText extends StatelessWidget {
  const _ScheduleHeaderText();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'График работы',
          style: TextStyle(
            color: _text,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Укажите интервалы, когда вы доступны для записи. Всё остальное время автоматически считается недоступным.',
          style: TextStyle(color: _muted, height: 1.45),
        ),
      ],
    );
  }
}

class _ScheduleLegend extends StatelessWidget {
  const _ScheduleLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 22,
      runSpacing: 10,
      children: [
        _LegendItem(
          color: _WorkScheduleSettingsScreenState._workColor,
          border: _WorkScheduleSettingsScreenState._workBorder,
          label: 'Рабочее время',
        ),
        _LegendItem(
          color: _WorkScheduleSettingsScreenState._breakColor,
          border: _WorkScheduleSettingsScreenState._breakBorder,
          label: 'Перерыв',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.border,
    required this.label,
  });

  final Color color;
  final Color border;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          label,
          style: const TextStyle(color: _text, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

enum _DayScheduleAction { copy, clear, dayOff }

class _ScheduleDayRow extends StatelessWidget {
  const _ScheduleDayRow({
    required this.dayIndex,
    required this.day,
    required this.enabled,
    required this.intervals,
    required this.onToggle,
    required this.onAdd,
    required this.onEdit,
    required this.onCopy,
    required this.onClear,
    required this.onDayOff,
  });

  final int dayIndex;
  final String day;
  final bool enabled;
  final List<_ScheduleInterval> intervals;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAdd;
  final ValueChanged<_ScheduleInterval> onEdit;
  final VoidCallback onCopy;
  final VoidCallback onClear;
  final VoidCallback onDayOff;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>('schedule-day-$dayIndex'),
        initiallyExpanded: dayIndex == 0,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: Switch(
          value: enabled,
          activeColor: _accent,
          onChanged: onToggle,
        ),
        title: Text(
          day,
          style: const TextStyle(
            color: _text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: enabled
            ? Text(
                intervals.isEmpty
                    ? 'Интервалы пока не добавлены'
                    : '${intervals.length} ${_intervalCountLabel(intervals.length)}',
                style: const TextStyle(color: _muted),
              )
            : const Text('Выходной'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DayScheduleMenu(
              onCopy: onCopy,
              onClear: onClear,
              onDayOff: onDayOff,
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              color: _accent,
              tooltip: 'Добавить интервал',
            ),
          ],
        ),
        children: [
          if (enabled) ...[
            if (intervals.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Интервалы пока не добавлены',
                  style: TextStyle(color: _muted),
                ),
              )
            else
              for (final interval in intervals) ...[
                _ScheduleIntervalTile(
                  interval: interval,
                  onTap: () => onEdit(interval),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить интервал'),
              ),
            ),
          ] else
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'В этот день онлайн-запись недоступна.',
                style: TextStyle(color: _muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayScheduleMenu extends StatelessWidget {
  const _DayScheduleMenu({
    required this.onCopy,
    required this.onClear,
    required this.onDayOff,
  });

  final VoidCallback onCopy;
  final VoidCallback onClear;
  final VoidCallback onDayOff;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DayScheduleAction>(
      tooltip: 'Действия с днём',
      icon: const Icon(Icons.more_vert_rounded),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (action) {
        switch (action) {
          case _DayScheduleAction.copy:
            onCopy();
            break;
          case _DayScheduleAction.clear:
            onClear();
            break;
          case _DayScheduleAction.dayOff:
            onDayOff();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _DayScheduleAction.copy,
          child: _ScheduleMenuItem(
            icon: Icons.copy_rounded,
            label: 'Скопировать график дня',
          ),
        ),
        PopupMenuItem(
          value: _DayScheduleAction.clear,
          child: _ScheduleMenuItem(
            icon: Icons.event_busy_outlined,
            label: 'Очистить интервалы',
          ),
        ),
        PopupMenuItem(
          value: _DayScheduleAction.dayOff,
          child: _ScheduleMenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Сделать выходным',
            danger: true,
          ),
        ),
      ],
    );
  }
}

class _ScheduleMenuItem extends StatelessWidget {
  const _ScheduleMenuItem({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? SecuritySettingsScreen._danger : _text;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ScheduleIntervalTile extends StatelessWidget {
  const _ScheduleIntervalTile({required this.interval, required this.onTap});

  final _ScheduleInterval interval;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBreak = interval.type == _ScheduleIntervalType.breakTime;
    final color = isBreak
        ? _WorkScheduleSettingsScreenState._breakColor
        : _WorkScheduleSettingsScreenState._workColor;
    final border = isBreak
        ? _WorkScheduleSettingsScreenState._breakBorder
        : _WorkScheduleSettingsScreenState._workBorder;
    final textColor = isBreak ? const Color(0xFF8A4F00) : _accent;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(
                isBreak
                    ? Icons.local_cafe_outlined
                    : Icons.work_outline_rounded,
                color: textColor,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${isBreak ? 'Перерыв' : 'Работа'} • ${_formatTime(interval.startMinute)}–${_formatTime(interval.endMinute)}',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.edit_outlined, size: 18, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyScheduleDialog extends StatefulWidget {
  const _CopyScheduleDialog({required this.sourceDayIndex, required this.days});

  final int sourceDayIndex;
  final List<String> days;

  @override
  State<_CopyScheduleDialog> createState() => _CopyScheduleDialogState();
}

class _CopyScheduleDialogState extends State<_CopyScheduleDialog> {
  late final Set<int> _selected;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _selected = {
      for (var index = 0; index < widget.days.length; index++)
        if (index != widget.sourceDayIndex && index < 5) index,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Скопировать график дня',
                  style: TextStyle(
                    color: _text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Выберите дни, куда применить текущие интервалы.',
            style: TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: Column(
              children: [
                for (var index = 0; index < widget.days.length; index++)
                  if (index != widget.sourceDayIndex)
                    CheckboxListTile(
                      value: _selected.contains(index),
                      activeColor: _accent,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        widget.days[index],
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          if (value ?? false) {
                            _selected.add(index);
                          } else {
                            _selected.remove(index);
                          }
                          _showError = false;
                        });
                      },
                    ),
              ],
            ),
          ),
          if (_showError) ...[
            const SizedBox(height: 10),
            const Text(
              'Выберите хотя бы один день',
              style: TextStyle(
                color: SecuritySettingsScreen._danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (_selected.isEmpty) {
                      setState(() => _showError = true);
                      return;
                    }
                    Navigator.of(context).pop(_selected.toList()..sort());
                  },
                  child: const Text('Применить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleIntervalEditor extends StatefulWidget {
  const _ScheduleIntervalEditor({
    required this.dayName,
    required this.interval,
    required this.validate,
  });

  final String dayName;
  final _ScheduleInterval? interval;
  final String? Function(_ScheduleInterval interval) validate;

  @override
  State<_ScheduleIntervalEditor> createState() =>
      _ScheduleIntervalEditorState();
}

class _ScheduleIntervalEditorState extends State<_ScheduleIntervalEditor> {
  late _ScheduleIntervalType _type =
      widget.interval?.type ?? _ScheduleIntervalType.work;
  late int _start = widget.interval?.startMinute ?? 540;
  late int _end = widget.interval?.endMinute ?? 600;
  String? _error;

  bool get _isEditing => widget.interval != null;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? 'Редактировать интервал' : 'Добавить интервал',
            style: const TextStyle(
              color: _text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(widget.dayName, style: const TextStyle(color: _muted)),
          const SizedBox(height: 20),
          DropdownButtonFormField<_ScheduleIntervalType>(
            value: _type,
            decoration: _inputDecoration('Тип интервала'),
            items: const [
              DropdownMenuItem(
                value: _ScheduleIntervalType.work,
                child: Text('Работа'),
              ),
              DropdownMenuItem(
                value: _ScheduleIntervalType.breakTime,
                child: Text('Перерыв'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _type = value;
                _error = null;
              });
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _start,
                  isExpanded: true,
                  decoration: _inputDecoration('Начало'),
                  items: _timeItems(includeEndOfDay: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _start = value;
                      if (_end <= _start) {
                        _end = (_start + 60).clamp(30, 1440).toInt();
                      }
                      _error = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _end,
                  isExpanded: true,
                  decoration: _inputDecoration('Окончание'),
                  items: _timeItems(includeEndOfDay: true, skipZero: true),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _end = value;
                      _error = null;
                    });
                  },
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: SecuritySettingsScreen._danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              if (_isEditing)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(const _ScheduleEditorResult.delete()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SecuritySettingsScreen._danger,
                      side: const BorderSide(
                        color: SecuritySettingsScreen._dangerLine,
                      ),
                    ),
                    child: const Text('Удалить'),
                  ),
                ),
              if (_isEditing) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<int>> _timeItems({
    required bool includeEndOfDay,
    bool skipZero = false,
  }) {
    final max = includeEndOfDay ? 1440 : 1410;
    return [
      for (var minute = skipZero ? 30 : 0; minute <= max; minute += 30)
        DropdownMenuItem(value: minute, child: Text(_formatTime(minute))),
    ];
  }

  void _save() {
    final interval = _ScheduleInterval(
      id:
          widget.interval?.id ??
          'local-${DateTime.now().microsecondsSinceEpoch}',
      type: _type,
      startMinute: _start,
      endMinute: _end,
    );
    final error = widget.validate(interval);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_ScheduleEditorResult.save(interval));
  }
}

class _ScheduleInfoBlock extends StatelessWidget {
  const _ScheduleInfoBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _accent, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Время вне указанных интервалов недоступно для записи. Клиенты не смогут выбрать это время при онлайн-записи.',
              style: TextStyle(
                color: _text,
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({
    super.key,
    required this.user,
    required this.onLogout,
    this.api,
    this.sessionToken,
  });

  final AuthUser? user;
  final Future<void> Function() onLogout;
  final InkConnectApiClient? api;
  final String? sessionToken;

  static const _danger = Color(0xFFB42318);
  static const _dangerLine = Color(0xFFF0B8B0);
  static const _dangerSoft = Color(0xFFFFF4F2);

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  SecurityContact? _contact;
  String? _loadedContactToken;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  @override
  void didUpdateWidget(covariant SecuritySettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.user?.email != widget.user?.email) {
      _loadedContactToken = null;
      _loadContact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = (_contact?.email.isNotEmpty ?? false)
        ? _contact!.email
        : ((widget.user?.email.isNotEmpty ?? false)
              ? widget.user!.email
              : 'Email не загружен');
    final phone = _formatSecurityPhone(_contact?.phone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Безопасность',
          style: TextStyle(
            color: _text,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Управляйте безопасностью аккаунта и личными данными',
          style: TextStyle(color: _muted, height: 1.45),
        ),
        const SizedBox(height: 24),
        _SecurityActionCard(
          title: 'Пароль',
          description:
              'Используйте сложный пароль и не передавайте его другим людям.',
          action: OutlinedButton(
            onPressed: () => _openPasswordModal(context),
            child: const Text('Изменить пароль'),
          ),
        ),
        const SizedBox(height: 14),
        _SecurityActionCard(
          title: 'Email',
          description: email,
          status: const _VerifiedBadge(label: 'Подтверждён'),
          action: OutlinedButton(
            onPressed: () => _openEmailModal(context, email),
            child: const Text('Изменить'),
          ),
        ),
        const SizedBox(height: 14),
        _SecurityActionCard(
          title: 'Номер телефона',
          description: phone,
          status: (_contact?.phone.isNotEmpty ?? false)
              ? const _VerifiedBadge(label: 'Подтверждён')
              : null,
          action: OutlinedButton(
            onPressed: () => _openPhoneModal(context, _contact?.phone ?? ''),
            child: const Text('Изменить'),
          ),
        ),
        const SizedBox(height: 14),
        _SecurityActionCard(
          title: 'Выйти из аккаунта',
          description: 'Вы выйдете из аккаунта на текущем устройстве.',
          action: OutlinedButton(
            onPressed: () => _logout(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: SecuritySettingsScreen._danger,
              side: const BorderSide(color: SecuritySettingsScreen._dangerLine),
            ),
            child: const Text('Выйти'),
          ),
        ),
        const SizedBox(height: 16),
        _DangerZoneCard(onDelete: () => _confirmDelete(context)),
      ],
    );
  }

  Future<void> _openPasswordModal(BuildContext context) async {
    final isMobile = MediaQuery.sizeOf(context).width < 620;
    final changed = isMobile
        ? await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (sheetContext) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: _PasswordChangeForm(
                  isBottomSheet: true,
                  onSubmit: _changePassword,
                ),
              );
            },
          )
        : await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _PasswordChangeDialog(onSubmit: _changePassword),
          );

    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пароль изменён'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openEmailModal(
    BuildContext context,
    String currentEmail,
  ) async {
    final updated = await _showSecurityContactSheet(
      context: context,
      title: 'Изменение email',
      valueLabel: 'Новый email',
      initialValue: currentEmail == 'Email не загружен' ? '' : currentEmail,
      keyboardType: TextInputType.emailAddress,
      valueType: _SecurityContactValueType.email,
      helperText: 'Для изменения email подтвердите действие текущим паролем.',
      submit: _updateEmail,
    );

    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email изменён'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openPhoneModal(
    BuildContext context,
    String currentPhone,
  ) async {
    final updated = await _showSecurityContactSheet(
      context: context,
      title: 'Изменение номера телефона',
      valueLabel: 'Новый номер телефона',
      initialValue: currentPhone,
      keyboardType: TextInputType.phone,
      valueType: _SecurityContactValueType.phone,
      helperText: 'Телефон хранится приватно и не показывается публично.',
      submit: _updatePhone,
    );

    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Телефон изменён'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Вы вышли из аккаунта'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await widget.onLogout();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Удалить аккаунт?'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Вы уверены, что хотите удалить аккаунт безвозвратно?'),
              SizedBox(height: 10),
              Text(
                'Это действие нельзя отменить. Ваш профиль и связанные данные могут быть удалены.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: SecuritySettingsScreen._danger,
                foregroundColor: Colors.white,
              ),
              child: const Text('Удалить аккаунт'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final deleted = await _showAccountDeleteSheet(context);
    if (deleted != true || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Аккаунт удалён'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await widget.onLogout();
  }

  Future<void> _changePassword(PasswordChangePayload payload) async {
    final client = widget.api;
    final token = widget.sessionToken;
    if (client == null || token == null || token.isEmpty) {
      throw const ApiException('Смена пароля доступна после входа в аккаунт.');
    }

    await client.changePassword(sessionToken: token, payload: payload);
  }

  Future<void> _loadContact() async {
    final client = widget.api;
    final token = widget.sessionToken;
    if (client == null || token == null || token.isEmpty) {
      return;
    }
    if (_loadedContactToken == token) {
      return;
    }
    _loadedContactToken = token;

    try {
      final contact = await client.securityContact(token);
      if (!mounted) return;
      setState(() => _contact = contact);
    } catch (_) {
      if (!mounted) return;
      setState(() => _contact = null);
    }
  }

  Future<void> _updateEmail(String value, String currentPassword) async {
    final client = widget.api;
    final token = widget.sessionToken;
    if (client == null || token == null || token.isEmpty) {
      throw const ApiException(
        'Изменение email доступно после входа в аккаунт.',
      );
    }

    final email = validators.normalizeEmail(value.trim());
    if (!validators.isValidEmail(email)) {
      throw const ApiException('Введите корректный email в латинице.');
    }

    final contact = await client.updateSecurityEmail(
      sessionToken: token,
      payload: EmailUpdatePayload(
        currentPassword: currentPassword,
        email: email,
      ),
    );
    if (mounted) {
      setState(() => _contact = contact);
    }
  }

  Future<void> _updatePhone(String value, String currentPassword) async {
    final client = widget.api;
    final token = widget.sessionToken;
    if (client == null || token == null || token.isEmpty) {
      throw const ApiException(
        'Изменение телефона доступно после входа в аккаунт.',
      );
    }

    final digits = validators.normalizePhoneDigits(value);
    if (digits.length != 10) {
      throw const ApiException('Телефон должен содержать 10 цифр после +7.');
    }

    final contact = await client.updateSecurityPhone(
      sessionToken: token,
      payload: PhoneUpdatePayload(
        currentPassword: currentPassword,
        phone: '+7$digits',
      ),
    );
    if (mounted) {
      setState(() => _contact = contact);
    }
  }

  Future<void> _deleteAccount(String currentPassword) async {
    final client = widget.api;
    final token = widget.sessionToken;
    if (client == null || token == null || token.isEmpty) {
      throw const ApiException(
        'Удаление аккаунта доступно после входа в аккаунт.',
      );
    }

    await client.deleteAccount(
      sessionToken: token,
      payload: AccountDeletePayload(currentPassword: currentPassword),
    );
  }

  String _formatSecurityPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return 'Телефон не загружен';
    }
    return '+7 ${validators.formatPhone(phone)}';
  }

  Future<bool?> _showSecurityContactSheet({
    required BuildContext context,
    required String title,
    required String valueLabel,
    required String initialValue,
    required TextInputType keyboardType,
    required _SecurityContactValueType valueType,
    required String helperText,
    required Future<void> Function(String value, String currentPassword) submit,
  }) async {
    final isMobile = MediaQuery.sizeOf(context).width < 620;
    if (isMobile) {
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: _SecurityContactForm(
              title: title,
              valueLabel: valueLabel,
              initialValue: initialValue,
              keyboardType: keyboardType,
              valueType: valueType,
              helperText: helperText,
              submit: submit,
              isBottomSheet: true,
            ),
          );
        },
      );
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: _SecurityContactForm(
            title: title,
            valueLabel: valueLabel,
            initialValue: initialValue,
            keyboardType: keyboardType,
            valueType: valueType,
            helperText: helperText,
            submit: submit,
          ),
        ),
      ),
    );
  }

  Future<bool?> _showAccountDeleteSheet(BuildContext context) async {
    final isMobile = MediaQuery.sizeOf(context).width < 620;
    if (isMobile) {
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: _AccountDeleteForm(
              onSubmit: _deleteAccount,
              isBottomSheet: true,
            ),
          );
        },
      );
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: _AccountDeleteForm(onSubmit: _deleteAccount),
        ),
      ),
    );
  }
}

enum _SecurityContactValueType { email, phone }

class _SecurityContactForm extends StatefulWidget {
  const _SecurityContactForm({
    required this.title,
    required this.valueLabel,
    required this.initialValue,
    required this.keyboardType,
    required this.valueType,
    required this.helperText,
    required this.submit,
    this.isBottomSheet = false,
  });

  final String title;
  final String valueLabel;
  final String initialValue;
  final TextInputType keyboardType;
  final _SecurityContactValueType valueType;
  final String helperText;
  final Future<void> Function(String value, String currentPassword) submit;
  final bool isBottomSheet;

  @override
  State<_SecurityContactForm> createState() => _SecurityContactFormState();
}

class _SecurityContactFormState extends State<_SecurityContactForm> {
  late final TextEditingController _valueController;
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _saving = false;
  String? _valueError;
  String? _passwordError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: _initialValueText());
  }

  @override
  void dispose() {
    _valueController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, widget.isBottomSheet ? 28 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _valueController,
            keyboardType: widget.keyboardType,
            onChanged: _handleValueChanged,
            decoration: _inputDecoration(widget.valueLabel).copyWith(
              errorText: _valueError,
              prefixText: widget.valueType == _SecurityContactValueType.phone
                  ? '+7 '
                  : null,
              hintText: widget.valueType == _SecurityContactValueType.phone
                  ? '(___) ___-__-__'
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          _PasswordField(
            label: 'Текущий пароль',
            controller: _passwordController,
            visible: _showPassword,
            errorText: _passwordError,
            onToggle: () => setState(() => _showPassword = !_showPassword),
            onChanged: _clearErrors,
          ),
          const SizedBox(height: 10),
          Text(
            widget.helperText,
            style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(
              _formError!,
              style: const TextStyle(
                color: SecuritySettingsScreen._danger,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initialValueText() {
    if (widget.valueType == _SecurityContactValueType.phone) {
      return validators.formatPhone(widget.initialValue);
    }
    return validators.normalizeEmail(widget.initialValue.trim());
  }

  void _handleValueChanged(String value) {
    if (widget.valueType == _SecurityContactValueType.email) {
      final normalized = validators.normalizeEmail(value);
      if (normalized != value) {
        _valueController.value = TextEditingValue(
          text: normalized,
          selection: TextSelection.collapsed(offset: normalized.length),
        );
      }
    } else {
      final formatted = validators.formatPhone(value);
      if (formatted != value) {
        _valueController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }

    _clearErrors(value);
  }

  String? _validateValue(String value) {
    if (widget.valueType == _SecurityContactValueType.email) {
      final email = validators.normalizeEmail(value.trim());
      if (!validators.isValidEmail(email)) {
        return 'Введите корректный email в латинице.';
      }
      return null;
    }

    if (validators.normalizePhoneDigits(value).length != 10) {
      return 'Введите полный номер: после +7 нужно 10 цифр.';
    }
    return null;
  }

  void _clearErrors(String _) {
    if (_valueError == null && _passwordError == null && _formError == null) {
      return;
    }
    setState(() {
      _valueError = null;
      _passwordError = null;
      _formError = null;
    });
  }

  Future<void> _save() async {
    final rawValue = _valueController.text.trim();
    final value = widget.valueType == _SecurityContactValueType.email
        ? validators.normalizeEmail(rawValue)
        : rawValue;
    final password = _passwordController.text;
    String? valueError = _validateValue(rawValue);
    String? passwordError;

    if (password.trim().isEmpty) {
      passwordError = 'Введите текущий пароль';
    }

    if (valueError != null || passwordError != null) {
      setState(() {
        _valueError = valueError;
        _passwordError = passwordError;
      });
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      await widget.submit(value, password);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = error.message.trim().isEmpty
            ? 'Не удалось сохранить изменения.'
            : error.message.trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'Не удалось сохранить изменения. Попробуйте ещё раз.';
      });
    }
  }
}

class _AccountDeleteForm extends StatefulWidget {
  const _AccountDeleteForm({
    required this.onSubmit,
    this.isBottomSheet = false,
  });

  final Future<void> Function(String currentPassword) onSubmit;
  final bool isBottomSheet;

  @override
  State<_AccountDeleteForm> createState() => _AccountDeleteFormState();
}

class _AccountDeleteFormState extends State<_AccountDeleteForm> {
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _saving = false;
  String? _passwordError;
  String? _formError;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, widget.isBottomSheet ? 28 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Подтверждение удаления',
                  style: TextStyle(
                    color: _text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Введите текущий пароль, чтобы удалить аккаунт. Это действие нельзя отменить.',
            style: TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          _PasswordField(
            label: 'Текущий пароль',
            controller: _passwordController,
            visible: _showPassword,
            errorText: _passwordError,
            onToggle: () => setState(() => _showPassword = !_showPassword),
            onChanged: _clearErrors,
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(
              _formError!,
              style: const TextStyle(
                color: SecuritySettingsScreen._danger,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _delete(),
                  style: FilledButton.styleFrom(
                    backgroundColor: SecuritySettingsScreen._danger,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Удалить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _clearErrors(String _) {
    if (_passwordError == null && _formError == null) {
      return;
    }
    setState(() {
      _passwordError = null;
      _formError = null;
    });
  }

  Future<void> _delete() async {
    final password = _passwordController.text;
    if (password.trim().isEmpty) {
      setState(() => _passwordError = 'Введите текущий пароль');
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      await widget.onSubmit(password);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = error.message.trim().isEmpty
            ? 'Не удалось удалить аккаунт.'
            : error.message.trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'Не удалось удалить аккаунт. Попробуйте ещё раз.';
      });
    }
  }
}

class _SecurityActionCard extends StatelessWidget {
  const _SecurityActionCard({
    required this.title,
    required this.description,
    required this.action,
    this.status,
  });

  final String title;
  final String description;
  final Widget action;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 620;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              description,
              style: const TextStyle(color: _text, fontSize: 14, height: 1.35),
            ),
            if (status != null) status!,
          ],
        ),
      ],
    );

    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: action),
              ],
            )
          : Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 18),
                action,
              ],
            ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.check_circle_rounded, color: _accent, size: 14),
        ],
      ),
    );
  }
}

class _DangerZoneCard extends StatelessWidget {
  const _DangerZoneCard({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 620;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Удаление аккаунта',
          style: TextStyle(
            color: SecuritySettingsScreen._danger,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Удаление аккаунта приведёт к потере доступа к вашему профилю и всем данным. Это действие нельзя отменить.',
          style: TextStyle(color: _text, fontSize: 14, height: 1.45),
        ),
      ],
    );

    final button = OutlinedButton(
      onPressed: onDelete,
      style: OutlinedButton.styleFrom(
        foregroundColor: SecuritySettingsScreen._danger,
        side: const BorderSide(color: SecuritySettingsScreen._dangerLine),
        backgroundColor: Colors.white,
      ),
      child: const Text('Удалить аккаунт'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SecuritySettingsScreen._dangerSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SecuritySettingsScreen._dangerLine),
      ),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: button),
              ],
            )
          : Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 18),
                button,
              ],
            ),
    );
  }
}

class _PasswordChangeDialog extends StatelessWidget {
  const _PasswordChangeDialog({required this.onSubmit});

  final Future<void> Function(PasswordChangePayload payload) onSubmit;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: _PasswordChangeForm(onSubmit: onSubmit),
      ),
    );
  }
}

class _PasswordChangeForm extends StatefulWidget {
  const _PasswordChangeForm({
    required this.onSubmit,
    this.isBottomSheet = false,
  });

  final Future<void> Function(PasswordChangePayload payload) onSubmit;
  final bool isBottomSheet;

  @override
  State<_PasswordChangeForm> createState() => _PasswordChangeFormState();
}

class _PasswordChangeFormState extends State<_PasswordChangeForm> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _saving = false;
  String? _currentError;
  String? _newError;
  String? _confirmError;
  String? _formError;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, widget.isBottomSheet ? 28 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Изменение пароля',
                  style: TextStyle(
                    color: _text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PasswordField(
            label: 'Текущий пароль',
            controller: _currentController,
            visible: _showCurrent,
            errorText: _currentError,
            onToggle: () => setState(() => _showCurrent = !_showCurrent),
            onChanged: _clearErrors,
          ),
          const SizedBox(height: 14),
          _PasswordField(
            label: 'Новый пароль',
            controller: _newController,
            visible: _showNew,
            errorText: _newError,
            onToggle: () => setState(() => _showNew = !_showNew),
            onChanged: _clearErrors,
          ),
          const SizedBox(height: 14),
          _PasswordField(
            label: 'Подтвердите новый пароль',
            controller: _confirmController,
            visible: _showConfirm,
            errorText: _confirmError,
            onToggle: () => setState(() => _showConfirm = !_showConfirm),
            onChanged: _clearErrors,
          ),
          const SizedBox(height: 10),
          const Text(
            'Пароль: минимум 10 символов, буквы, цифры и спецсимвол, без пробелов в начале и конце.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(
              _formError!,
              style: const TextStyle(
                color: SecuritySettingsScreen._danger,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _clearErrors(String _) {
    if (_currentError == null &&
        _newError == null &&
        _confirmError == null &&
        _formError == null) {
      return;
    }
    setState(() {
      _currentError = null;
      _newError = null;
      _confirmError = null;
      _formError = null;
    });
  }

  Future<void> _save() async {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;
    String? currentError;
    String? newError;
    String? confirmError;

    if (current.trim().isEmpty) {
      currentError = 'Введите текущий пароль';
    }
    if (!validators.isValidPassword(next)) {
      newError =
          'Пароль: минимум 10 символов, буквы, цифры и спецсимвол, без пробелов в начале и конце.';
    }
    if (!validators.isValidPassword(confirm)) {
      confirmError =
          'Подтверждение пароля должно быть не короче 10 символов, содержать буквы, цифры и спецсимвол, без пробелов в начале и конце.';
    } else if (confirm != next) {
      confirmError = 'Пароли не совпадают.';
    }

    if (currentError != null || newError != null || confirmError != null) {
      setState(() {
        _currentError = currentError;
        _newError = newError;
        _confirmError = confirmError;
      });
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      await widget.onSubmit(
        PasswordChangePayload(
          currentPassword: current,
          newPassword: next,
          passwordConfirm: confirm,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = error.message.trim().isEmpty
            ? 'Не удалось изменить пароль.'
            : error.message.trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'Не удалось изменить пароль. Попробуйте ещё раз.';
      });
    }
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.label,
    required this.controller,
    required this.visible,
    required this.onToggle,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      onChanged: onChanged,
      decoration: _inputDecoration(label).copyWith(
        errorText: errorText,
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _PlaceholderSettingsCard extends StatelessWidget {
  const _PlaceholderSettingsCard({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _settingsLabel(section),
            style: const TextStyle(
              color: _text,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Раздел будет подключен следующим шагом.',
            style: TextStyle(color: _muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.saved});

  final bool saved;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Услуги и цены',
          style: TextStyle(
            color: _text,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const _ServicesSubtitle(),
        if (saved) ...[
          const SizedBox(height: 8),
          const Text(
            'Изменения сохранены',
            style: TextStyle(color: _accent, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }
}

class _ServicesSubtitle extends StatelessWidget {
  const _ServicesSubtitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Укажите информацию о своих услугах, стоимости и времени.\n'
      'Эти данные увидят клиенты при записи.',
      style: TextStyle(color: _muted, height: 1.45),
    );
  }
}

class _MasterCategoryCard extends StatelessWidget {
  const _MasterCategoryCard({
    required this.isDesktop,
    required this.category,
    required this.selectedStyles,
    required this.onCategoryChanged,
    required this.onAddStyle,
    required this.onRemoveStyle,
  });

  final bool isDesktop;
  final String category;
  final List<String> selectedStyles;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onAddStyle;
  final ValueChanged<String> onRemoveStyle;

  bool get _isTattoo => category == 'Тату-мастер';

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Категория мастера',
          style: TextStyle(color: _text, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: isDesktop ? 280 : double.infinity,
          child: DropdownButtonFormField<String>(
            value: category,
            decoration: _inputDecoration(''),
            items: const [
              DropdownMenuItem(
                value: 'Тату-мастер',
                child: Text('Тату-мастер'),
              ),
              DropdownMenuItem(
                value: 'Мастер пирсинга',
                child: Text('Мастер пирсинга'),
              ),
            ],
            onChanged: onCategoryChanged,
          ),
        ),
        const SizedBox(height: 20),
        if (_isTattoo) ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Стили тату (выберите один или несколько)',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w800),
                ),
              ),
              _TattooStylePicker(
                selectedStyles: selectedStyles,
                onAddStyle: onAddStyle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedStyles
                .map(
                  (style) => InputChip(
                    label: Text(style),
                    onDeleted: () => onRemoveStyle(style),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    backgroundColor: _soft,
                    side: BorderSide.none,
                    labelStyle: const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
                .toList(),
          ),
        ] else
          const Text(
            'Для мастера пирсинга стили тату не указываются.',
            style: TextStyle(color: _muted, height: 1.45),
          ),
      ],
    );

    if (!isDesktop) {
      return _SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            content,
            const SizedBox(height: 16),
            const _CategoryInfoCard(),
          ],
        ),
      );
    }

    return _SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: content),
          const SizedBox(width: 28),
          const SizedBox(width: 360, child: _CategoryInfoCard()),
        ],
      ),
    );
  }
}

class _CategoryInfoCard extends StatelessWidget {
  const _CategoryInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: _accent, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Как это работает?',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'Клиент увидит выбранные стили в вашем профиле и сможет записаться только на те направления, в которых вы работаете.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TattooStylePicker extends StatelessWidget {
  const _TattooStylePicker({
    required this.selectedStyles,
    required this.onAddStyle,
  });

  final List<String> selectedStyles;
  final ValueChanged<String> onAddStyle;

  @override
  Widget build(BuildContext context) {
    final availableStyles = _tattooStyles
        .where((style) => !selectedStyles.contains(style))
        .toList();

    return PopupMenuButton<String>(
      enabled: availableStyles.isNotEmpty,
      tooltip: 'Добавить стиль',
      onSelected: onAddStyle,
      itemBuilder: (context) {
        return availableStyles
            .map(
              (style) =>
                  PopupMenuItem<String>(value: style, child: Text(style)),
            )
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: availableStyles.isEmpty ? _soft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 18,
              color: availableStyles.isEmpty ? _muted : _accent,
            ),
            const SizedBox(width: 6),
            Text(
              availableStyles.isEmpty ? 'Все выбраны' : 'Добавить стиль',
              style: TextStyle(
                color: availableStyles.isEmpty ? _muted : _accent,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkTermsCard extends StatelessWidget {
  const _WorkTermsCard({
    required this.isDesktop,
    required this.minPriceController,
    required this.hourlyRateController,
    required this.breakValue,
    required this.onMinPriceChanged,
    required this.onHourlyRateChanged,
    required this.onBreakChanged,
  });

  final bool isDesktop;
  final TextEditingController minPriceController;
  final TextEditingController hourlyRateController;
  final String breakValue;
  final ValueChanged<String> onMinPriceChanged;
  final ValueChanged<String> onHourlyRateChanged;
  final ValueChanged<String?> onBreakChanged;

  @override
  Widget build(BuildContext context) {
    final fields = [
      _MoneyField(
        label: 'Минимальная стоимость сеанса, ₽',
        hint: 'Минимальная сумма за сеанс продолжительностью до 1 часа.',
        controller: minPriceController,
        onChanged: onMinPriceChanged,
      ),
      _MoneyField(
        label: 'Стоимость за час работы, ₽',
        hint: 'Стоимость каждого следующего часа после первого.',
        controller: hourlyRateController,
        onChanged: onHourlyRateChanged,
      ),
      _BreakDropdown(value: breakValue, onChanged: onBreakChanged),
    ];

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Условия работы',
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 20),
          isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: fields
                      .map(
                        (field) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 22),
                            child: field,
                          ),
                        ),
                      )
                      .toList(),
                )
              : Column(
                  children: fields
                      .map(
                        (field) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: field,
                        ),
                      )
                      .toList(),
                ),
        ],
      ),
    );
  }
}

class _ServicesCard extends StatelessWidget {
  const _ServicesCard({
    required this.services,
    required this.minSessionPrice,
    required this.hourlyRate,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onDurationChanged,
    required this.onPriceChanged,
  });

  final List<MasterService> services;
  final int minSessionPrice;
  final int hourlyRate;
  final VoidCallback onAdd;
  final ValueChanged<MasterService> onEdit;
  final ValueChanged<MasterService> onDelete;
  final void Function(MasterService service, double? duration)
  onDurationChanged;
  final void Function(MasterService service, String value) onPriceChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return _SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Услуги',
                        style: TextStyle(
                          color: _text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить услугу'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _line),
              if (compact)
                ...services.map(
                  (service) => _MobileServiceCard(
                    service: service,
                    minSessionPrice: minSessionPrice,
                    hourlyRate: hourlyRate,
                    onEdit: () => onEdit(service),
                    onDelete: () => onDelete(service),
                    onDurationChanged: (value) =>
                        onDurationChanged(service, value),
                    onPriceChanged: (value) => onPriceChanged(service, value),
                  ),
                )
              else
                Column(
                  children: [
                    const _ServiceTableHeader(),
                    ...services.map(
                      (service) => _ServiceRow(
                        service: service,
                        minSessionPrice: minSessionPrice,
                        hourlyRate: hourlyRate,
                        onEdit: () => onEdit(service),
                        onDelete: () => onDelete(service),
                        onDurationChanged: (value) =>
                            onDurationChanged(service, value),
                        onPriceChanged: (value) =>
                            onPriceChanged(service, value),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ServiceTableHeader extends StatelessWidget {
  const _ServiceTableHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 16, 22, 10),
      child: Row(
        children: [
          Expanded(flex: 30, child: _HeaderText('Услуга')),
          Expanded(flex: 18, child: _HeaderText('Тип')),
          Expanded(flex: 18, child: _HeaderText('Длительность')),
          Expanded(flex: 20, child: _HeaderText('Рекомендуемая цена')),
          Expanded(flex: 20, child: _HeaderText('Цена услуги')),
          SizedBox(width: 88, child: _HeaderText('Действия')),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.minSessionPrice,
    required this.hourlyRate,
    required this.onEdit,
    required this.onDelete,
    required this.onDurationChanged,
    required this.onPriceChanged,
  });

  final MasterService service;
  final int minSessionPrice;
  final int hourlyRate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<double?> onDurationChanged;
  final ValueChanged<String> onPriceChanged;

  int get recommendedPrice =>
      _calculateRecommended(service, minSessionPrice, hourlyRate);

  @override
  Widget build(BuildContext context) {
    final manuallyChanged =
        !service.useAutoPrice || service.price != recommendedPrice;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 30, child: _ServiceName(service: service)),
          Expanded(flex: 18, child: _TypeChip(type: service.type)),
          Expanded(
            flex: 18,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _CompactDurationDropdown(
                value: service.durationHours,
                sketchOnly: service.type == ServiceType.sketch,
                enabled:
                    service.type == ServiceType.session ||
                    service.type == ServiceType.consultation,
                onChanged: onDurationChanged,
              ),
            ),
          ),
          Expanded(
            flex: 20,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _RecommendedPrice(
                service: service,
                recommendedPrice: recommendedPrice,
                hourlyRate: hourlyRate,
              ),
            ),
          ),
          Expanded(
            flex: 20,
            child: _EditablePrice(
              service: service,
              manuallyChanged: manuallyChanged,
              onChanged: onPriceChanged,
            ),
          ),
          SizedBox(
            width: 88,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Редактировать',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  tooltip: 'Удалить',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileServiceCard extends StatelessWidget {
  const _MobileServiceCard({
    required this.service,
    required this.minSessionPrice,
    required this.hourlyRate,
    required this.onEdit,
    required this.onDelete,
    required this.onDurationChanged,
    required this.onPriceChanged,
  });

  final MasterService service;
  final int minSessionPrice;
  final int hourlyRate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<double?> onDurationChanged;
  final ValueChanged<String> onPriceChanged;

  @override
  Widget build(BuildContext context) {
    final recommended = _calculateRecommended(
      service,
      minSessionPrice,
      hourlyRate,
    );
    final manuallyChanged =
        !service.useAutoPrice || service.price != recommended;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ServiceName(service: service)),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TypeChip(type: service.type),
          const SizedBox(height: 12),
          _DurationDropdown(
            value: service.durationHours,
            sketchOnly: service.type == ServiceType.sketch,
            enabled:
                service.type == ServiceType.session ||
                service.type == ServiceType.consultation,
            onChanged: onDurationChanged,
          ),
          const SizedBox(height: 12),
          _RecommendedPrice(
            service: service,
            recommendedPrice: recommended,
            hourlyRate: hourlyRate,
          ),
          const SizedBox(height: 12),
          _EditablePrice(
            service: service,
            manuallyChanged: manuallyChanged,
            onChanged: onPriceChanged,
          ),
        ],
      ),
    );
  }
}

class _ServiceEditorSheet extends StatefulWidget {
  const _ServiceEditorSheet({
    required this.service,
    required this.minSessionPrice,
    required this.hourlyRate,
  });

  final MasterService? service;
  final int minSessionPrice;
  final int hourlyRate;

  @override
  State<_ServiceEditorSheet> createState() => _ServiceEditorSheetState();
}

class _ServiceEditorSheetState extends State<_ServiceEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late ServiceType _type;
  late double? _duration;
  late bool _useAutoPrice;
  late bool _fromPrice;
  bool _priceChangedManually = false;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _nameController = TextEditingController(text: service?.name ?? '');
    _descriptionController = TextEditingController(
      text: service?.description ?? '',
    );
    _type = service?.type ?? ServiceType.session;
    _duration = service?.durationHours ?? 1;
    _useAutoPrice =
        _type == ServiceType.session && (service?.useAutoPrice ?? true);
    _fromPrice = service?.fromPrice ?? false;
    _priceChangedManually = service != null && !service.useAutoPrice;
    final price =
        service?.price ??
        _calculateRecommended(
          MasterService(
            id: 'new',
            name: '',
            description: '',
            type: _type,
            durationHours: _duration,
            price: widget.minSessionPrice,
            useAutoPrice: _useAutoPrice,
          ),
          widget.minSessionPrice,
          widget.hourlyRate,
        );
    _priceController = TextEditingController(text: price.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.service == null
                      ? 'Добавить услугу'
                      : 'Редактировать услугу',
                  style: const TextStyle(
                    color: _text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                _LabeledInput(
                  label: 'Название услуги',
                  controller: _nameController,
                ),
                const SizedBox(height: 14),
                _LabeledInput(
                  label: 'Описание',
                  controller: _descriptionController,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<ServiceType>(
                  value: _type,
                  decoration: _inputDecoration('Тип услуги'),
                  items: ServiceType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(_typeLabel(type)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _applyTypeDefaults(value);
                    });
                  },
                ),
                const SizedBox(height: 14),
                _DurationDropdown(
                  value: _duration,
                  sketchOnly: _type == ServiceType.sketch,
                  enabled: _type != ServiceType.sketch,
                  onChanged: (value) {
                    setState(() {
                      _duration = value;
                      _syncEditorPrice();
                    });
                  },
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  value: _useAutoPrice,
                  onChanged: _type == ServiceType.session
                      ? (value) {
                          setState(() {
                            _useAutoPrice = value;
                            _priceChangedManually = !value;
                            _syncEditorPrice();
                          });
                        }
                      : null,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Использовать автоматический расчёт'),
                  subtitle: Text(
                    _type == ServiceType.session
                        ? 'Цена будет пересчитываться при изменении длительности.'
                        : 'Для консультации и эскиза цена задаётся вручную.',
                  ),
                ),
                const SizedBox(height: 14),
                _LabeledInput(
                  label: 'Цена услуги, ₽',
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: _moneyInputFormatters,
                  onChanged: _handlePriceChanged,
                ),
                if (_priceChangedManually || _type != ServiceType.session) ...[
                  const SizedBox(height: 6),
                  Text(
                    _type == ServiceType.session
                        ? 'Изменено вручную'
                        : _typeHelpText,
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_type == ServiceType.sketch)
                  CheckboxListTile(
                    value: _fromPrice,
                    onChanged: (value) =>
                        setState(() => _fromPrice = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Показывать как “от X ₽”'),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncEditorPrice() {
    if (!_useAutoPrice || _type != ServiceType.session) return;
    final service = MasterService(
      id: 'preview',
      name: '',
      description: '',
      type: _type,
      durationHours: _duration,
      price: widget.minSessionPrice,
      useAutoPrice: true,
    );
    _priceController.text = _calculateRecommended(
      service,
      widget.minSessionPrice,
      widget.hourlyRate,
    ).toString();
    _priceChangedManually = false;
  }

  void _handlePriceChanged(String value) {
    if (_type == ServiceType.session && _useAutoPrice) {
      setState(() {
        _useAutoPrice = false;
        _priceChangedManually = true;
      });
      return;
    }
    setState(() => _priceChangedManually = true);
  }

  void _applyTypeDefaults(ServiceType type) {
    final previousType = _type;
    final shouldUpdateName =
        _nameController.text.trim().isEmpty ||
        _nameController.text.trim() == _defaultNameForType(previousType);
    final shouldUpdateDescription =
        _descriptionController.text.trim().isEmpty ||
        _descriptionController.text.trim() ==
            _defaultDescriptionForType(previousType);

    _type = type;
    if (shouldUpdateName) {
      _nameController.text = _defaultNameForType(type);
    }
    if (shouldUpdateDescription) {
      _descriptionController.text = _defaultDescriptionForType(type);
    }

    if (type == ServiceType.session) {
      if (previousType != ServiceType.session || _duration == null) {
        _duration = 1;
      }
      _useAutoPrice = true;
      _fromPrice = false;
      _syncEditorPrice();
      return;
    }

    _useAutoPrice = false;
    _priceChangedManually = true;
    if (type == ServiceType.consultation) {
      _duration = 0.5;
      _fromPrice = false;
      _priceController.text = '0';
      return;
    }

    _duration = null;
    _fromPrice = true;
    _priceController.text = '2000';
  }

  String _defaultNameForType(ServiceType type) {
    return switch (type) {
      ServiceType.session => 'Минимальная тату',
      ServiceType.consultation => 'Консультация',
      ServiceType.sketch => 'Разработка эскиза',
    };
  }

  String _defaultDescriptionForType(ServiceType type) {
    return switch (type) {
      ServiceType.session => 'Небольшие татуировки до 5 см',
      ServiceType.consultation =>
        'Обсуждение идеи, стиля, размера, места нанесения и примерной стоимости.',
      ServiceType.sketch =>
        'Создание индивидуального эскиза по пожеланиям клиента.',
    };
  }

  String get _typeHelpText {
    return switch (_type) {
      ServiceType.consultation => 'Для консультации цена задаётся вручную.',
      ServiceType.sketch =>
        'Для эскиза цена задаётся вручную и зависит от сложности.',
      ServiceType.session => 'Изменено вручную',
    };
  }

  void _submit() {
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    if (_type == ServiceType.session &&
        (name.isEmpty || description.isEmpty || _duration == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заполните название, описание и длительность сеанса'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final resolvedName = name.isNotEmpty
        ? name
        : _type == ServiceType.consultation
        ? 'Консультация'
        : 'Разработка эскиза';
    final resolvedDescription = description.isNotEmpty
        ? description
        : _type == ServiceType.consultation
        ? 'Обсуждение идеи, стиля, размера, места нанесения и примерной стоимости.'
        : 'Создание индивидуального эскиза по пожеланиям клиента.';

    Navigator.of(context).pop(
      MasterService(
        id:
            widget.service?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: resolvedName,
        description: resolvedDescription,
        type: _type,
        durationHours: _type == ServiceType.sketch ? null : _duration,
        price: _parseMoney(_priceController.text),
        useAutoPrice: _type == ServiceType.session && _useAutoPrice,
        fromPrice: _type == ServiceType.sketch && _fromPrice,
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: _moneyInputFormatters,
          onChanged: onChanged,
          decoration: _inputDecoration('').copyWith(suffixText: '₽'),
        ),
        const SizedBox(height: 8),
        Text(hint, style: const TextStyle(color: _muted, height: 1.35)),
      ],
    );
  }
}

class _BreakDropdown extends StatelessWidget {
  const _BreakDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Перерыв между клиентами',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: _inputDecoration(''),
          items: const ['0 минут', '15 минут', '30 минут', '45 минут', '1 час']
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        const Text(
          'Время, которое автоматически блокируется до и после записи.',
          style: TextStyle(color: _muted, height: 1.35),
        ),
      ],
    );
  }
}

class _DurationDropdown extends StatelessWidget {
  const _DurationDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.sketchOnly = false,
    this.showLabel = true,
  });

  final double? value;
  final bool enabled;
  final ValueChanged<double?> onChanged;
  final bool sketchOnly;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final items = sketchOnly
        ? const [DropdownMenuItem<double?>(value: null, child: Text('-'))]
        : const [
            DropdownMenuItem<double?>(value: null, child: Text('-')),
            DropdownMenuItem<double?>(value: 0.5, child: Text('~ 30 минут')),
            DropdownMenuItem<double?>(value: 1, child: Text('~ 1 час')),
            DropdownMenuItem<double?>(value: 2, child: Text('~ 2 часа')),
            DropdownMenuItem<double?>(value: 3, child: Text('~ 3 часа')),
            DropdownMenuItem<double?>(value: 4, child: Text('~ 4 часа')),
            DropdownMenuItem<double?>(value: 5, child: Text('~ 5 часов')),
            DropdownMenuItem<double?>(value: 6, child: Text('~ 6 часов')),
            DropdownMenuItem<double?>(value: 7, child: Text('~ 7 часов')),
            DropdownMenuItem<double?>(value: 8, child: Text('~ 8 часов')),
            DropdownMenuItem<double?>(value: 9, child: Text('~ 9 часов')),
            DropdownMenuItem<double?>(value: 10, child: Text('~ 10 часов')),
            DropdownMenuItem<double?>(value: 11, child: Text('~ 11 часов')),
            DropdownMenuItem<double?>(value: 12, child: Text('~ 12 часов')),
          ];

    return DropdownButtonFormField<double?>(
      value: value,
      decoration: _inputDecoration('Примерная длительность'),
      items: items,
      onChanged: enabled && !sketchOnly ? onChanged : null,
    );
  }
}

class _CompactDurationDropdown extends StatelessWidget {
  const _CompactDurationDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.sketchOnly = false,
  });

  final double? value;
  final bool enabled;
  final ValueChanged<double?> onChanged;
  final bool sketchOnly;

  @override
  Widget build(BuildContext context) {
    final items = sketchOnly
        ? const [DropdownMenuItem<double?>(value: null, child: Text('-'))]
        : const [
            DropdownMenuItem<double?>(value: null, child: Text('-')),
            DropdownMenuItem<double?>(value: 0.5, child: Text('~ 30 минут')),
            DropdownMenuItem<double?>(value: 1, child: Text('~ 1 час')),
            DropdownMenuItem<double?>(value: 2, child: Text('~ 2 часа')),
            DropdownMenuItem<double?>(value: 3, child: Text('~ 3 часа')),
            DropdownMenuItem<double?>(value: 4, child: Text('~ 4 часа')),
            DropdownMenuItem<double?>(value: 5, child: Text('~ 5 часов')),
            DropdownMenuItem<double?>(value: 6, child: Text('~ 6 часов')),
            DropdownMenuItem<double?>(value: 7, child: Text('~ 7 часов')),
            DropdownMenuItem<double?>(value: 8, child: Text('~ 8 часов')),
            DropdownMenuItem<double?>(value: 9, child: Text('~ 9 часов')),
            DropdownMenuItem<double?>(value: 10, child: Text('~ 10 часов')),
            DropdownMenuItem<double?>(value: 11, child: Text('~ 11 часов')),
            DropdownMenuItem<double?>(value: 12, child: Text('~ 12 часов')),
          ];

    return DropdownButtonFormField<double?>(
      value: value,
      decoration: _inputDecoration(''),
      items: items,
      onChanged: enabled && !sketchOnly ? onChanged : null,
    );
  }
}

/*
class _EditablePrice extends StatelessWidget {
  const _EditablePrice({
    required this.service,
    required this.manuallyChanged,
    required this.onChanged,
  });

  final MasterService service;
  final bool manuallyChanged;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: ValueKey('${service.id}-${service.price}'),
          initialValue: service.price.toString(),
          keyboardType: TextInputType.number,
          inputFormatters: _moneyInputFormatters,
          onChanged: onChanged,
          decoration: _inputDecoration('').copyWith(suffixText: 'в‚Ѕ'),
        ),
        if (manuallyChanged) ...[
          const SizedBox(height: 6),
          const Text(
            'РР·РјРµРЅРµРЅРѕ РІСЂСѓС‡РЅСѓСЋ',
            style: TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }
}

class _UnusedOldDurationDropdownItems {
  const _UnusedOldDurationDropdownItems._();

  static const items = [
        DropdownMenuItem<double?>(value: null, child: Text('Без длительности')),
        DropdownMenuItem<double?>(value: 0.5, child: Text('~ 30 минут')),
        DropdownMenuItem<double?>(value: 1, child: Text('~ 1 час')),
        DropdownMenuItem<double?>(value: 2, child: Text('~ 2 часа')),
        DropdownMenuItem<double?>(value: 3, child: Text('~ 3 часа')),
        DropdownMenuItem<double?>(value: 4, child: Text('~ 4 часа')),
        DropdownMenuItem<double?>(value: 5, child: Text('~ 5 часов')),
        DropdownMenuItem<double?>(value: 6, child: Text('~ 6 часов')),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
*/

class _EditablePrice extends StatefulWidget {
  const _EditablePrice({
    required this.service,
    required this.manuallyChanged,
    required this.onChanged,
  });

  final MasterService service;
  final bool manuallyChanged;
  final ValueChanged<String> onChanged;

  @override
  State<_EditablePrice> createState() => _EditablePriceState();
}

class _EditablePriceState extends State<_EditablePrice> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.service.price.toString());
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _EditablePrice oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = widget.service.price.toString();

    if (oldWidget.service.id != widget.service.id) {
      _controller.text = nextText;
      return;
    }

    if (!_focusNode.hasFocus && _controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          keyboardType: TextInputType.number,
          inputFormatters: _moneyInputFormatters,
          onChanged: widget.onChanged,
          decoration: _inputDecoration('').copyWith(suffixText: '₽'),
        ),
        if (widget.manuallyChanged) ...[
          const SizedBox(height: 6),
          const Text(
            'Изменено вручную',
            style: TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _RecommendedPrice extends StatelessWidget {
  const _RecommendedPrice({
    required this.service,
    required this.recommendedPrice,
    required this.hourlyRate,
  });

  final MasterService service;
  final int recommendedPrice;
  final int hourlyRate;

  @override
  Widget build(BuildContext context) {
    final label = service.type == ServiceType.sketch
        ? 'от ${_formatMoney(service.price)} ₽'
        : service.type == ServiceType.session
        ? '${_formatMoney(recommendedPrice)} ₽'
        : '${_formatMoney(service.price)} ₽';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
        ),
        if (service.type == ServiceType.session &&
            service.durationHours != null)
          Text(
            service.durationHours! <= 1
                ? 'минимальная стоимость'
                : '1 час + ${service.durationHours!.round() - 1} ч x ${_formatMoney(hourlyRate)}',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
      ],
    );
  }
}

class _ServiceName extends StatelessWidget {
  const _ServiceName({required this.service});

  final MasterService service;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          service.name,
          style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(service.description, style: const TextStyle(color: _text)),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final ServiceType type;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(_typeLabel(type)),
      backgroundColor: _soft,
      side: BorderSide.none,
      labelStyle: const TextStyle(color: _text, fontWeight: FontWeight.w700),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: _accent, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Рекомендуемая цена рассчитывается автоматически. Вы всегда можете изменить цену услуги вручную с учётом сложности, стиля и других факторов. Клиент увидит цену “от X ₽”, примерную длительность и предупреждение, что итоговая стоимость может измениться после консультации.',
              style: TextStyle(color: _text, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.enabled = true,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      enabled: enabled,
      onChanged: onChanged,
      decoration: _inputDecoration(label),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
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

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label.isEmpty ? null : label,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
      borderSide: const BorderSide(color: _accent, width: 1.4),
    ),
  );
}

String _formatTime(int minutes) {
  final safeMinutes = minutes.clamp(0, 1440).toInt();
  final hours = safeMinutes ~/ 60;
  final mins = safeMinutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
}

String _intervalCountLabel(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) {
    return 'интервал';
  }
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'интервала';
  }
  return 'интервалов';
}

List<SettingsSection> _settingsSectionsFor(AuthUser? user) {
  final isMaster = user?.role == 'master';
  return [
    SettingsSection.profile,
    if (isMaster) SettingsSection.servicesPrices,
    if (isMaster) SettingsSection.schedule,
    SettingsSection.notifications,
    SettingsSection.security,
  ];
}

String _settingsLabel(SettingsSection section) {
  return switch (section) {
    SettingsSection.profile => 'Профиль',
    SettingsSection.servicesPrices => 'Услуги и цены',
    SettingsSection.schedule => 'График работы',
    SettingsSection.notifications => 'Уведомления',
    SettingsSection.security => 'Безопасность',
  };
}

IconData _settingsIcon(SettingsSection section) {
  return switch (section) {
    SettingsSection.profile => Icons.person_outline,
    SettingsSection.servicesPrices => Icons.list_alt_outlined,
    SettingsSection.schedule => Icons.calendar_today_outlined,
    SettingsSection.notifications => Icons.notifications_none_rounded,
    SettingsSection.security => Icons.lock_outline_rounded,
  };
}

int _calculateRecommended(
  MasterService service,
  int minSessionPrice,
  int hourlyRate,
) {
  if (service.type != ServiceType.session || service.durationHours == null) {
    return service.price;
  }
  if (service.durationHours! <= 1) {
    return minSessionPrice;
  }
  return (minSessionPrice + ((service.durationHours! - 1) * hourlyRate))
      .round();
}

int _parseMoney(String value) {
  return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

String _formatMoney(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final reverseIndex = raw.length - i;
    buffer.write(raw[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) {
      buffer.write(' ');
    }
  }
  return buffer.toString();
}

String _typeLabel(ServiceType type) {
  return switch (type) {
    ServiceType.session => 'Сеанс',
    ServiceType.consultation => 'Консультация',
    ServiceType.sketch => 'Эскиз',
  };
}

String _serviceTypeValue(ServiceType type) {
  return switch (type) {
    ServiceType.session => 'session',
    ServiceType.consultation => 'consultation',
    ServiceType.sketch => 'sketch',
  };
}

ServiceType _serviceTypeFromValue(String value) {
  return switch (value) {
    'consultation' => ServiceType.consultation,
    'sketch' => ServiceType.sketch,
    _ => ServiceType.session,
  };
}

bool _isBackendServiceId(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value.trim());
}
