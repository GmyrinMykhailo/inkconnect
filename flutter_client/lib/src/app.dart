import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/api_client.dart';
import 'auth/auth_styles.dart';
import 'auth/auth_widgets.dart';
import 'auth/login_screen.dart';
import 'auth/register_screen.dart';
import 'auth/session_store.dart';
import 'models.dart';
import 'screens/appointments_screen.dart';
import 'screens/appointment_care_journals_screen.dart';
import 'screens/authenticated_dashboard_screen.dart';
import 'screens/booking_service_screen.dart';
import 'screens/care_journal_screen.dart';
import 'screens/care_step_confirmation_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/client_journals_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/guest_dashboard_screen.dart';
import 'screens/guest_master_profile_screen.dart';
import 'screens/guest_search_screen.dart';
import 'screens/master_appointments_screen.dart';
import 'screens/my_care_journals_screen.dart';
import 'screens/recommendation_approval_screen.dart';
import 'screens/recommendation_builder_screen.dart';
import 'screens/services_prices_screen.dart';
import 'widgets/authenticated_badge_counts_scope.dart';
import 'widgets/authenticated_profile_avatar_scope.dart';

void runInkConnectApp() {
  runApp(const InkConnectApp());
}

enum AppScreen {
  guest,
  guestSearch,
  guestMasterProfile,
  userProfile,
  myProfile,
  profileSettings,
  login,
  register,
  dashboard,
  favorites,
  booking,
  appointments,
  masterAppointments,
  recommendationBuilder,
  recommendationApproval,
  chat,
  myCareJournals,
  appointmentCareJournals,
  careJournal,
  careStepConfirmation,
  clientJournals,
  servicesPrices,
}

class InkConnectApp extends StatelessWidget {
  const InkConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InkConnect',
      debugShowCheckedModeBanner: false,
      theme: buildInkConnectTheme(),
      locale: const Locale('ru', 'RU'),
      supportedLocales: const [Locale('ru', 'RU')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mediaQuery = MediaQuery.maybeOf(context);
        if (mediaQuery == null) {
          return child ?? const SizedBox.shrink();
        }
        return MediaQuery(
          data: mediaQuery.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const InkConnectShell(),
    );
  }
}

class InkConnectShell extends StatefulWidget {
  const InkConnectShell({super.key});

  @override
  State<InkConnectShell> createState() => _InkConnectShellState();
}

class _InkConnectShellState extends State<InkConnectShell> {
  static const _appointmentJournalRoutePrefix = 'appointment:';

  late final InkConnectApiClient _api;

  AppScreen _screen = AppScreen.guest;
  AuthUser? _currentUser;
  UserProfile? _currentProfile;
  UserProfile? _lastRegisteredProfile;
  MasterSettings? _currentMasterSettings;
  List<MasterServiceSettings>? _currentMasterServices;
  AppointmentCounts? _clientAppointmentCounts;
  AppointmentCounts? _masterAppointmentCounts;
  String? _sessionToken;
  String? _loginNotice;
  String? _mockRouteId;
  String? _selectedJournalId;
  String? _selectedCareStepId;
  bool _selectedJournalAsMaster = false;
  String? _selectedAppointmentJournalsAppointmentId;
  List<AppointmentJournalSummary> _selectedAppointmentJournals =
      const <AppointmentJournalSummary>[];
  bool _selectedAppointmentJournalsAsMaster = false;
  bool _loadingAppointmentJournals = false;
  String? _appointmentJournalsError;
  String? _bookingServiceId;
  String _selectedPublicMasterUsername = 'master';
  String? _selectedUserProfileUsername;
  PublicUserProfile? _selectedUserProfile;
  String? _selectedUserProfileError;
  String? _selectedChatPeerUserId;
  GuestSearchFilters _guestSearchFilters = GuestSearchFilters.initial();
  final Set<String> _approvedRecommendationIds = <String>{};
  final Map<String, String> _approvedRecommendationJournalIds =
      <String, String>{};
  final Set<String> _completedCareStepIds = <String>{'day-1', 'day-3', 'day-7'};
  bool _showProfileFullName = true;
  bool _showProfileCity = true;
  bool _isBootstrapping = true;
  String? _globalError;

  @override
  void initState() {
    super.initState();
    _api = InkConnectApiClient(onUnauthorized: _handleUnauthorizedSession);
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final storedToken = _sessionToken ?? SessionTokenStore.read();

    if (storedToken == null || storedToken.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isBootstrapping = false;
      });
      return;
    }

    try {
      final user = await _api.currentUser(storedToken);
      final loadedProfile = await _loadCurrentProfileOrNull(storedToken);
      final profile = _profileWithRegistrationFallback(user, loadedProfile);
      final masterSettings = user.role == 'master'
          ? await _loadCurrentMasterSettingsOrNull(storedToken)
          : null;
      final masterServices = user.role == 'master'
          ? await _loadCurrentMasterServicesOrNull(storedToken)
          : null;
      final clientCounts = await _loadClientAppointmentCountsOrNull(
        storedToken,
      );
      final masterCounts = user.role == 'master'
          ? await _loadMasterAppointmentCountsOrNull(storedToken)
          : null;
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionToken = storedToken;
        _currentUser = user;
        _currentProfile = profile;
        _currentMasterSettings = masterSettings;
        _currentMasterServices = masterServices;
        _clientAppointmentCounts = clientCounts;
        _masterAppointmentCounts = masterCounts;
        if (profile != null) {
          _showProfileFullName = profile.showFullNameInProfile;
          _showProfileCity = profile.showCityInProfile;
        }
        _screen = AppScreen.dashboard;
        _isBootstrapping = false;
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        SessionTokenStore.clear();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isBootstrapping = false;
        _screen = error.isUnauthorized ? AppScreen.login : AppScreen.guest;
        _globalError = error.isUnauthorized
            ? 'Сессия истекла. Войдите снова.'
            : 'Не удалось восстановить сессию. Повторите попытку позже.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isBootstrapping = false;
        _screen = AppScreen.guest;
        _globalError =
            'Не удалось восстановить сессию. Повторите попытку позже.';
      });
    }
  }

  void _handleUnauthorizedSession() {
    final hadSession =
        _sessionToken != null || (SessionTokenStore.read() ?? '').isNotEmpty;
    SessionTokenStore.clear();
    if (!mounted || !hadSession) {
      return;
    }
    setState(() {
      _sessionToken = null;
      _currentUser = null;
      _currentProfile = null;
      _lastRegisteredProfile = null;
      _currentMasterSettings = null;
      _currentMasterServices = null;
      _clientAppointmentCounts = null;
      _masterAppointmentCounts = null;
      _loginNotice = null;
      _selectedJournalId = null;
      _selectedCareStepId = null;
      _selectedAppointmentJournalsAppointmentId = null;
      _selectedAppointmentJournals = const <AppointmentJournalSummary>[];
      _selectedAppointmentJournalsAsMaster = false;
      _loadingAppointmentJournals = false;
      _appointmentJournalsError = null;
      _isBootstrapping = false;
      _screen = AppScreen.login;
      _globalError = 'Сессия истекла. Войдите снова.';
    });
  }

  Future<void> _handleLogin(String email, String password) async {
    final response = await _api.login(email: email, password: password);
    final loadedProfile = await _loadCurrentProfileOrNull(
      response.sessionToken,
    );
    final profile = _profileWithRegistrationFallback(
      response.user,
      loadedProfile,
    );
    final masterSettings = response.user.role == 'master'
        ? await _loadCurrentMasterSettingsOrNull(response.sessionToken)
        : null;
    final masterServices = response.user.role == 'master'
        ? await _loadCurrentMasterServicesOrNull(response.sessionToken)
        : null;
    final clientCounts = await _loadClientAppointmentCountsOrNull(
      response.sessionToken,
    );
    final masterCounts = response.user.role == 'master'
        ? await _loadMasterAppointmentCountsOrNull(response.sessionToken)
        : null;

    if (!mounted) {
      return;
    }
    SessionTokenStore.write(response.sessionToken);
    setState(() {
      _sessionToken = response.sessionToken;
      _currentUser = response.user;
      _currentProfile = profile;
      _currentMasterSettings = masterSettings;
      _currentMasterServices = masterServices;
      _clientAppointmentCounts = clientCounts;
      _masterAppointmentCounts = masterCounts;
      if (profile != null) {
        _showProfileFullName = profile.showFullNameInProfile;
        _showProfileCity = profile.showCityInProfile;
      }
      _globalError = null;
      _screen = AppScreen.dashboard;
    });
  }

  Future<UserProfile?> _loadCurrentProfileOrNull(String token) async {
    try {
      return await _api.currentProfile(token);
    } catch (_) {
      return null;
    }
  }

  Future<List<MasterServiceSettings>?> _loadCurrentMasterServicesOrNull(
    String token,
  ) async {
    try {
      return await _api.currentMasterServices(token);
    } catch (_) {
      return null;
    }
  }

  Future<MasterSettings?> _loadCurrentMasterSettingsOrNull(String token) async {
    try {
      return await _api.currentMasterSettings(token);
    } catch (_) {
      return null;
    }
  }

  Future<AppointmentCounts?> _loadClientAppointmentCountsOrNull(
    String token,
  ) async {
    try {
      return (await _api.clientAppointments(token)).counts;
    } catch (_) {
      return null;
    }
  }

  Future<AppointmentCounts?> _loadMasterAppointmentCountsOrNull(
    String token,
  ) async {
    try {
      return (await _api.masterAppointments(token)).counts;
    } catch (_) {
      return null;
    }
  }

  void _handleClientAppointmentCountsChanged(AppointmentCounts counts) {
    setState(() => _clientAppointmentCounts = counts);
  }

  void _handleMasterAppointmentCountsChanged(AppointmentCounts counts) {
    setState(() => _masterAppointmentCounts = counts);
  }

  void _handleProfileChanged(UserProfile profile) {
    setState(() {
      _currentProfile = profile;
      _lastRegisteredProfile = profile;
      _showProfileFullName = profile.showFullNameInProfile;
      _showProfileCity = profile.showCityInProfile;
    });
  }

  void _handleMasterServicesChanged(List<MasterServiceSettings> services) {
    setState(() {
      _currentMasterServices = services;
    });
  }

  void _handleMasterSettingsChanged(MasterSettings settings) {
    setState(() {
      _currentMasterSettings = settings;
    });
  }

  void _handleGuestSearchFiltersChanged(GuestSearchFilters filters) {
    _guestSearchFilters = filters;
  }

  Future<void> _handleRegistration(Map<String, dynamic> payload) async {
    final result = await _api.register(payload);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastRegisteredProfile = _profileDraftFromRegistration(result, payload);
      _globalError = null;
      _loginNotice =
          'Регистрация прошла успешно. Теперь вы можете войти в аккаунт.';
      _screen = AppScreen.login;
    });
  }

  UserProfile _profileDraftFromRegistration(
    RegistrationResponse result,
    Map<String, dynamic> payload,
  ) {
    String textField(String key) {
      return (payload[key] as String? ?? '').trim();
    }

    return UserProfile(
      id: result.userId,
      username: result.username,
      role: result.role,
      lastName: textField('last_name'),
      firstName: textField('first_name'),
      middleName: textField('middle_name'),
      studioName: textField('studio_name'),
      city: textField('city'),
      bio: textField('bio'),
      avatarUrl: '',
      showFullNameInProfile: false,
      showCityInProfile: payload['show_city_in_profile'] as bool? ?? false,
    );
  }

  UserProfile? _profileWithRegistrationFallback(
    AuthUser user,
    UserProfile? profile,
  ) {
    if (profile != null) {
      return profile;
    }

    final draft = _lastRegisteredProfile;
    if (draft == null) {
      return null;
    }

    if (draft.id == user.id || draft.username == user.username) {
      return draft;
    }

    return null;
  }

  Future<void> _handleLogout([AppScreen nextScreen = AppScreen.guest]) async {
    final token = _sessionToken;

    if (token != null && token.isNotEmpty) {
      try {
        await _api.logout(token);
      } catch (_) {}
    }
    SessionTokenStore.clear();

    if (!mounted) {
      return;
    }
    setState(() {
      _sessionToken = null;
      _currentUser = null;
      _currentProfile = null;
      _lastRegisteredProfile = null;
      _currentMasterSettings = null;
      _currentMasterServices = null;
      _clientAppointmentCounts = null;
      _masterAppointmentCounts = null;
      _loginNotice = null;
      _selectedUserProfileUsername = null;
      _selectedUserProfile = null;
      _selectedUserProfileError = null;
      _selectedAppointmentJournalsAppointmentId = null;
      _selectedAppointmentJournals = const <AppointmentJournalSummary>[];
      _selectedAppointmentJournalsAsMaster = false;
      _loadingAppointmentJournals = false;
      _appointmentJournalsError = null;
      _screen = nextScreen;
    });
  }

  void _switchTo(AppScreen screen) {
    setState(() {
      _globalError = null;
      if (screen != AppScreen.login) {
        _loginNotice = null;
      }
      if (screen != AppScreen.booking) {
        _bookingServiceId = null;
      }
      _screen = screen;
    });
  }

  void _openBooking([String? serviceId]) {
    setState(() {
      _globalError = null;
      _bookingServiceId = serviceId;
      _screen = AppScreen.booking;
    });
  }

  void _openFavorites() {
    if (_currentUser == null) {
      _switchTo(AppScreen.login);
      return;
    }
    setState(() {
      _globalError = null;
      _screen = AppScreen.favorites;
    });
  }

  void _openBookingForMaster(String username) {
    final trimmed = username.trim();
    final normalized = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    final currentUsername = _currentUser?.username.trim() ?? '';
    if (_currentUser?.role == 'master' &&
        normalized.isNotEmpty &&
        currentUsername.toLowerCase() == normalized.toLowerCase()) {
      _switchTo(AppScreen.myProfile);
      return;
    }
    setState(() {
      _globalError = null;
      _bookingServiceId = null;
      if (normalized.isNotEmpty) {
        _selectedPublicMasterUsername = normalized;
      }
      _screen = AppScreen.booking;
    });
  }

  void _openPublicMasterProfile(String username) {
    final trimmed = username.trim();
    final normalized = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    final currentUsername = _currentUser?.username.trim() ?? '';
    if (_currentUser?.role == 'master' &&
        normalized.isNotEmpty &&
        currentUsername.toLowerCase() == normalized.toLowerCase()) {
      _switchTo(AppScreen.myProfile);
      return;
    }
    setState(() {
      _globalError = null;
      if (normalized.isNotEmpty) {
        _selectedPublicMasterUsername = normalized;
      }
      _screen = AppScreen.guestMasterProfile;
    });
  }

  void _openAccountProfile(String username, bool isMaster) {
    if (isMaster) {
      _openPublicMasterProfile(username);
      return;
    }
    _openUserProfile(username);
  }

  void _openUserProfile(String username) {
    final trimmed = username.trim();
    final normalized = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    if (normalized.isEmpty) {
      return;
    }

    setState(() {
      _globalError = null;
      _selectedUserProfileUsername = normalized;
      _selectedUserProfile = null;
      _selectedUserProfileError = null;
      _screen = AppScreen.userProfile;
    });

    final token = _sessionToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _selectedUserProfileError = 'Профиль доступен после входа.';
      });
      return;
    }

    _loadUserProfile(normalized, token);
  }

  Future<void> _loadUserProfile(String username, String token) async {
    try {
      final profile = await _api.publicUserProfile(
        sessionToken: token,
        username: username,
      );
      if (!mounted || _selectedUserProfileUsername != username) {
        return;
      }
      setState(() {
        _selectedUserProfile = profile;
        _selectedUserProfileError = null;
      });
    } catch (_) {
      if (!mounted || _selectedUserProfileUsername != username) {
        return;
      }
      setState(() {
        _selectedUserProfileError = 'Профиль не удалось загрузить.';
      });
    }
  }

  void _openMockRoute(AppScreen screen, String id) {
    setState(() {
      _globalError = null;
      _mockRouteId = id;
      _screen = screen;
    });
  }

  void _openMessagesRoute() {
    if (_currentUser == null) {
      _switchTo(AppScreen.login);
      return;
    }
    setState(() {
      _globalError = null;
      _mockRouteId = null;
      _selectedChatPeerUserId = null;
      _screen = AppScreen.chat;
    });
  }

  void _openChatWithUser(String userId) {
    if (_currentUser == null) {
      _switchTo(AppScreen.login);
      return;
    }
    final trimmed = userId.trim();
    if (trimmed.isEmpty || trimmed == 'messages') {
      _openMessagesRoute();
      return;
    }
    setState(() {
      _globalError = null;
      _mockRouteId = null;
      _selectedChatPeerUserId = trimmed;
      _screen = AppScreen.chat;
    });
  }

  void _openCareJournalRoute(String id, {bool asMaster = false}) {
    setState(() {
      _globalError = null;
      _mockRouteId = id;
      _selectedJournalId = id;
      _selectedJournalAsMaster = asMaster;
      _screen = AppScreen.careJournal;
    });
  }

  void _openJournalNavigationRoute(String id, {bool asMaster = false}) {
    final trimmed = id.trim();
    if (trimmed.startsWith(_appointmentJournalRoutePrefix)) {
      final appointmentId = trimmed
          .substring(_appointmentJournalRoutePrefix.length)
          .trim();
      unawaited(
        _loadAppointmentJournalsForRoute(appointmentId, asMaster: asMaster),
      );
      return;
    }

    if (trimmed.isEmpty ||
        trimmed == 'journal' ||
        trimmed == 'mock' ||
        trimmed.startsWith('journal-')) {
      if (asMaster) {
        setState(() {
          _globalError = 'Журнал ухода по этой записи ещё не создан.';
        });
        return;
      }
      _openMyCareJournals();
      return;
    }

    _openCareJournalRoute(trimmed, asMaster: asMaster);
  }

  Future<void> _loadAppointmentJournalsForRoute(
    String appointmentId, {
    required bool asMaster,
    bool silent = false,
  }) async {
    final trimmed = appointmentId.trim();
    if (!silent) {
      setState(() {
        _globalError = null;
        _selectedAppointmentJournalsAppointmentId = trimmed;
        _selectedAppointmentJournals = const <AppointmentJournalSummary>[];
        _selectedAppointmentJournalsAsMaster = asMaster;
        _loadingAppointmentJournals = true;
        _appointmentJournalsError = null;
        _screen = AppScreen.appointmentCareJournals;
      });
    }

    final token = _sessionToken;
    if (trimmed.isEmpty || token == null || token.isEmpty) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _loadingAppointmentJournals = false;
        _appointmentJournalsError =
            'Не удалось загрузить журналы ухода: нет активной сессии или выбранной записи.';
      });
      return;
    }

    try {
      final journals = await _api.getAppointmentJournals(
        sessionToken: token,
        appointmentId: trimmed,
      );
      if (!mounted ||
          _selectedAppointmentJournalsAppointmentId != trimmed ||
          _selectedAppointmentJournalsAsMaster != asMaster) {
        return;
      }

      if (!silent &&
          journals.length == 1 &&
          journals.first.id.trim().isNotEmpty) {
        _openCareJournalRoute(journals.first.id, asMaster: asMaster);
        return;
      }

      setState(() {
        _selectedAppointmentJournals = journals;
        _loadingAppointmentJournals = false;
        _appointmentJournalsError = null;
      });
    } catch (error) {
      if (!mounted ||
          _selectedAppointmentJournalsAppointmentId != trimmed ||
          _selectedAppointmentJournalsAsMaster != asMaster) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _selectedAppointmentJournals = const <AppointmentJournalSummary>[];
        _loadingAppointmentJournals = false;
        _appointmentJournalsError =
            'Не удалось загрузить журналы ухода по записи: $error';
      });
    }
  }

  void _retryAppointmentJournalsRoute() {
    final appointmentId = _selectedAppointmentJournalsAppointmentId;
    if (appointmentId == null || appointmentId.trim().isEmpty) {
      return;
    }
    unawaited(
      _loadAppointmentJournalsForRoute(
        appointmentId,
        asMaster: _selectedAppointmentJournalsAsMaster,
      ),
    );
  }

  void _autoRefreshAppointmentJournalsRoute() {
    final appointmentId = _selectedAppointmentJournalsAppointmentId;
    if (appointmentId == null || appointmentId.trim().isEmpty) {
      return;
    }
    unawaited(
      _loadAppointmentJournalsForRoute(
        appointmentId,
        asMaster: _selectedAppointmentJournalsAsMaster,
        silent: true,
      ),
    );
  }

  void _openMyCareJournals() {
    setState(() {
      _globalError = null;
      _mockRouteId = null;
      _selectedJournalId = null;
      _selectedJournalAsMaster = false;
      _screen = AppScreen.myCareJournals;
    });
  }

  void _openClientCareJournalRoute(String id) {
    _openJournalNavigationRoute(id);
  }

  void _openCareStepConfirmationRoute(String stepId) {
    setState(() {
      _globalError = null;
      _selectedCareStepId = stepId;
      _screen = AppScreen.careStepConfirmation;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_screen == AppScreen.dashboard ||
        _screen == AppScreen.booking ||
        _screen == AppScreen.appointments ||
        _screen == AppScreen.masterAppointments ||
        _screen == AppScreen.recommendationBuilder ||
        _screen == AppScreen.recommendationApproval ||
        _screen == AppScreen.chat ||
        _screen == AppScreen.myCareJournals ||
        _screen == AppScreen.appointmentCareJournals ||
        _screen == AppScreen.careJournal ||
        _screen == AppScreen.careStepConfirmation ||
        _screen == AppScreen.clientJournals ||
        _screen == AppScreen.servicesPrices ||
        _screen == AppScreen.myProfile ||
        _screen == AppScreen.userProfile ||
        _screen == AppScreen.profileSettings ||
        _screen == AppScreen.favorites ||
        _screen == AppScreen.guest ||
        _screen == AppScreen.guestSearch ||
        _screen == AppScreen.guestMasterProfile) {
      return Scaffold(
        body: AuthenticatedProfileAvatarScope(
          avatarUrl: _currentProfile?.avatarUrl ?? '',
          child: AuthenticatedBadgeCountsScope(
            counts: AuthenticatedBadgeCounts(
              clientAppointments: _clientAppointmentCounts,
              masterAppointments: _masterAppointmentCounts,
            ),
            child: _buildScreenContent(),
          ),
        ),
      );
    }

    final isAuthScreen =
        _screen == AppScreen.login || _screen == AppScreen.register;
    final maxWidth = switch (_screen) {
      AppScreen.login => 1360.0,
      AppScreen.register => 1480.0,
      AppScreen.guest => 860.0,
      AppScreen.guestSearch => 860.0,
      AppScreen.guestMasterProfile => 860.0,
      AppScreen.userProfile => 860.0,
      AppScreen.myProfile => 860.0,
      AppScreen.profileSettings => 860.0,
      AppScreen.dashboard => 860.0,
      AppScreen.favorites => 860.0,
      AppScreen.booking => 860.0,
      AppScreen.appointments => 860.0,
      AppScreen.masterAppointments => 860.0,
      AppScreen.recommendationBuilder => 860.0,
      AppScreen.recommendationApproval => 860.0,
      AppScreen.chat => 860.0,
      AppScreen.myCareJournals => 860.0,
      AppScreen.appointmentCareJournals => 860.0,
      AppScreen.careJournal => 860.0,
      AppScreen.careStepConfirmation => 860.0,
      AppScreen.clientJournals => 860.0,
      AppScreen.servicesPrices => 860.0,
    };

    return Scaffold(
      body: DecoratedBox(
        decoration: authBackgroundDecoration,
        child: SafeArea(
          child: Align(
            alignment: isAuthScreen ? Alignment.topCenter : Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AuthPageCard(child: _buildScreenContent()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreenContent() {
    final token = _sessionToken;
    final user = _currentUser;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: switch (_screen) {
        AppScreen.guest => GuestDashboardScreen(
          key: const ValueKey('guest-dashboard'),
          onOpenLogin: () => _switchTo(AppScreen.login),
          onOpenRegister: () => _switchTo(AppScreen.register),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenMasterProfile: _openPublicMasterProfile,
          api: _api,
          sessionToken: token,
        ),
        AppScreen.guestSearch => GuestSearchScreen(
          key: const ValueKey('guest-search'),
          onOpenHome: () =>
              _switchTo(user == null ? AppScreen.guest : AppScreen.dashboard),
          onOpenLogin: () => _switchTo(AppScreen.login),
          onOpenRegister: () => _switchTo(AppScreen.register),
          onOpenMasterProfile: _openPublicMasterProfile,
          api: _api,
          sessionToken: token,
          onOpenBooking: user == null ? null : _openBookingForMaster,
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onOpenFavorites: _openFavorites,
          onOpenMessages: _openMessagesRoute,
          onOpenMyProfile: () => _switchTo(AppScreen.myProfile),
          isAuthenticated: user != null,
          currentUsername: user?.username,
          currentUserRole: user?.role,
          userName: _displayNameFor(user),
          initialFilters: _guestSearchFilters,
          onFiltersChanged: _handleGuestSearchFiltersChanged,
        ),
        AppScreen.guestMasterProfile => GuestMasterProfileScreen(
          key: const ValueKey('guest-master-profile'),
          api: _api,
          sessionToken: token,
          publicUsername: _selectedPublicMasterUsername,
          onOpenHome: () =>
              _switchTo(user == null ? AppScreen.guest : AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenLogin: user == null
              ? () => _switchTo(AppScreen.login)
              : () => _openBooking(),
          onOpenBooking: user == null
              ? null
              : (serviceId) => _openBooking(serviceId),
          onOpenRegister: () => _switchTo(AppScreen.register),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onOpenFavorites: _openFavorites,
          onOpenChat: _openChatWithUser,
          onOpenMyProfile: () => _switchTo(AppScreen.myProfile),
          isAuthenticated: user != null,
          userName: _displayNameFor(user),
        ),
        AppScreen.myProfile =>
          user?.role == 'master'
              ? GuestMasterProfileScreen(
                  key: const ValueKey('my-master-profile'),
                  api: _api,
                  sessionToken: token,
                  onOpenHome: () => _switchTo(AppScreen.dashboard),
                  onOpenSearch: () => _switchTo(AppScreen.guestSearch),
                  onOpenLogin: () => _switchTo(AppScreen.profileSettings),
                  onOpenRegister: () => _switchTo(AppScreen.register),
                  onOpenRecommendations: () =>
                      _showMockRoute('Лента рекомендаций'),
                  onOpenFavorites: _openFavorites,
                  onOpenChat: _openChatWithUser,
                  onOpenMyProfile: () => _switchTo(AppScreen.myProfile),
                  onOpenProfileSettings: () =>
                      _switchTo(AppScreen.profileSettings),
                  isAuthenticated: true,
                  isOwnProfile: true,
                  profile: _currentProfile,
                  masterSettings: _currentMasterSettings,
                  services: _currentMasterServices,
                  showFullNameInOwnProfile: _showProfileFullName,
                  showCityInOwnProfile: _showProfileCity,
                  userName: _displayNameFor(user),
                )
              : ClientProfileScreen(
                  key: const ValueKey('my-client-profile'),
                  onOpenHome: () => _switchTo(AppScreen.dashboard),
                  onOpenSearch: () => _switchTo(AppScreen.guestSearch),
                  onOpenRecommendations: () =>
                      _showMockRoute('Лента рекомендаций'),
                  onOpenMyProfile: () => _switchTo(AppScreen.myProfile),
                  onOpenMessages: _openMessagesRoute,
                  onOpenProfileSettings: () =>
                      _switchTo(AppScreen.profileSettings),
                  userName: _displayNameFor(user),
                  showFullName: _showProfileFullName,
                  showCity: _showProfileCity,
                  profile: _currentProfile,
                ),
        AppScreen.userProfile => ClientProfileScreen(
          key: ValueKey(
            'user-profile-${_selectedUserProfileUsername ?? 'unknown'}',
          ),
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenRecommendations: () =>
              _showMockRoute('Р›РµРЅС‚Р° СЂРµРєРѕРјРµРЅРґР°С†РёР№'),
          onOpenMyProfile: () => _switchTo(AppScreen.myProfile),
          onOpenMessages: _openMessagesRoute,
          onOpenProfileSettings: () => _switchTo(AppScreen.myProfile),
          userName: _selectedUserProfileUsername ?? 'user',
          publicProfile: _selectedUserProfile,
          errorText: _selectedUserProfileError,
          canEdit: false,
        ),
        AppScreen.login => LoginScreen(
          key: const ValueKey('login'),
          errorText: _globalError,
          successText: _loginNotice,
          onLogin: (email, password) async {
            setState(() {
              _loginNotice = null;
            });
            await _runAction(action: () => _handleLogin(email, password));
          },
          onOpenRegister: () => _switchTo(AppScreen.register),
        ),
        AppScreen.register => RegisterScreen(
          key: const ValueKey('register'),
          api: _api,
          errorText: _globalError,
          onRegister: (payload) async {
            await _runAction(action: () => _handleRegistration(payload));
          },
          onOpenLogin: () => _switchTo(AppScreen.login),
        ),
        AppScreen.dashboard => DashboardScreen(
          key: const ValueKey('dashboard'),
          user: user,
          api: _api,
          sessionToken: token,
          onLogout: _handleLogout,
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenMasterProfile: _openPublicMasterProfile,
          onOpenMyProfile: () => _switchTo(AppScreen.myProfile),
          onOpenFavorites: _openFavorites,
        ),
        AppScreen.favorites => FavoritesScreen(
          key: const ValueKey('favorites'),
          user: user,
          userName: _displayNameFor(user),
          api: _api,
          sessionToken: token,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenMessages: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenMasterProfile: _openPublicMasterProfile,
        ),
        AppScreen.appointments => AppointmentsScreen(
          key: const ValueKey('appointments'),
          user: user,
          userName: _displayNameFor(user),
          api: _api,
          sessionToken: token,
          onCountsChanged: _handleClientAppointmentCountsChanged,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenAccountProfile: _openAccountProfile,
          onOpenRecommendationApproval: (id) =>
              _openMockRoute(AppScreen.recommendationApproval, id),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          approvedRecommendationIds: _approvedRecommendationIds,
          approvedRecommendationJournalIds: _approvedRecommendationJournalIds,
        ),
        AppScreen.profileSettings => ServicesPricesScreen(
          key: const ValueKey('profile-settings'),
          user: user,
          userName: _displayNameFor(user),
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onLogout: () => _handleLogout(AppScreen.login),
          api: _api,
          sessionToken: token,
          initialMasterSettings: _currentMasterSettings,
          initialServices: _currentMasterServices,
          initialShowFullName: _showProfileFullName,
          initialShowCity: _showProfileCity,
          onProfileChanged: _handleProfileChanged,
          onMasterSettingsChanged: _handleMasterSettingsChanged,
          onServicesChanged: _handleMasterServicesChanged,
          onShowFullNameChanged: (value) {
            setState(() => _showProfileFullName = value);
          },
          onShowCityChanged: (value) {
            setState(() => _showProfileCity = value);
          },
          initialSection: SettingsSection.profile,
        ),
        AppScreen.recommendationApproval => RecommendationApprovalScreen(
          key: ValueKey('recommendation-approval-${_mockRouteId ?? 'mock'}'),
          user: user,
          userName: _displayNameFor(user),
          appointmentId: _mockRouteId ?? 'mock',
          api: _api,
          sessionToken: token,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onApproved: (id, journalId) {
            setState(() {
              _approvedRecommendationIds.add(id);
              final value = journalId.trim();
              if (value.isNotEmpty) {
                _approvedRecommendationJournalIds[id] = value;
              }
            });
          },
        ),
        AppScreen.recommendationBuilder => RecommendationBuilderScreen(
          key: ValueKey('recommendation-builder-${_mockRouteId ?? 'mock'}'),
          user: user,
          userName: _displayNameFor(user),
          appointmentId: _mockRouteId ?? 'mock',
          api: _api,
          sessionToken: token,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onOpenAccountProfile: _openAccountProfile,
        ),
        AppScreen.masterAppointments => MasterAppointmentsScreen(
          key: const ValueKey('master-appointments'),
          user: user,
          userName: _displayNameFor(user),
          api: _api,
          sessionToken: token,
          onCountsChanged: _handleMasterAppointmentCountsChanged,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: (id) =>
              _openJournalNavigationRoute(id, asMaster: true),
          onOpenOwnCareJournal: () => _openClientCareJournalRoute('journal'),
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onOpenAccountProfile: _openAccountProfile,
          onCreateRecommendations: (id) =>
              _openMockRoute(AppScreen.recommendationBuilder, id),
        ),
        AppScreen.booking => BookingServiceScreen(
          key: ValueKey('booking-service-${_bookingServiceId ?? 'select'}'),
          user: user,
          userName: _displayNameFor(user),
          api: _api,
          sessionToken: token,
          masterUsername: _selectedPublicMasterUsername,
          initialServiceId: _bookingServiceId,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onBackToProfile: () => _switchTo(AppScreen.guestMasterProfile),
        ),
        AppScreen.chat => ChatScreen(
          key: ValueKey('chat-${_selectedChatPeerUserId ?? 'list'}'),
          user: user,
          userName: _displayNameFor(user),
          api: _api,
          sessionToken: token,
          initialPeerUserId: _selectedChatPeerUserId,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenFavorites: _openFavorites,
        ),
        AppScreen.myCareJournals => MyCareJournalsScreen(
          key: const ValueKey('my-care-journals'),
          user: user,
          userName: _displayNameFor(user),
          api: _api,
          sessionToken: token,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
        ),
        AppScreen.appointmentCareJournals => AppointmentCareJournalsScreen(
          key: ValueKey(
            'appointment-care-journals-${_selectedAppointmentJournalsAppointmentId ?? 'none'}',
          ),
          user: user,
          userName: _displayNameFor(user),
          appointmentId: _selectedAppointmentJournalsAppointmentId ?? '',
          items: _selectedAppointmentJournals,
          isLoading: _loadingAppointmentJournals,
          asMaster: _selectedAppointmentJournalsAsMaster,
          errorText: _appointmentJournalsError,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenJournal: (id) => _openCareJournalRoute(
            id,
            asMaster: _selectedAppointmentJournalsAsMaster,
          ),
          onOpenOwnCareJournal: () => _openClientCareJournalRoute('journal'),
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onBack: () => _selectedAppointmentJournalsAsMaster
              ? _switchTo(AppScreen.masterAppointments)
              : _switchTo(AppScreen.appointments),
          onRetry: _retryAppointmentJournalsRoute,
          onAutoRefresh: _autoRefreshAppointmentJournalsRoute,
        ),
        AppScreen.careJournal => CareJournalScreen(
          key: ValueKey('care-journal-${_mockRouteId ?? 'mock'}'),
          user: user,
          userName: _displayNameFor(user),
          journalId: _selectedJournalId ?? _mockRouteId ?? 'mock',
          journalAsMaster: _selectedJournalAsMaster,
          api: _api,
          sessionToken: token,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenCareJournalAsMaster: (id) =>
              _openCareJournalRoute(id, asMaster: true),
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onOpenStepConfirmation: _openCareStepConfirmationRoute,
          completedStepIds: _completedCareStepIds,
          onStepConfirmed: (id) {
            setState(() => _completedCareStepIds.add(id));
          },
          onBack: () => _selectedJournalAsMaster
              ? _switchTo(AppScreen.clientJournals)
              : _switchTo(AppScreen.myCareJournals),
        ),
        AppScreen.careStepConfirmation => CareStepConfirmationScreen(
          key: ValueKey('care-step-${_mockRouteId ?? 'day-3'}'),
          user: user,
          userName: _displayNameFor(user),
          journalId: _selectedJournalId ?? _mockRouteId ?? 'journal',
          stepId: _selectedCareStepId ?? _mockRouteId ?? 'day-3',
          api: _api,
          sessionToken: token,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          completedStepIds: _completedCareStepIds,
          onStepConfirmed: (id) {
            setState(() => _completedCareStepIds.add(id));
          },
          onBack: () => _openCareJournalRoute(
            _selectedJournalId ?? _mockRouteId ?? 'journal',
            asMaster: _selectedJournalAsMaster,
          ),
        ),
        AppScreen.clientJournals => ClientJournalsScreen(
          key: ValueKey('client-journals-${_mockRouteId ?? 'all'}'),
          user: user,
          userName: _displayNameFor(user),
          selectedJournalId: null,
          api: _api,
          sessionToken: token,
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: (id) => _openCareJournalRoute(id, asMaster: true),
          onOpenOwnCareJournal: () => _openClientCareJournalRoute('journal'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onBack: () => _switchTo(AppScreen.masterAppointments),
        ),
        AppScreen.servicesPrices => ServicesPricesScreen(
          key: const ValueKey('services-prices'),
          user: user,
          userName: _displayNameFor(user),
          onOpenHome: () => _switchTo(AppScreen.dashboard),
          onOpenSearch: () => _switchTo(AppScreen.guestSearch),
          onOpenAppointments: () => _switchTo(AppScreen.appointments),
          onOpenMasterAppointments: () =>
              _switchTo(AppScreen.masterAppointments),
          onOpenChat: _openChatWithUser,
          onOpenCareJournal: _openClientCareJournalRoute,
          onOpenClientJournals: () =>
              _openMockRoute(AppScreen.clientJournals, 'all'),
          onOpenServicesPrices: () => _switchTo(AppScreen.servicesPrices),
          onOpenProfile: () => _switchTo(AppScreen.myProfile),
          onOpenRecommendations: () => _showMockRoute('Лента рекомендаций'),
          onLogout: () => _handleLogout(AppScreen.login),
          api: _api,
          sessionToken: token,
          initialMasterSettings: _currentMasterSettings,
          initialServices: _currentMasterServices,
          initialSection: SettingsSection.servicesPrices,
          initialShowFullName: _showProfileFullName,
          initialShowCity: _showProfileCity,
          onProfileChanged: _handleProfileChanged,
          onMasterSettingsChanged: _handleMasterSettingsChanged,
          onServicesChanged: _handleMasterServicesChanged,
          onShowFullNameChanged: (value) {
            setState(() => _showProfileFullName = value);
          },
          onShowCityChanged: (value) {
            setState(() => _showProfileCity = value);
          },
        ),
      },
    );
  }

  Future<void> _runAction({required Future<void> Function() action}) async {
    try {
      await action();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _globalError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _globalError = 'Не удалось выполнить запрос. Повторите попытку позже.';
      });
    }
  }

  String _displayNameFor(AuthUser? user) {
    final username = user?.username.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    return 'Артём';
  }

  void _showMockRoute(String label) {
    if (label.trim() == 'Избранное') {
      _openFavorites();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: экран будет подключён следующим шагом'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class RegisterSuccessScreen extends StatelessWidget {
  const RegisterSuccessScreen({
    super.key,
    required this.result,
    required this.onGoToLogin,
    required this.onRegisterAnother,
  });

  final RegistrationResponse? result;
  final VoidCallback onGoToLogin;
  final VoidCallback onRegisterAnother;

  @override
  Widget build(BuildContext context) {
    final item = result;
    if (item == null) {
      return const Center(child: Text('Нет данных о регистрации.'));
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Регистрация прошла успешно',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Профиль сохранен в базе данных, а ключевая пара создана для дальнейшей работы с защищенными записями.',
          style: TextStyle(color: authHint, height: 1.5),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 320,
              child: _InfoCard(
                title: 'Данные профиля',
                items: {
                  'ID пользователя': item.userId,
                  'Username': item.username,
                  'Email': item.email,
                  'Роль': item.role,
                },
              ),
            ),
            SizedBox(width: 320, child: const _ProtectedJournalKeyCard()),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: onGoToLogin,
              child: const Text('Перейти ко входу'),
            ),
            OutlinedButton(
              onPressed: onRegisterAnother,
              child: const Text('Создать еще один аккаунт'),
            ),
          ],
        ),
      ],
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    required this.api,
    required this.sessionToken,
    required this.onLogout,
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
  });

  final AuthUser? user;
  final InkConnectApiClient api;
  final String? sessionToken;
  final Future<void> Function() onLogout;
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

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return AuthenticatedDashboardScreen(
      user: widget.user,
      api: widget.api,
      sessionToken: widget.sessionToken,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: widget.onOpenAppointments,
      onOpenMasterAppointments: widget.onOpenMasterAppointments,
      onOpenChat: widget.onOpenChat,
      onOpenCareJournal: widget.onOpenCareJournal,
      onOpenClientJournals: widget.onOpenClientJournals,
      onOpenServicesPrices: widget.onOpenServicesPrices,
      onOpenMasterProfile: widget.onOpenMasterProfile,
      onOpenMyProfile: widget.onOpenMyProfile,
      onOpenFavorites: widget.onOpenFavorites,
      onLogout: widget.onLogout,
    );
  }
}

class _MockRouteScreen extends StatelessWidget {
  const _MockRouteScreen({
    super.key,
    required this.title,
    required this.routeLabel,
    required this.description,
    required this.onBack,
  });

  final String title;
  final String routeLabel;
  final String description;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AuthPageCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    routeLabel,
                    style: const TextStyle(
                      color: authAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    style: const TextStyle(color: authHint, height: 1.45),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Назад к моим записям'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProtectedJournalKeyCard extends StatelessWidget {
  const _ProtectedJournalKeyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE6D8C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Защищённый журнал',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          const Text(
            'Аккаунт создан. Ключ защищённого журнала создан автоматически. Он будет использоваться системой для фиксации важных действий в журнале ухода.',
            style: TextStyle(color: authHint, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.items,
    this.monoValues = false,
  });

  final String title;
  final Map<String, String> items;
  final bool monoValues;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE6D8C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ...items.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(fontSize: 12, color: authHint),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    entry.value,
                    style: TextStyle(
                      fontFamily: monoValues ? 'Consolas' : null,
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
