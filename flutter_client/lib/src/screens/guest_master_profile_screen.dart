import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../style_options.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_site_header.dart';
import '../widgets/drop_file_area.dart';
import '../widgets/dropped_upload_file.dart';
import '../widgets/profile_image.dart';
import '../widgets/remote_or_asset_image.dart';
import 'guest_dashboard_screen.dart';

enum _MasterProfileTab { portfolio, about, reviews, services }

const String _publicMasterHandle = 'master';
const String _portfolioAllStyle = '\u0412\u0441\u0435';
const String _publicMasterFullName = 'Мария Козлова';
const String _actionsTooltip =
    '\u0414\u0435\u0439\u0441\u0442\u0432\u0438\u044f';
const String _deletePublicationLabel =
    '\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u043f\u0443\u0431\u043b\u0438\u043a\u0430\u0446\u0438\u044e';

String _profileHandle(String value) {
  final trimmed = value.trim();
  final handle = trimmed.isEmpty ? _publicMasterHandle : trimmed;
  return handle.startsWith('@') ? handle : '@$handle';
}

String _profileUsername(UserProfile? profile, String fallback) {
  final username = profile?.username.trim();
  if (username != null && username.isNotEmpty) {
    return username;
  }
  return fallback.trim().isEmpty ? _publicMasterHandle : fallback.trim();
}

String _profileFullName(UserProfile? profile) {
  if (profile == null) {
    return '';
  }
  return [
    profile.lastName.trim(),
    profile.firstName.trim(),
    profile.middleName.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
}

String _ownProfileDisplayName({
  required UserProfile? profile,
  required String fallbackUserName,
  required bool showFullName,
}) {
  final effectiveShowFullName = profile?.showFullNameInProfile ?? showFullName;
  final fullName = _profileFullName(profile);
  if (effectiveShowFullName && fullName.isNotEmpty) {
    return fullName;
  }
  if (profile == null && effectiveShowFullName) {
    return _publicMasterFullName;
  }
  return _profileHandle(_profileUsername(profile, fallbackUserName));
}

String _ownProfileHandle(UserProfile? profile, String fallbackUserName) {
  return _profileHandle(_profileUsername(profile, fallbackUserName));
}

String? _ownProfileCityLabel({
  required UserProfile? profile,
  required bool showCity,
}) {
  final effectiveShowCity = profile?.showCityInProfile ?? showCity;
  if (!effectiveShowCity) {
    return null;
  }
  final city = profile?.city.trim();
  if (city != null && city.isNotEmpty) {
    return city;
  }
  return profile == null ? 'Москва · Sakura Tattoo' : null;
}

String _masterServiceTypeLabel(String type) {
  return switch (type) {
    'consultation' => 'Консультация',
    'sketch' => 'Эскиз',
    _ => 'Сеанс',
  };
}

String _masterServiceDurationLabel(MasterServiceSettings service) {
  final hours = service.durationHours;
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

String _masterServicePriceLabel(MasterServiceSettings service) {
  final price = '${_formatRubles(service.price)} ₽';
  return service.fromPrice ? 'от $price' : price;
}

String? _masterServiceSubPrice(MasterServiceSettings service) {
  if (service.fromPrice) {
    return 'цена зависит от сложности';
  }
  if (service.useAutoPrice && service.type == 'session') {
    return 'рассчитано по настройкам мастера';
  }
  return null;
}

String _formatRubles(int value) {
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

class GuestMasterProfileScreen extends StatefulWidget {
  const GuestMasterProfileScreen({
    super.key,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenLogin,
    required this.onOpenRegister,
    this.onOpenBooking,
    this.onOpenRecommendations,
    this.onOpenFavorites,
    this.onOpenChat,
    this.onOpenMyProfile,
    this.onOpenProfileSettings,
    this.api,
    this.sessionToken,
    this.publicUsername,
    this.isAuthenticated = false,
    this.isOwnProfile = false,
    this.profile,
    this.masterSettings,
    this.services,
    this.showFullNameInOwnProfile = true,
    this.showCityInOwnProfile = true,
    this.userName = 'Артём',
  });

  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLogin;
  final VoidCallback onOpenRegister;
  final ValueChanged<String?>? onOpenBooking;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenFavorites;
  final ValueChanged<String>? onOpenChat;
  final VoidCallback? onOpenMyProfile;
  final VoidCallback? onOpenProfileSettings;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final String? publicUsername;
  final bool isAuthenticated;
  final bool isOwnProfile;
  final UserProfile? profile;
  final MasterSettings? masterSettings;
  final List<MasterServiceSettings>? services;
  final bool showFullNameInOwnProfile;
  final bool showCityInOwnProfile;
  final String userName;

  @override
  State<GuestMasterProfileScreen> createState() =>
      _GuestMasterProfileScreenState();
}

class _GuestMasterProfileScreenState extends State<GuestMasterProfileScreen> {
  _MasterProfileTab _selectedTab = _MasterProfileTab.portfolio;
  MasterProfile? _publicProfile;
  String? _loadedPublicUsername;
  bool _publicProfileLoading = false;
  bool _publicProfileIsFavorite = false;
  bool _favoriteUpdating = false;
  String? _publicProfileError;
  List<MasterPublication>? _publications;
  bool _publicationsLoading = false;
  String? _publicationsError;
  String? _loadedPublicationsUsername;

  @override
  void initState() {
    super.initState();
    _loadPublicProfile();
    _loadPublications();
  }

  @override
  void didUpdateWidget(covariant GuestMasterProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.publicUsername != widget.publicUsername ||
        oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.isOwnProfile != widget.isOwnProfile ||
        oldWidget.profile?.username != widget.profile?.username ||
        oldWidget.userName != widget.userName) {
      _loadPublicProfile();
      _loadPublications(force: true);
    }
  }

  Future<void> _loadPublicProfile() async {
    if (widget.isOwnProfile) {
      return;
    }
    final api = widget.api;
    final username = widget.publicUsername?.trim();
    if (api == null || username == null || username.isEmpty) {
      setState(() {
        _publicProfile = null;
        _loadedPublicUsername = null;
        _publicProfileLoading = false;
        _publicProfileError =
            'Не удалось загрузить профиль мастера: не передан real username или API.';
      });
      return;
    }
    if (_loadedPublicUsername == username && _publicProfile != null) {
      return;
    }

    setState(() {
      _publicProfileLoading = true;
      _publicProfileIsFavorite = false;
      _publicProfileError = null;
    });
    try {
      final profile = await api.publicMasterProfile(username);
      final isFavorite = await _isFavoriteProfile(api, profile.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _publicProfile = profile;
        _loadedPublicUsername = username;
        _publicProfileIsFavorite = isFavorite;
        _publicProfileLoading = false;
        _publicProfileError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _publicProfile = null;
        _loadedPublicUsername = null;
        _publicProfileLoading = false;
        _publicProfileError = 'Не удалось загрузить профиль мастера: $error';
      });
    }
  }

  String _publicationUsername() {
    if (widget.isOwnProfile) {
      return _profileUsername(widget.profile, widget.userName);
    }
    final publicUsername = widget.publicUsername?.trim();
    if (publicUsername != null && publicUsername.isNotEmpty) {
      return publicUsername;
    }
    final loadedUsername = _publicProfile?.username.trim();
    return loadedUsername == null ? '' : loadedUsername;
  }

  Future<void> _loadPublications({bool force = false}) async {
    final api = widget.api;
    final username = _publicationUsername().trim();
    if (api == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _publications = null;
        _publicationsLoading = false;
        _publicationsError = null;
        _loadedPublicationsUsername = null;
      });
      return;
    }
    if (!force &&
        _loadedPublicationsUsername == username &&
        _publications != null) {
      return;
    }

    setState(() {
      _publicationsLoading = true;
      _publicationsError = null;
    });
    try {
      final items = await api.masterPublications(username);
      if (!mounted) {
        return;
      }
      setState(() {
        _publications = items;
        _loadedPublicationsUsername = username;
        _publicationsLoading = false;
        _publicationsError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _publications = null;
        _loadedPublicationsUsername = null;
        _publicationsLoading = false;
        _publicationsError = '$error';
      });
    }
  }

  List<_PortfolioImageData> get _portfolioItems {
    final publications = _publications;
    if (publications == null || publications.isEmpty) {
      return const <_PortfolioImageData>[];
    }
    final items = <_PortfolioImageData>[];
    for (var index = 0; index < publications.length; index += 1) {
      final item = _portfolioItemFromPublication(publications[index], index);
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  _PortfolioAuthorData get _portfolioAuthor {
    if (widget.isOwnProfile) {
      final fullName = _profileFullName(widget.profile);
      final displayName = fullName.isNotEmpty
          ? fullName
          : _ownProfileDisplayName(
              profile: widget.profile,
              fallbackUserName: widget.userName,
              showFullName: widget.showFullNameInOwnProfile,
            );
      return _PortfolioAuthorData(
        handle: _ownProfileHandle(widget.profile, widget.userName),
        displayName: displayName,
        avatarUrl: widget.profile?.avatarUrl.trim() ?? '',
        subtitle: 'Ваш профиль · InkConnect',
      );
    }

    final publicProfile = _publicProfile;
    final username = publicProfile?.username.trim();
    final handle = _profileHandle(
      username != null && username.isNotEmpty ? username : _publicationUsername(),
    );
    final displayName = [
      publicProfile?.displayName.trim() ?? '',
      publicProfile?.fullName.trim() ?? '',
      publicProfile?.studioName.trim() ?? '',
      handle,
    ].firstWhere((value) => value.isNotEmpty, orElse: () => handle);
    final subtitleParts = <String>[
      publicProfile?.category.trim() ?? '',
      publicProfile?.city.trim() ?? '',
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return _PortfolioAuthorData(
      handle: handle,
      displayName: displayName,
      avatarUrl: publicProfile?.avatarUrl.trim() ?? '',
      subtitle: subtitleParts.isEmpty
          ? 'Тату-мастер · InkConnect'
          : '${subtitleParts.join(' · ')} · InkConnect',
    );
  }

  Future<bool> _isFavoriteProfile(
    InkConnectApiClient api,
    String masterId,
  ) async {
    final token = widget.sessionToken;
    if (!widget.isAuthenticated ||
        token == null ||
        token.isEmpty ||
        masterId.trim().isEmpty) {
      return false;
    }
    try {
      final favorites = await api.getFavoriteMasters(sessionToken: token);
      return favorites.any((master) => master.id == masterId);
    } catch (_) {
      return false;
    }
  }

  Future<void> _toggleProfileFavorite() async {
    final api = widget.api;
    final token = widget.sessionToken;
    final profile = _publicProfile;
    if (api == null || token == null || token.isEmpty) {
      _showSnackBar('Войдите, чтобы добавлять мастеров в избранное');
      return;
    }
    if (profile == null || profile.id.trim().isEmpty || _favoriteUpdating) {
      return;
    }

    final nextValue = !_publicProfileIsFavorite;
    setState(() {
      _publicProfileIsFavorite = nextValue;
      _favoriteUpdating = true;
    });

    try {
      if (nextValue) {
        await api.addFavoriteMaster(sessionToken: token, masterId: profile.id);
        _showSnackBar('Добавлено в избранное');
      } else {
        await api.removeFavoriteMaster(
          sessionToken: token,
          masterId: profile.id,
        );
        _showSnackBar('Удалено из избранного');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _publicProfileIsFavorite = !nextValue);
        _showSnackBar('Не удалось обновить избранное');
      }
    } finally {
      if (mounted) {
        setState(() => _favoriteUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 980;
    final ownProfile = widget.isOwnProfile ? widget.profile : null;
    final ownMasterSettings = widget.isOwnProfile
        ? widget.masterSettings
        : null;
    final ownServices = widget.isOwnProfile ? widget.services : null;
    final publicProfile = widget.isOwnProfile ? null : _publicProfile;
    final publicTitle = publicProfile?.displayName.trim().isNotEmpty == true
        ? publicProfile!.displayName.trim()
        : _profileHandle(widget.publicUsername ?? _publicMasterHandle);
    final publicBlocked =
        !widget.isOwnProfile &&
        (_publicProfileLoading ||
            _publicProfileError != null ||
            publicProfile == null);

    return Scaffold(
      backgroundColor: GuestDashboardTheme.background,
      bottomNavigationBar: isDesktop
          ? null
          : widget.isAuthenticated
          ? AuthenticatedMobileNavigation(
              activeItem: AuthenticatedMobileNavItem.search,
              onOpenHome: widget.onOpenHome,
              onOpenSearch: widget.onOpenSearch,
              onOpenMessages: () {
                final handler = widget.onOpenChat;
                if (handler != null) {
                  handler('messages');
                  return;
                }
                _showMockAction('Сообщения');
              },
              onOpenRecommendations:
                  widget.onOpenRecommendations ?? widget.onOpenSearch,
              onOpenCareJournal: () => _showMockAction('Журнал ухода'),
            )
          : _MobileProfileNav(
              onOpenHome: widget.onOpenHome,
              onOpenSearch: widget.onOpenSearch,
              onOpenRecommendations: widget.onOpenRecommendations,
            ),
      body: Column(
        children: [
          _ProfileHeader(
            isDesktop: isDesktop,
            onOpenHome: widget.onOpenHome,
            onOpenSearch: widget.onOpenSearch,
            onOpenLogin: widget.onOpenLogin,
            onOpenRecommendations: widget.onOpenRecommendations,
            onOpenFavorites: widget.onOpenFavorites,
            onOpenMyProfile: widget.onOpenMyProfile,
            isAuthenticated: widget.isAuthenticated,
            userName: widget.userName,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 24 : 16,
                24,
                isDesktop ? 24 : 16,
                isDesktop
                    ? 32
                    : widget.isAuthenticated
                    ? 96
                    : 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1131.2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Breadcrumbs(
                        onOpenHome: widget.onOpenHome,
                        onOpenSearch: widget.onOpenSearch,
                        currentLabel: widget.isOwnProfile
                            ? 'Мой профиль'
                            : publicTitle,
                        showSearchLink: !widget.isOwnProfile,
                      ),
                      const SizedBox(height: 20),
                      if (publicBlocked)
                        _PublicProfileState(
                          loading: _publicProfileLoading,
                          message:
                              _publicProfileError ??
                              'Профиль мастера не найден в backend.',
                          onRetry: _loadPublicProfile,
                        )
                      else if (isDesktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 300,
                              child: _MasterProfileSidebar(
                                onOpenBooking: _openBooking,
                                onOpenChat: _openChat,
                                onAddPublication: _openAddPublication,
                                onEditProfile: _openProfileSettings,
                                isOwnProfile: widget.isOwnProfile,
                                showFullName: widget.showFullNameInOwnProfile,
                                showCity: widget.showCityInOwnProfile,
                                userName: widget.userName,
                                profile: ownProfile,
                                masterSettings: ownMasterSettings,
                                publicProfile: publicProfile,
                                isFavorite: _publicProfileIsFavorite,
                                favoriteUpdating: _favoriteUpdating,
                                onToggleFavorite: _toggleProfileFavorite,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _MasterProfileContent(
                                selectedTab: _selectedTab,
                                onTabSelected: _selectTab,
                                onOpenBooking: _openBooking,
                                onOpenPortfolioPost: _openPortfolioFeed,
                                isOwnProfile: widget.isOwnProfile,
                                profile: ownProfile,
                                masterSettings: ownMasterSettings,
                                services: ownServices,
                                publicProfile: publicProfile,
                                portfolioItems: _portfolioItems,
                                publicationsLoading: _publicationsLoading,
                                publicationsError: _publicationsError,
                                onRetryPublications: () =>
                                    _loadPublications(force: true),
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MasterProfileSidebar(
                              onOpenBooking: _openBooking,
                              onOpenChat: _openChat,
                              onAddPublication: _openAddPublication,
                              onEditProfile: _openProfileSettings,
                              isOwnProfile: widget.isOwnProfile,
                              showFullName: widget.showFullNameInOwnProfile,
                              showCity: widget.showCityInOwnProfile,
                              userName: widget.userName,
                              profile: ownProfile,
                              masterSettings: ownMasterSettings,
                              publicProfile: publicProfile,
                              isFavorite: _publicProfileIsFavorite,
                              favoriteUpdating: _favoriteUpdating,
                              onToggleFavorite: _toggleProfileFavorite,
                            ),
                            const SizedBox(height: 24),
                            _MasterProfileContent(
                              selectedTab: _selectedTab,
                              onTabSelected: _selectTab,
                              onOpenBooking: _openBooking,
                              onOpenPortfolioPost: _openPortfolioFeed,
                              isOwnProfile: widget.isOwnProfile,
                              profile: ownProfile,
                              masterSettings: ownMasterSettings,
                              services: ownServices,
                              publicProfile: publicProfile,
                              portfolioItems: _portfolioItems,
                              publicationsLoading: _publicationsLoading,
                              publicationsError: _publicationsError,
                              onRetryPublications: () =>
                                  _loadPublications(force: true),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectTab(_MasterProfileTab tab) {
    setState(() => _selectedTab = tab);
  }

  void _openBooking([String? serviceId]) {
    final handler = widget.onOpenBooking;
    if (handler != null) {
      handler(serviceId);
      return;
    }
    widget.onOpenLogin();
  }

  void _openChat() {
    final targetId = _publicProfile?.id.trim() ?? '';
    final handler = widget.onOpenChat;
    if (handler != null && targetId.isNotEmpty) {
      handler(targetId);
      return;
    }
    widget.onOpenLogin();
  }

  Future<void> _openPortfolioFeed(int initialIndex) async {
    final isDesktop = MediaQuery.sizeOf(context).width >= 820;
    final items = _portfolioItems;
    if (items.isEmpty) {
      return;
    }
    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
    final feed = _PortfolioFeedView(
      items: items,
      initialIndex: safeInitialIndex,
      author: _portfolioAuthor,
      userName: widget.userName,
      isOwnProfile: widget.isOwnProfile,
      onClose: () => Navigator.of(context).pop(),
      onDeletePublication: _deletePublication,
    );

    if (isDesktop) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: feed,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => feed,
    );
  }

  void _showMockAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: экран будет подключён следующим шагом'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openAddPublication() async {
    final isDesktop = MediaQuery.sizeOf(context).width >= 820;
    final sheet = _AddPublicationSheet(
      isDesktop: isDesktop,
      onPublish: _createPublication,
    );
    final published = isDesktop
        ? await showDialog<bool>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.62),
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              child: sheet,
            ),
          )
        : await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            enableDrag: false,
            backgroundColor: Colors.transparent,
            builder: (context) => sheet,
          );

    if (published == true && mounted) {
      await _loadPublications(force: true);
      _showSnackBar(
        '\u041f\u0443\u0431\u043b\u0438\u043a\u0430\u0446\u0438\u044f \u043e\u043f\u0443\u0431\u043b\u0438\u043a\u043e\u0432\u0430\u043d\u0430',
      );
    }
  }

  Future<void> _createPublication(_PublicationDraft draft) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      throw const ApiException(
        '\u0412\u043e\u0439\u0434\u0438\u0442\u0435, \u0447\u0442\u043e\u0431\u044b \u043e\u043f\u0443\u0431\u043b\u0438\u043a\u043e\u0432\u0430\u0442\u044c \u0440\u0430\u0431\u043e\u0442\u0443.',
      );
    }
    await api.createMasterPublication(
      sessionToken: token,
      description: draft.description,
      styles: draft.styles,
      commentsDisabled: draft.commentsDisabled,
      photos: draft.photos
          .map(
            (photo) => PublicationPhotoUploadPayload(
              filename: photo.name,
              bytes: photo.bytes,
            ),
          )
          .toList(),
    );
  }

  Future<bool> _deletePublication(_PortfolioImageData item) async {
    final api = widget.api;
    final token = widget.sessionToken;
    final publicationId = item.publicationId.trim();
    if (api == null || token == null || token.isEmpty || publicationId.isEmpty) {
      _showSnackBar(
        '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0443\u0434\u0430\u043b\u0438\u0442\u044c \u043f\u0443\u0431\u043b\u0438\u043a\u0430\u0446\u0438\u044e',
      );
      return false;
    }
    try {
      await api.deleteMasterPublication(
        sessionToken: token,
        publicationId: publicationId,
      );
      if (mounted) {
        _showSnackBar(
          '\u041f\u0443\u0431\u043b\u0438\u043a\u0430\u0446\u0438\u044f \u0443\u0434\u0430\u043b\u0435\u043d\u0430',
        );
        await _loadPublications(force: true);
      }
      return true;
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0443\u0434\u0430\u043b\u0438\u0442\u044c: $error',
        );
      }
      return false;
    }
  }

  void _openProfileSettings() {
    final handler = widget.onOpenProfileSettings;
    if (handler != null) {
      handler();
      return;
    }
    _showMockAction('Настройки профиля');
  }
}

class _PublicProfileState extends StatelessWidget {
  const _PublicProfileState({
    required this.loading,
    required this.message,
    required this.onRetry,
  });

  final bool loading;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 16),
          ],
          Text(
            loading ? 'Профиль мастера загружается...' : message,
            style: const TextStyle(
              color: Color(0xFF355072),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!loading) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить'),
            ),
          ],
        ],
      ),
    );
  }
}

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({
    super.key,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenProfileSettings,
    this.onOpenRecommendations,
    this.onOpenFavorites,
    this.onOpenMyProfile,
    this.onOpenMessages,
    this.userName = 'anna_smirnova',
    this.showFullName = true,
    this.showCity = true,
    this.profile,
    this.publicProfile,
    this.errorText,
    this.canEdit = true,
  });

  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenProfileSettings;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenMyProfile;
  final VoidCallback? onOpenMessages;
  final String userName;
  final bool showFullName;
  final bool showCity;
  final UserProfile? profile;
  final PublicUserProfile? publicProfile;
  final String? errorText;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 980;

    return Scaffold(
      backgroundColor: GuestDashboardTheme.background,
      bottomNavigationBar: isDesktop
          ? null
          : AuthenticatedMobileNavigation(
              activeItem: AuthenticatedMobileNavItem.home,
              onOpenHome: onOpenHome,
              onOpenSearch: onOpenSearch,
              onOpenMessages:
                  onOpenMessages ?? () => _showMockAction(context, 'Сообщения'),
              onOpenRecommendations: onOpenRecommendations ?? onOpenSearch,
              onOpenCareJournal: () => _showMockAction(context, 'Журнал ухода'),
            ),
      body: Column(
        children: [
          _ProfileHeader(
            isDesktop: isDesktop,
            onOpenHome: onOpenHome,
            onOpenSearch: onOpenSearch,
            onOpenLogin: onOpenProfileSettings,
            onOpenRecommendations: onOpenRecommendations,
            onOpenFavorites: onOpenFavorites,
            onOpenMyProfile: onOpenMyProfile,
            isAuthenticated: true,
            userName: userName,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 24 : 16,
                24,
                isDesktop ? 24 : 16,
                isDesktop ? 32 : 96,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1131.2),
                  child: _ClientProfileCard(
                    userName: userName,
                    showFullName: showFullName,
                    showCity: showCity,
                    profile: profile,
                    publicProfile: publicProfile,
                    errorText: errorText,
                    canEdit: canEdit,
                    onEditProfile: onOpenProfileSettings,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMockAction(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: экран будет подключён следующим шагом'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ClientProfileCard extends StatelessWidget {
  const _ClientProfileCard({
    required this.userName,
    required this.showFullName,
    required this.showCity,
    required this.profile,
    required this.publicProfile,
    required this.errorText,
    required this.canEdit,
    required this.onEditProfile,
  });

  final String userName;
  final bool showFullName;
  final bool showCity;
  final UserProfile? profile;
  final PublicUserProfile? publicProfile;
  final String? errorText;
  final bool canEdit;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 640;
    final avatarSize = isMobile ? 156.0 : 210.0;
    final horizontalPadding = isMobile ? 22.0 : 36.0;
    final topPadding = isMobile ? 34.0 : 32.0;
    final bottomPadding = isMobile ? 28.0 : 26.0;
    final titleSize = isMobile ? 30.0 : 29.0;
    final metaSize = isMobile ? 20.0 : 15.0;
    final aboutTitleSize = isMobile ? 18.0 : 14.0;
    final aboutTextSize = isMobile ? 18.0 : 14.0;
    final bodyMaxWidth = isMobile ? 440.0 : 330.0;
    final dividerWidth = isMobile ? 288.0 : 216.0;
    final shortDividerWidth = isMobile ? 312.0 : 234.0;
    final buttonWidth = isMobile ? double.infinity : 252.0;
    final isPublicView = !canEdit;
    final avatarUrl = isPublicView
        ? publicProfile?.avatarUrl.trim() ?? ''
        : profile?.avatarUrl.trim() ?? '';
    final handle = _profileHandle(publicProfile?.username ?? userName);
    final displayName = publicProfile?.displayName.trim().isNotEmpty == true
        ? publicProfile!.displayName.trim()
        : isPublicView
        ? handle
        : showFullName
        ? 'Анна Смирнова'
        : handle;
    final cityLabel = publicProfile == null
        ? (showCity ? 'Москва, Россия' : '')
        : publicProfile!.city.trim();
    final aboutText = errorText?.trim().isNotEmpty == true
        ? errorText!.trim()
        : publicProfile == null
        ? isPublicView
              ? 'Профиль загружается или недоступен.'
              : 'Люблю японскую татуировку, графику и тонкие линии.\n'
                    'Ищу мастеров, которые делают стильные\n'
                    'и аккуратные работы.'
        : publicProfile!.bio.trim().isEmpty
        ? 'Профиль пока не заполнен.'
        : publicProfile!.bio.trim();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipOval(
            child: ProfileImage(
              avatarUrl: avatarUrl,
              letterFallback: displayName,
              width: avatarSize,
              height: avatarSize,
              fit: BoxFit.cover,
              circular: true,
              backgroundColor: GuestDashboardTheme.accent,
              letterStyle: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 52 : 64,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(height: isMobile ? 24 : 22),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF101828),
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              height: 1.08,
            ),
          ),
          SizedBox(height: isMobile ? 16 : 12),
          Text(
            handle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF344054),
              fontSize: metaSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (cityLabel.isNotEmpty) ...[
            SizedBox(height: isMobile ? 20 : 15),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: isMobile ? 22 : 17,
                  color: const Color(0xFF182235),
                ),
                const SizedBox(width: 8),
                Text(
                  cityLabel,
                  style: TextStyle(
                    color: const Color(0xFF344054),
                    fontSize: metaSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: isMobile ? 30 : 22),
          _ClientProfileDivider(width: dividerWidth),
          SizedBox(height: isMobile ? 28 : 21),
          Text(
            'О себе',
            style: TextStyle(
              color: const Color(0xFF101828),
              fontSize: aboutTitleSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: isMobile ? 12 : 9),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bodyMaxWidth),
            child: Text(
              aboutText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF344054),
                fontSize: aboutTextSize,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: isMobile ? 22 : 16),
          _ClientProfileDivider(width: shortDividerWidth),
          SizedBox(height: isMobile ? 14 : 10),
          if (canEdit)
            SizedBox(
              width: buttonWidth,
              child: OutlinedButton(
                onPressed: onEditProfile,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF182235),
                  side: const BorderSide(color: Color(0xFFD6DAE1)),
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 15 : 11),
                  textStyle: TextStyle(
                    fontSize: isMobile ? 16 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('Редактировать профиль'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClientProfileDivider extends StatelessWidget {
  const _ClientProfileDivider({this.width = 288});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(width: width, height: 1, color: const Color(0xFFDDE1E7));
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.isDesktop,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenLogin,
    this.onOpenRecommendations,
    this.onOpenFavorites,
    this.onOpenMyProfile,
    this.isAuthenticated = false,
    this.userName = 'Артём',
  });

  final bool isDesktop;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLogin;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenMyProfile;
  final bool isAuthenticated;
  final String userName;

  @override
  Widget build(BuildContext context) {
    if (isAuthenticated) {
      return AuthenticatedSiteHeader(
        isDesktop: isDesktop,
        userName: userName,
        activeSection: AuthenticatedHeaderSection.search,
        onOpenHome: onOpenHome,
        onOpenSearch: onOpenSearch,
        onOpenRecommendations: onOpenRecommendations ?? onOpenSearch,
        onOpenFavorites: onOpenFavorites,
        onOpenProfile: onOpenMyProfile,
        horizontalPadding: isDesktop ? 24 : 16,
      );
    }

    return Container(
      height: isDesktop ? 68.8 : 57,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16),
      child: Row(
        children: [
          InkWell(
            onTap: onOpenHome,
            borderRadius: BorderRadius.circular(6),
            child: Text(
              'InkConnect',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: GuestDashboardTheme.accent,
                fontSize: isDesktop ? 20 : 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 48),
            _HeaderTextButton(label: 'Главная', onTap: onOpenHome),
            const SizedBox(width: 32),
            _HeaderTextButton(label: 'Поиск мастеров', onTap: onOpenSearch),
          ],
          const Spacer(),
          FilledButton(
            onPressed: onOpenLogin,
            style: FilledButton.styleFrom(
              backgroundColor: GuestDashboardTheme.accent,
              minimumSize: Size(isDesktop ? 80 : 66, isDesktop ? 36 : 32),
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 14),
              shape: const StadiumBorder(),
            ),
            child: const Text('Войти'),
          ),
        ],
      ),
    );
  }
}

class _AddPublicationSheet extends StatefulWidget {
  const _AddPublicationSheet({
    required this.isDesktop,
    required this.onPublish,
  });

  final bool isDesktop;
  final Future<void> Function(_PublicationDraft draft) onPublish;

  @override
  State<_AddPublicationSheet> createState() => _AddPublicationSheetState();
}

class _AddPublicationSheetState extends State<_AddPublicationSheet> {
  static const _maxPhotos = 10;
  static const _maxPhotoBytes = 50 * 1024 * 1024;
  static const _allowedPhotoExtensions = {'jpg', 'jpeg', 'png', 'webp'};
  static const _styles = inkConnectTattooStyles;

  final _descriptionController = TextEditingController();
  final List<_DraftPublicationPhoto> _photos = [];
  final Set<String> _selectedStyles = <String>{};
  String? _notice;
  bool _commentsDisabled = false;
  bool _publishing = false;
  int _photoSeed = 0;

  bool get _canPublish => _photos.isNotEmpty && !_publishing;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(_refreshDescriptionCounter);
  }

  @override
  void dispose() {
    _descriptionController
      ..removeListener(_refreshDescriptionCounter)
      ..dispose();
    super.dispose();
  }

  void _refreshDescriptionCounter() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickPhotos() async {
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) {
      _showNotice('Можно добавить не больше $_maxPhotos фото.');
      return;
    }

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _allowedPhotoExtensions.toList(),
      withData: true,
    );
    if (result == null || !mounted) {
      return;
    }

    final accepted = <_DraftPublicationPhoto>[];
    final rejectedMessages = <String>{};
    for (final file in result.files) {
      if (_photos.length + accepted.length >= _maxPhotos) {
        rejectedMessages.add('Часть фото не добавлена: максимум $_maxPhotos.');
        continue;
      }

      final error = _photoValidationError(file);
      if (error != null) {
        rejectedMessages.add(error);
        continue;
      }

      accepted.add(
        _DraftPublicationPhoto(
          id: 'photo-${DateTime.now().microsecondsSinceEpoch}-${_photoSeed++}',
          name: file.name,
          extension: _photoExtension(file),
          sizeBytes: file.size,
          bytes: file.bytes!,
        ),
      );
    }

    setState(() {
      _photos.addAll(accepted);
      _notice = rejectedMessages.isEmpty
          ? null
          : rejectedMessages.take(2).join(' ');
    });

    if (rejectedMessages.isNotEmpty) {
      _showSnackBar(rejectedMessages.first);
    }
  }

  Future<void> _dropPhotos(List<DroppedUploadFile> files) async {
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) {
      _showNotice('Можно добавить не больше $_maxPhotos фото.');
      return;
    }

    final accepted = <_DraftPublicationPhoto>[];
    final rejectedMessages = <String>{};
    for (final file in files) {
      if (_photos.length + accepted.length >= _maxPhotos) {
        rejectedMessages.add('Часть фото не добавлена: максимум $_maxPhotos.');
        continue;
      }

      final error = _droppedPhotoValidationError(file);
      if (error != null) {
        rejectedMessages.add(error);
        continue;
      }

      accepted.add(
        _DraftPublicationPhoto(
          id: 'photo-${DateTime.now().microsecondsSinceEpoch}-${_photoSeed++}',
          name: file.name,
          extension: _extensionFromName(file.name),
          sizeBytes: file.size,
          bytes: file.bytes,
        ),
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _photos.addAll(accepted);
      _notice = rejectedMessages.isEmpty
          ? null
          : rejectedMessages.take(2).join(' ');
    });

    if (rejectedMessages.isNotEmpty) {
      _showSnackBar(rejectedMessages.first);
    }
  }

  String? _photoValidationError(PlatformFile file) {
    final extension = _photoExtension(file);
    if (!_allowedPhotoExtensions.contains(extension)) {
      return 'Поддерживаются только JPG, PNG и WEBP.';
    }
    if (file.size > _maxPhotoBytes) {
      return 'Фото ${file.name} больше 50 MB.';
    }
    if (file.bytes == null || file.bytes!.isEmpty) {
      return 'Не удалось прочитать ${file.name}.';
    }
    return null;
  }

  String? _droppedPhotoValidationError(DroppedUploadFile file) {
    final extension = _extensionFromName(file.name);
    if (!_allowedPhotoExtensions.contains(extension)) {
      return 'Поддерживаются только JPG, PNG и WEBP.';
    }
    if (file.size > _maxPhotoBytes) {
      return 'Фото ${file.name} больше 50 MB.';
    }
    if (file.bytes.isEmpty) {
      return 'Не удалось прочитать ${file.name}.';
    }
    return null;
  }

  String _photoExtension(PlatformFile file) {
    final extension = file.extension?.trim().toLowerCase();
    if (extension != null && extension.isNotEmpty) {
      return extension;
    }
    final dotIndex = file.name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == file.name.length - 1) {
      return '';
    }
    return file.name.substring(dotIndex + 1).toLowerCase();
  }

  String _extensionFromName(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1).toLowerCase();
  }

  void _removePhoto(String id) {
    setState(() {
      _photos.removeWhere((photo) => photo.id == id);
      _notice = null;
    });
  }

  void _toggleStyle(String style) {
    setState(() {
      if (_selectedStyles.contains(style)) {
        _selectedStyles.remove(style);
      } else {
        _selectedStyles.add(style);
      }
    });
  }

  void _showNotice(String text) {
    setState(() => _notice = text);
    _showSnackBar(text);
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _publish() async {
    if (!_canPublish) {
      return;
    }
    setState(() {
      _publishing = true;
      _notice = null;
    });
    try {
      await widget.onPublish(
        _PublicationDraft(
          description: _descriptionController.text.trim(),
          styles: _selectedStyles.toList(growable: false),
          commentsDisabled: _commentsDisabled,
          photos: List<_DraftPublicationPhoto>.of(_photos),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = 'Не удалось опубликовать: $error';
      setState(() {
        _publishing = false;
        _notice = message;
      });
      _showSnackBar(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.isDesktop ? _buildDesktop(context) : _buildMobile(context);
  }

  Widget _buildDesktop(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = size.width >= 1060 ? 980.0 : size.width - 48;
    final dialogHeight = size.height >= 800 ? 740.0 : size.height - 48;
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DesktopPublicationHeader(
                onClose: () => Navigator.of(context).pop(false),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 390,
                        child: SingleChildScrollView(
                          child: _mediaSection(true),
                        ),
                      ),
                      const SizedBox(width: 28),
                      Container(
                        width: 1,
                        height: double.infinity,
                        color: const Color(0xFFE5E7EB),
                      ),
                      const SizedBox(width: 28),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _detailsSection(true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _DesktopPublicationActions(
                canPublish: _canPublish,
                publishing: _publishing,
                onCancel: () => Navigator.of(context).pop(false),
                onPublish: _publish,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Material(
      color: Colors.white,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            _MobilePublicationHeader(
              canPublish: _canPublish,
              publishing: _publishing,
              onClose: () => Navigator.of(context).pop(false),
              onPublish: _publish,
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _mobileCard(_mediaSection(false)),
                    const SizedBox(height: 12),
                    _mobileCard(_detailsSection(false)),
                    const SizedBox(height: 12),
                    _mobileCard(_additionalSection()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileCard(Widget child) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDEFF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _mediaSection(bool isDesktop) {
    final title = _photos.isEmpty
        ? 'Медиафайлы'
        : 'Медиафайлы (${_photos.length}/$_maxPhotos)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PublicationSectionTitle(title: title, subtitle: 'Добавьте до 10 фото'),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 16),
          _PhotoPreviewGrid(
            photos: _photos,
            isDesktop: isDesktop,
            onRemove: _removePhoto,
          ),
        ],
        const SizedBox(height: 18),
        _PhotoUploadArea(
          isDesktop: isDesktop,
          hasPhotos: _photos.isNotEmpty,
          onPickPhotos: _pickPhotos,
          onDropPhotos: _dropPhotos,
        ),
        const SizedBox(height: 14),
        const Text(
          'Фото: JPG, PNG, WEBP до 50 MB',
          style: TextStyle(
            color: Color(0xFF667085),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 10),
          Text(
            _notice!,
            style: const TextStyle(
              color: Color(0xFF9A6700),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailsSection(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PublicationSectionTitle(title: 'Описание'),
        const SizedBox(height: 12),
        SizedBox(
          height: isDesktop ? 236 : 156,
          child: TextField(
          controller: _descriptionController,
          expands: true,
          minLines: null,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          maxLength: 2000,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 15,
            height: 1.45,
          ),
          decoration: InputDecoration(
            hintText: 'Расскажите о работе, процессе, идее...',
            hintStyle: const TextStyle(color: Color(0xFF8A94A6)),
            counterText: '${_descriptionController.text.length}/2000',
            counterStyle: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD9DEE7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: GuestDashboardTheme.accent,
                width: 1.4,
              ),
            ),
          ),
          ),
        ),
        SizedBox(height: isDesktop ? 26 : 22),
        const _PublicationSectionTitle(
          title: 'Стили',
          subtitle: 'Выберите стиль(и), к которым относится ваша работа',
        ),
        const SizedBox(height: 12),
        _StylesPicker(
          styles: _styles,
          selectedStyles: _selectedStyles,
          onToggleStyle: _toggleStyle,
        ),
        if (isDesktop) ...[
          const SizedBox(height: 28),
          _additionalSection(),
        ],
      ],
    );
  }

  Widget _additionalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.isDesktop) ...[
          const _PublicationSectionTitle(title: 'Дополнительно'),
          const SizedBox(height: 12),
        ],
        _PublicationToggleRow(
          label: 'Отключить комментарии',
          value: _commentsDisabled,
          onChanged: (value) {
            setState(() => _commentsDisabled = value);
          },
        ),
      ],
    );
  }
}

class _DraftPublicationPhoto {
  const _DraftPublicationPhoto({
    required this.id,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.bytes,
  });

  final String id;
  final String name;
  final String extension;
  final int sizeBytes;
  final Uint8List bytes;
}

class _PublicationDraft {
  const _PublicationDraft({
    required this.description,
    required this.styles,
    required this.commentsDisabled,
    required this.photos,
  });

  final String description;
  final List<String> styles;
  final bool commentsDisabled;
  final List<_DraftPublicationPhoto> photos;
}

class _DesktopPublicationHeader extends StatelessWidget {
  const _DesktopPublicationHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const canDelete = false;
    void onDelete() {}

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 24, 22),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Новая публикация',
                  style: TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Поделитесь своей работой с сообществом',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (canDelete)
            PopupMenuButton<String>(
              tooltip: _actionsTooltip,
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (value) {
                if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(_deletePublicationLabel),
                ),
              ],
            )
          else
            IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Закрыть',
            color: const Color(0xFF101828),
          ),
        ],
      ),
    );
  }
}

class _MobilePublicationHeader extends StatelessWidget {
  const _MobilePublicationHeader({
    required this.canPublish,
    required this.publishing,
    required this.onClose,
    required this.onPublish,
  });

  final bool canPublish;
  final bool publishing;
  final VoidCallback onClose;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Закрыть',
              color: const Color(0xFF101828),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Новая публикация',
                  style: TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: canPublish ? onPublish : null,
              style: TextButton.styleFrom(
                foregroundColor: GuestDashboardTheme.accent,
                disabledForegroundColor: const Color(0xFF98A2B3),
              ),
              child: const Text(
                'Опубликовать',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopPublicationActions extends StatelessWidget {
  const _DesktopPublicationActions({
    required this.canPublish,
    required this.publishing,
    required this.onCancel,
    required this.onPublish,
  });

  final bool canPublish;
  final bool publishing;
  final VoidCallback onCancel;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF101828),
              side: const BorderSide(color: Color(0xFFD9DEE7)),
              minimumSize: const Size(112, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Отмена',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 14),
          FilledButton(
            onPressed: canPublish ? onPublish : null,
            style: FilledButton.styleFrom(
              backgroundColor: GuestDashboardTheme.accent,
              disabledBackgroundColor: const Color(0xFFB8C0BD),
              foregroundColor: Colors.white,
              minimumSize: const Size(156, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Опубликовать',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicationSectionTitle extends StatelessWidget {
  const _PublicationSectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _PhotoPreviewGrid extends StatelessWidget {
  const _PhotoPreviewGrid({
    required this.photos,
    required this.isDesktop,
    required this.onRemove,
  });

  final List<_DraftPublicationPhoto> photos;
  final bool isDesktop;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 2 : 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        return _PhotoPreviewTile(
          photo: photos[index],
          index: index,
          isCover: index == 0,
          onRemove: () => onRemove(photos[index].id),
        );
      },
    );
  }
}

class _PhotoPreviewTile extends StatelessWidget {
  const _PhotoPreviewTile({
    required this.photo,
    required this.index,
    required this.isCover,
    required this.onRemove,
  });

  final _DraftPublicationPhoto photo;
  final int index;
  final bool isCover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(photo.bytes, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x22000000), Color(0x55000000)],
              ),
            ),
          ),
          if (isCover)
            Positioned(
              left: 8,
              top: 8,
              child: _PhotoBadge(
                label: 'Обложка',
                color: GuestDashboardTheme.accent,
              ),
            ),
          Positioned(
            right: 8,
            top: 8,
            child: _PublicationRoundIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Удалить фото',
              onTap: onRemove,
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: _PhotoBadge(
              label: '${index + 1}',
              color: Colors.black.withValues(alpha: 0.58),
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PublicationRoundIconButton extends StatelessWidget {
  const _PublicationRoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF101828)),
        ),
      ),
    );
  }
}

class _PhotoUploadArea extends StatefulWidget {
  const _PhotoUploadArea({
    required this.isDesktop,
    required this.hasPhotos,
    required this.onPickPhotos,
    required this.onDropPhotos,
  });

  final bool isDesktop;
  final bool hasPhotos;
  final VoidCallback onPickPhotos;
  final Future<void> Function(List<DroppedUploadFile> files) onDropPhotos;

  @override
  State<_PhotoUploadArea> createState() => _PhotoUploadAreaState();
}

class _PhotoUploadAreaState extends State<_PhotoUploadArea> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final height = widget.isDesktop
        ? (widget.hasPhotos ? 154.0 : 260.0)
        : 96.0;
    final area = _DashedBorder(
      radius: 16,
      color: _isDragging
          ? GuestDashboardTheme.accent
          : const Color(0xFFD0D5DD),
      child: InkWell(
        onTap: widget.onPickPhotos,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: _isDragging
                ? GuestDashboardTheme.accent.withValues(alpha: 0.06)
                : const Color(0xFFFBFCFD),
            borderRadius: BorderRadius.circular(16),
          ),
          child: widget.isDesktop
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_upload_outlined,
                      color: GuestDashboardTheme.accent,
                      size: 38,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Перетащите файлы сюда',
                      style: TextStyle(
                        color: Color(0xFF101828),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'или',
                      style: TextStyle(color: Color(0xFF667085)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: widget.onPickPhotos,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF101828),
                        side: const BorderSide(color: Color(0xFFD9DEE7)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Выбрать файлы',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: GuestDashboardTheme.accent,
                      size: 28,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Добавить фото',
                      style: TextStyle(
                        color: GuestDashboardTheme.accent,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
    return DropFileArea(
      enabled: widget.isDesktop,
      onTap: widget.onPickPhotos,
      onFilesDropped: widget.onDropPhotos,
      onHoverChanged: (value) {
        if (mounted) {
          setState(() => _isDragging = value);
        }
      },
      child: area,
    );
  }
}

class _StylesPicker extends StatelessWidget {
  const _StylesPicker({
    required this.styles,
    required this.selectedStyles,
    required this.onToggleStyle,
  });

  final List<String> styles;
  final Set<String> selectedStyles;
  final ValueChanged<String> onToggleStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD9DEE7)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: selectedStyles.isEmpty
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Без стиля',
                      style: TextStyle(
                        color: Color(0xFF8A94A6),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selectedStyles
                        .map(
                          (style) => _SelectedStyleChip(
                            label: style,
                            onDeleted: () => onToggleStyle(style),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: styles
              .map(
                (style) => _SelectableStyleChip(
                  label: style,
                  selected: selectedStyles.contains(style),
                  onTap: () => onToggleStyle(style),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _SelectedStyleChip extends StatelessWidget {
  const _SelectedStyleChip({required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: GuestDashboardTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onDeleted,
            borderRadius: BorderRadius.circular(999),
            child: const Icon(Icons.close_rounded, size: 17),
          ),
        ],
      ),
    );
  }
}

class _SelectableStyleChip extends StatelessWidget {
  const _SelectableStyleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? GuestDashboardTheme.accent
              : const Color(0xFFF6F8F7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? GuestDashboardTheme.accent
                : const Color(0xFFD9DEE7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF344054),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicationToggleRow extends StatelessWidget {
  const _PublicationToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.mode_comment_outlined,
          color: Color(0xFF344054),
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Switch.adaptive(
          value: value,
          activeColor: GuestDashboardTheme.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DashedBorder extends StatelessWidget {
  const _DashedBorder({
    required this.child,
    required this.radius,
    required this.color,
  });

  final Widget child;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(radius: radius, color: color),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 7;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 13;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.color != color;
  }
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, color: Color(0xFF364153)),
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.currentLabel,
    required this.showSearchLink,
  });

  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final String currentLabel;
  final bool showSearchLink;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _BreadcrumbLink(label: 'Главная', onTap: onOpenHome),
        if (showSearchLink) ...[
          const _BreadcrumbDivider(),
          _BreadcrumbLink(label: 'Поиск мастеров', onTap: onOpenSearch),
        ],
        const _BreadcrumbDivider(),
        Text(
          currentLabel,
          style: TextStyle(
            color: Color(0xFF1E2939),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _BreadcrumbLink extends StatelessWidget {
  const _BreadcrumbLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(color: Color(0xFF6A7282), fontSize: 14),
      ),
    );
  }
}

class _BreadcrumbDivider extends StatelessWidget {
  const _BreadcrumbDivider();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '/',
      style: TextStyle(color: Color(0xFF6A7282), fontSize: 14),
    );
  }
}

class _MasterProfileSidebar extends StatelessWidget {
  const _MasterProfileSidebar({
    required this.onOpenBooking,
    required this.onOpenChat,
    required this.onAddPublication,
    required this.onEditProfile,
    required this.isOwnProfile,
    required this.showFullName,
    required this.showCity,
    required this.userName,
    this.profile,
    this.masterSettings,
    this.publicProfile,
    this.isFavorite = false,
    this.favoriteUpdating = false,
    this.onToggleFavorite,
  });

  final ValueChanged<String?> onOpenBooking;
  final VoidCallback onOpenChat;
  final VoidCallback onAddPublication;
  final VoidCallback onEditProfile;
  final bool isOwnProfile;
  final bool showFullName;
  final bool showCity;
  final String userName;
  final UserProfile? profile;
  final MasterSettings? masterSettings;
  final MasterProfile? publicProfile;
  final bool isFavorite;
  final bool favoriteUpdating;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final handle = isOwnProfile
        ? _ownProfileHandle(profile, userName)
        : _profileHandle(publicProfile?.username ?? _publicMasterHandle);
    final publicDisplayName = publicProfile?.displayName.trim() ?? '';
    final displayName = isOwnProfile
        ? _ownProfileDisplayName(
            profile: profile,
            fallbackUserName: userName,
            showFullName: showFullName,
          )
        : publicDisplayName.isNotEmpty
        ? publicDisplayName
        : handle;
    final secondaryName = displayName == handle
        ? ''
        : handle;
    final fullName = secondaryName;
    final studioName = isOwnProfile
        ? ''
        : publicProfile?.studioName.trim() ?? '';
    final cityLabel = isOwnProfile
        ? _ownProfileCityLabel(profile: profile, showCity: showCity)
        : 'Москва · Sakura Tattoo';
    final styles = isOwnProfile
        ? masterSettings?.styles ?? const <String>[]
        : const ['Япония', 'Леттеринг'];
    final priceLabel = isOwnProfile && masterSettings != null
        ? 'от ${_formatRubles(masterSettings!.minSessionPrice)} ₽'
        : 'от 5 000 ₽';
    final publicCity = publicProfile?.city.trim();
    final effectiveCityLabel = isOwnProfile
        ? cityLabel
        : publicProfile == null
        ? cityLabel
        : publicCity != null && publicCity.isNotEmpty
        ? publicCity
        : null;
    final effectivePriceLabel =
        publicProfile != null && publicProfile!.minSessionPrice > 0
        ? '\u043e\u0442 ${_formatRubles(publicProfile!.minSessionPrice)} \u20bd'
        : priceLabel;
    final effectiveStyles = publicProfile != null
        ? publicProfile!.styles
        : styles;
    final ratingLabel = publicProfile == null
        ? '0.0 (0)'
        : '${publicProfile!.rating.toStringAsFixed(1)} (${publicProfile!.reviewCount})';
    final avatarUrl = isOwnProfile
        ? profile?.avatarUrl.trim() ?? ''
        : publicProfile?.avatarUrl.trim() ?? '';

    return Column(
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: _cardDecoration(),
          child: Column(
            children: [
              _HeroProfileImage(
                imageUrl: avatarUrl,
                label: displayName,
                showFavorite: !isOwnProfile,
                isFavorite: isFavorite,
                favoriteUpdating: favoriteUpdating,
                onToggleFavorite: onToggleFavorite,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (fullName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        fullName,
                        style: const TextStyle(
                          color: Color(0xFF4A5565),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (studioName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '\u0421\u0442\u0443\u0434\u0438\u044f \u0438\u043b\u0438 \u0440\u0430\u0431\u043e\u0447\u0435\u0435 \u0438\u043c\u044f: $studioName',
                        style: const TextStyle(
                          color: Color(0xFF4A5565),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const _StarRating(),
                        const SizedBox(width: 6),
                        Text(
                          ratingLabel,
                          style: const TextStyle(
                            color: Color(0xFF364153),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (effectiveCityLabel != null)
                      _InfoRow(
                        icon: Icons.location_on_outlined,
                        label: effectiveCityLabel,
                      ),
                    _InfoRow(
                      icon: Icons.payments_outlined,
                      label: effectivePriceLabel,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final style in effectiveStyles.take(6))
                          _ProfileChip(style),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: isOwnProfile
                          ? onAddPublication
                          : () => onOpenBooking(null),
                      style: FilledButton.styleFrom(
                        backgroundColor: GuestDashboardTheme.accent,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        isOwnProfile ? 'Добавить публикацию' : 'Записаться',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: isOwnProfile ? onEditProfile : onOpenChat,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                        foregroundColor: const Color(0xFF364153),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        isOwnProfile
                            ? 'Редактировать профиль'
                            : 'Написать сообщение',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroProfileImage extends StatelessWidget {
  const _HeroProfileImage({
    required this.imageUrl,
    required this.label,
    required this.showFavorite,
    required this.isFavorite,
    required this.favoriteUpdating,
    required this.onToggleFavorite,
  });

  final String imageUrl;
  final String label;
  final bool showFavorite;
  final bool isFavorite;
  final bool favoriteUpdating;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProfileImage(
            avatarUrl: imageUrl,
            letterFallback: label,
            fit: BoxFit.cover,
            backgroundColor: GuestDashboardTheme.accent,
            letterStyle: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.w900,
            ),
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
              children: [
                if (showFavorite) ...[
                  _RoundIconButton(
                    icon: isFavorite
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    tooltip: isFavorite ? 'В избранном' : 'В избранное',
                    onPressed: favoriteUpdating ? null : onToggleFavorite,
                  ),
                  const SizedBox(width: 8),
                ],
                const _RoundIconButton(icon: Icons.share_outlined),
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, this.tooltip, this.onPressed});

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: const Color(0xFF364153)),
        ),
      ),
    );

    final decorated = Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: button,
    );

    if (tooltip == null) {
      return decorated;
    }
    return Tooltip(message: tooltip!, child: decorated);
  }
}

class _StarRating extends StatelessWidget {
  const _StarRating();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (_) => const Padding(
          padding: EdgeInsets.only(right: 2),
          child: Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFC107)),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final hideIcon = icon == Icons.payments_outlined;

    return Row(
      children: [
        if (!hideIcon) ...[
          Icon(icon, size: 16, color: GuestDashboardTheme.accent),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: const Color(0xFF4A5565),
              fontSize: 14,
              fontWeight: hideIcon ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Color(0xFF364153), fontSize: 12),
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF6A7282), fontSize: 12),
        ),
      ],
    );
  }
}

class _MasterProfileContent extends StatelessWidget {
  const _MasterProfileContent({
    required this.selectedTab,
    required this.onTabSelected,
    required this.onOpenBooking,
    required this.onOpenPortfolioPost,
    required this.isOwnProfile,
    this.profile,
    this.masterSettings,
    this.services,
    this.publicProfile,
    required this.portfolioItems,
    required this.publicationsLoading,
    this.publicationsError,
    required this.onRetryPublications,
  });

  final _MasterProfileTab selectedTab;
  final ValueChanged<_MasterProfileTab> onTabSelected;
  final ValueChanged<String?> onOpenBooking;
  final ValueChanged<int> onOpenPortfolioPost;
  final bool isOwnProfile;
  final UserProfile? profile;
  final MasterSettings? masterSettings;
  final List<MasterServiceSettings>? services;
  final MasterProfile? publicProfile;
  final List<_PortfolioImageData> portfolioItems;
  final bool publicationsLoading;
  final String? publicationsError;
  final VoidCallback onRetryPublications;

  @override
  Widget build(BuildContext context) {
    final rating = publicProfile?.rating ?? 0;
    final reviewCount = publicProfile?.reviewCount ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileTabs(
          selectedTab: selectedTab,
          onTabSelected: onTabSelected,
          reviewCount: reviewCount,
        ),
        const SizedBox(height: 16),
        switch (selectedTab) {
          _MasterProfileTab.portfolio => _PortfolioContent(
            onOpenPost: onOpenPortfolioPost,
            isOwnProfile: isOwnProfile,
            portfolioItems: portfolioItems,
            loading: publicationsLoading,
            error: publicationsError,
            onRetry: onRetryPublications,
          ),
          _MasterProfileTab.services => _ServicesAndPricesContent(
            onOpenBooking: onOpenBooking,
            isOwnProfile: isOwnProfile,
            settings: isOwnProfile
                ? masterSettings
                : publicProfile?.toMasterSettingsFallback(),
            services: isOwnProfile ? services : publicProfile?.services,
          ),
          _MasterProfileTab.about => _AboutMasterContent(
            isOwnProfile: isOwnProfile,
            profile: profile,
            masterSettings: isOwnProfile
                ? masterSettings
                : publicProfile?.toMasterSettingsFallback(),
            publicProfile: publicProfile,
          ),
          _MasterProfileTab.reviews => _ReviewsContent(
            rating: rating,
            reviewCount: reviewCount,
          ),
        },
      ],
    );
  }
}

class _PortfolioContent extends StatefulWidget {
  const _PortfolioContent({
    required this.onOpenPost,
    required this.isOwnProfile,
    required this.portfolioItems,
    required this.loading,
    this.error,
    required this.onRetry,
  });

  final ValueChanged<int> onOpenPost;
  final bool isOwnProfile;
  final List<_PortfolioImageData> portfolioItems;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  static const List<_PortfolioImageData> items = [
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio01,
      caption:
          'Свободная композиция с хризантемой и мягкой графикой по предплечью.',
      date: '12 мая 2024',
      likes: 248,
      comments: [
        _PortfolioCommentData(
          'Анна',
          'Очень чистая работа, линии супер.',
          '2 ч',
        ),
        _PortfolioCommentData('Илья', 'Нравится плотность и цвет.', '1 ч'),
      ],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio02,
      caption:
          'Фрагмент японского рукава: плотные тени, красный акцент и спокойный ритм.',
      date: '8 мая 2024',
      likes: 316,
      comments: [
        _PortfolioCommentData('Марина', 'Сколько занял такой фрагмент?', '5 ч'),
      ],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio03,
      caption:
          'Леттеринг с тонкой посадкой по ключице. Минимально и аккуратно.',
      date: '4 мая 2024',
      likes: 189,
      comments: [],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio04,
      caption: 'Видео-процесс: финальные белые акценты на японском мотиве.',
      date: '30 апреля 2024',
      likes: 421,
      isVideo: false,
      comments: [
        _PortfolioCommentData('Саша', 'Видео очень атмосферное.', '1 д'),
      ],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio05,
      caption:
          'Карп кои в спокойной палитре, работа строилась под движение руки.',
      date: '26 апреля 2024',
      likes: 372,
      comments: [],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio06,
      caption: 'Графичный фрагмент с плотной штриховкой и мягким переходом.',
      date: '21 апреля 2024',
      likes: 204,
      comments: [
        _PortfolioCommentData('Олег', 'Штриховка выглядит очень ровно.', '3 д'),
      ],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio07,
      caption:
          'Орнаментальный элемент, адаптированный под старую работу клиента.',
      date: '18 апреля 2024',
      likes: 166,
      comments: [],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio08,
      caption: 'Миниатюра с тонкой линией: небольшой размер, но много деталей.',
      date: '13 апреля 2024',
      likes: 292,
      comments: [
        _PortfolioCommentData('Катя', 'Очень нежно получилось.', '6 д'),
      ],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio09,
      caption: 'Маска хання в авторской трактовке с тёплым красным акцентом.',
      date: '9 апреля 2024',
      likes: 508,
      comments: [],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio10,
      caption: 'Большой фрагмент спины, первый этап по теням и общей форме.',
      date: '3 апреля 2024',
      likes: 447,
      comments: [
        _PortfolioCommentData('Дима', 'Жду продолжение проекта.', '1 нед'),
      ],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio11,
      caption: 'Флоральный мотив с мягкой посадкой по плечу.',
      date: '28 марта 2024',
      likes: 233,
      comments: [],
    ),
    _PortfolioImageData(
      asset: GuestMasterProfileAssets.portfolio03,
      caption: 'Повторный ракурс леттеринга после заживления.',
      date: '24 марта 2024',
      likes: 154,
      comments: [],
    ),
  ];

  static const List<String> styles = [
    'Все',
    'Реализм',
    'Япония',
    'Графика / Гравюра',
    'Blackwork',
    'Fine Line',
    'Леттеринг',
  ];

  @override
  State<_PortfolioContent> createState() => _PortfolioContentState();
}

class _PortfolioContentState extends State<_PortfolioContent> {
  String _selectedStyle = _portfolioAllStyle;

  @override
  Widget build(BuildContext context) {
    final styles = _portfolioStylesForItems(widget.portfolioItems);
    if (!styles.contains(_selectedStyle)) {
      _selectedStyle = styles.first;
    }
    final filteredItems = widget.portfolioItems
        .where(
          (item) =>
              _selectedStyle == _portfolioAllStyle ||
              item.matchesStyle(_selectedStyle),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PortfolioFilterBar(
          styles: styles,
          selectedStyle: _selectedStyle,
          totalCount: filteredItems.length,
          title: widget.isOwnProfile ? 'Мои публикации' : 'Портфолио',
          onStyleSelected: (style) => setState(() => _selectedStyle = style),
        ),
        if (widget.loading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (widget.error != null) ...[
          const SizedBox(height: 12),
          _PortfolioLoadNotice(message: widget.error!, onRetry: widget.onRetry),
        ],
        const SizedBox(height: 16),
        if (filteredItems.isEmpty)
          _PortfolioEmptyState(isOwnProfile: widget.isOwnProfile)
        else
          _PortfolioGrid(
            items: filteredItems,
            onOpenPost: (item) =>
                widget.onOpenPost(widget.portfolioItems.indexOf(item)),
          ),
      ],
    );
  }
}

class _PortfolioEmptyState extends StatelessWidget {
  const _PortfolioEmptyState({required this.isOwnProfile});

  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.photo_library_outlined,
            color: Color(0xFF98A2B3),
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(
            isOwnProfile
                ? 'Публикаций пока нет'
                : 'У мастера пока нет публикаций',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isOwnProfile
                ? 'Добавьте первую работу, чтобы она появилась в профиле.'
                : 'Когда мастер добавит работы, они появятся в этом разделе.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioLoadNotice extends StatelessWidget {
  const _PortfolioLoadNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFEDFAA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB54708)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF7A4A00),
                fontSize: 13,
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

class _PortfolioFilterBar extends StatelessWidget {
  const _PortfolioFilterBar({
    required this.styles,
    required this.selectedStyle,
    required this.totalCount,
    required this.title,
    required this.onStyleSelected,
  });

  final List<String> styles;
  final String selectedStyle;
  final int totalCount;
  final String title;
  final ValueChanged<String> onStyleSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$totalCount работ',
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < styles.length; index += 1) ...[
                if (index > 0) const SizedBox(width: 10),
                _PortfolioFilterPill(
                  label: styles[index],
                  selected: selectedStyle == styles[index],
                  onTap: () => onStyleSelected(styles[index]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PortfolioFilterPill extends StatelessWidget {
  const _PortfolioFilterPill({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: selected ? 28 : 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? GuestDashboardTheme.accent : Colors.white,
          border: selected ? null : Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF4A5565),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PortfolioGrid extends StatelessWidget {
  const _PortfolioGrid({required this.items, required this.onOpenPost});

  final List<_PortfolioImageData> items;
  final ValueChanged<_PortfolioImageData> onOpenPost;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopGrid = constraints.maxWidth >= 720;
        final gap = isDesktopGrid ? 6.0 : 4.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isDesktopGrid ? 3 : 2,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: 4 / 5,
          ),
          itemBuilder: (context, index) => _PortfolioTile(
            item: items[index],
            onTap: () => onOpenPost(items[index]),
          ),
        );
      },
    );
  }
}

class _PortfolioTile extends StatefulWidget {
  const _PortfolioTile({required this.item, required this.onTap});

  final _PortfolioImageData item;
  final VoidCallback onTap;

  @override
  State<_PortfolioTile> createState() => _PortfolioTileState();
}

class _PortfolioTileState extends State<_PortfolioTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final showOverlay = !isDesktop || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RemoteOrAssetImage(
              assetPath: widget.item.asset,
              imageUrl: widget.item.imageUrl,
              fit: BoxFit.cover,
            ),
            if (widget.item.isVideo)
              Center(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            AnimatedOpacity(
              opacity: showOverlay ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: isDesktop ? 0.22 : 0.12,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (widget.item.style.trim().isNotEmpty)
                            _PortfolioOverlayPill(label: widget.item.style),
                          _PortfolioOverlayPill(
                            label: '${widget.item.likes}',
                            icon: Icons.favorite_border_rounded,
                          ),
                          _PortfolioOverlayPill(
                            label: '${widget.item.comments.length}',
                            icon: Icons.mode_comment_outlined,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  hoverColor: Colors.black.withValues(alpha: 0.06),
                  splashColor: Colors.black.withValues(alpha: 0.04),
                  highlightColor: Colors.black.withValues(alpha: 0.04),
                  onTap: widget.onTap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioOverlayPill extends StatelessWidget {
  const _PortfolioOverlayPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioImageData {
  const _PortfolioImageData({
    required this.asset,
    required this.caption,
    required this.date,
    required this.likes,
    this.comments = const [],
    this.isVideo = false,
    this.imageUrl = '',
    this.mediaUrls = const [],
    this.publicationId = '',
    this.remoteStyles = const [],
    this.commentsDisabled = false,
  });

  final String asset;
  final String caption;
  final String date;
  final int likes;
  final List<_PortfolioCommentData> comments;
  final bool isVideo;
  final String imageUrl;
  final List<String> mediaUrls;
  final String publicationId;
  final List<String> remoteStyles;
  final bool commentsDisabled;

  String get style {
    final styles = displayStyles;
    if (styles.isNotEmpty) {
      return styles.first;
    }
    return '';
  }

  List<String> get displayStyles {
    final normalizedRemoteStyles = remoteStyles
        .map((style) => style.trim())
        .where((style) => style.isNotEmpty)
        .toList(growable: false);
    if (normalizedRemoteStyles.isNotEmpty) {
      return normalizedRemoteStyles;
    }
    if (publicationId.trim().isNotEmpty) {
      return const [];
    }
    if (asset == GuestMasterProfileAssets.portfolio01 ||
        asset == GuestMasterProfileAssets.portfolio02 ||
        asset == GuestMasterProfileAssets.portfolio05) {
      return const ['Япония'];
    }
    if (asset == GuestMasterProfileAssets.portfolio03) {
      return const ['Леттеринг'];
    }
    if (asset == GuestMasterProfileAssets.portfolio04 ||
        asset == GuestMasterProfileAssets.portfolio06) {
      return const ['Графика / Гравюра'];
    }
    if (asset == GuestMasterProfileAssets.portfolio07) {
      return const ['Орнаментал'];
    }
    if (asset == GuestMasterProfileAssets.portfolio08 ||
        asset == GuestMasterProfileAssets.portfolio11) {
      return const ['Fine Line'];
    }
    if (asset == GuestMasterProfileAssets.portfolio09) {
      return const ['Blackwork'];
    }
    return const ['Реализм'];
  }

  bool matchesStyle(String selectedStyle) {
    final target = selectedStyle.trim();
    if (target.isEmpty) {
      return false;
    }
    return displayStyles.any((style) => style.trim() == target);
  }
}

const List<String> _publicationFallbackAssets = [
  GuestMasterProfileAssets.portfolio01,
  GuestMasterProfileAssets.portfolio02,
  GuestMasterProfileAssets.portfolio03,
  GuestMasterProfileAssets.portfolio04,
  GuestMasterProfileAssets.portfolio05,
  GuestMasterProfileAssets.portfolio06,
  GuestMasterProfileAssets.portfolio07,
  GuestMasterProfileAssets.portfolio08,
  GuestMasterProfileAssets.portfolio09,
  GuestMasterProfileAssets.portfolio10,
  GuestMasterProfileAssets.portfolio11,
];

_PortfolioImageData? _portfolioItemFromPublication(
  MasterPublication publication,
  int index,
) {
  final sortedMedia = List<MasterPublicationMedia>.of(publication.media)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final mediaUrls = sortedMedia
      .map((media) => media.imageUrl.trim())
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
  final coverUrl =
      publication.coverMedia?.imageUrl.trim().isNotEmpty == true
      ? publication.coverMedia!.imageUrl.trim()
      : publication.coverImageUrl.trim().isNotEmpty
      ? publication.coverImageUrl.trim()
      : mediaUrls.isNotEmpty
      ? mediaUrls.first
      : '';
  if (coverUrl.isEmpty && mediaUrls.isEmpty) {
    return null;
  }

  return _PortfolioImageData(
    asset: _publicationFallbackAssets[index % _publicationFallbackAssets.length],
    imageUrl: coverUrl,
    mediaUrls: mediaUrls.isEmpty ? [coverUrl] : mediaUrls,
    publicationId: publication.id,
    remoteStyles: publication.styles
        .map((style) => style.trim())
        .where((style) => style.isNotEmpty)
        .toList(growable: false),
    commentsDisabled: publication.commentsDisabled,
    caption: publication.description.trim().isEmpty
        ? 'Публикация мастера InkConnect'
        : publication.description.trim(),
    date: _publicationDateLabel(publication.createdAt),
    likes: 0,
    comments: const [],
  );
}

List<String> _portfolioStylesForItems(List<_PortfolioImageData> items) {
  final styles = <String>[_portfolioAllStyle];
  for (final item in items) {
    final itemStyles = item.remoteStyles.isNotEmpty
        ? item.remoteStyles
        : <String>[item.style];
    for (final style in itemStyles) {
      final normalized = style.trim();
      if (normalized.isNotEmpty && !styles.contains(normalized)) {
        styles.add(normalized);
      }
    }
  }
  return styles;
}

String _publicationDateLabel(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value.trim();
  }
  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}

class _PortfolioCommentData {
  const _PortfolioCommentData(this.author, this.text, this.time);

  final String author;
  final String text;
  final String time;
}

class _PortfolioAuthorData {
  const _PortfolioAuthorData({
    required this.handle,
    required this.displayName,
    required this.avatarUrl,
    required this.subtitle,
  });

  final String handle;
  final String displayName;
  final String avatarUrl;
  final String subtitle;

  String get captionName {
    final cleanHandle = handle.startsWith('@') ? handle.substring(1) : handle;
    if (cleanHandle.trim().isNotEmpty) {
      return cleanHandle.trim();
    }
    return displayName.trim();
  }
}

class _PortfolioFeedView extends StatefulWidget {
  const _PortfolioFeedView({
    required this.items,
    required this.initialIndex,
    required this.author,
    required this.userName,
    required this.isOwnProfile,
    required this.onClose,
    required this.onDeletePublication,
  });

  final List<_PortfolioImageData> items;
  final int initialIndex;
  final _PortfolioAuthorData author;
  final String userName;
  final bool isOwnProfile;
  final VoidCallback onClose;
  final Future<bool> Function(_PortfolioImageData item) onDeletePublication;

  @override
  State<_PortfolioFeedView> createState() => _PortfolioFeedViewState();
}

class _PortfolioFeedViewState extends State<_PortfolioFeedView> {
  late final ScrollController _scrollController;
  late List<_PortfolioImageData> _items;
  late List<GlobalKey> _postKeys;
  late final List<bool> _liked;
  late final List<int> _likes;
  late final List<List<_PortfolioCommentData>> _comments;
  late final List<TextEditingController> _commentControllers;
  late final List<FocusNode> _commentFocusNodes;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _items = List<_PortfolioImageData>.of(widget.items);
    _postKeys = List.generate(_items.length, (_) => GlobalKey());
    _liked = List.generate(_items.length, (_) => false);
    _likes = _items.map((item) => item.likes).toList();
    _comments = _items
        .map((item) => List<_PortfolioCommentData>.of(item.comments))
        .toList();
    _commentControllers = List.generate(
      _items.length,
      (_) => TextEditingController(),
    );
    _commentFocusNodes = List.generate(_items.length, (_) => FocusNode());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _postKeys[widget.initialIndex].currentContext;
      if (context == null) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _commentControllers) {
      controller.dispose();
    }
    for (final node in _commentFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 820;
    final height = MediaQuery.sizeOf(context).height;

    return Container(
      height: isDesktop ? height - 48 : height * 0.96,
      constraints: BoxConstraints(maxWidth: isDesktop ? 1080 : double.infinity),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 14 : 18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _PortfolioFeedHeader(
            title: widget.isOwnProfile
                ? 'Мои публикации'
                : 'Публикации мастера',
            onClose: widget.onClose,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 18 : 12,
                12,
                isDesktop ? 18 : 12,
                20,
              ),
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < _items.length;
                    index += 1
                  ) ...[
                    KeyedSubtree(
                      key: _postKeys[index],
                      child: _PortfolioFeedPost(
                        item: _items[index],
                        author: widget.author,
                        userName: widget.userName,
                        isOwnProfile: widget.isOwnProfile,
                        isLiked: _liked[index],
                        likes: _likes[index],
                        comments: _comments[index],
                        commentController: _commentControllers[index],
                        commentFocusNode: _commentFocusNodes[index],
                        onToggleLike: () => _toggleLike(index),
                        onFocusComment: () =>
                            _commentFocusNodes[index].requestFocus(),
                        onShare: () => _sharePost(index),
                        onSendComment: () => _sendComment(index),
                        onDelete: () => _deletePost(index),
                      ),
                    ),
                    if (index != _items.length - 1)
                      SizedBox(height: isDesktop ? 18 : 14),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleLike(int index) {
    setState(() {
      _liked[index] = !_liked[index];
      _likes[index] += _liked[index] ? 1 : -1;
    });
  }

  void _sendComment(int index) {
    final text = _commentControllers[index].text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _comments[index].add(
        _PortfolioCommentData(
          widget.userName.trim().isEmpty ? 'Вы' : widget.userName,
          text,
          'только что',
        ),
      );
      _commentControllers[index].clear();
    });
  }

  Future<void> _sharePost(int index) async {
    await Clipboard.setData(
      ClipboardData(
        text: 'https://inkconnect.local/maria-kozlova/posts/${index + 1}',
      ),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка на публикацию скопирована'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deletePost(int index) async {
    if (index < 0 || index >= _items.length) {
      return;
    }
    final item = _items[index];
    if (item.publicationId.trim().isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить публикацию?'),
        content: const Text('Публикация исчезнет из профиля, но файлы останутся в приватном хранилище.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: GuestDashboardTheme.accent,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final deleted = await widget.onDeletePublication(item);
    if (!deleted || !mounted) {
      return;
    }

    final controller = _commentControllers.removeAt(index);
    final focusNode = _commentFocusNodes.removeAt(index);
    controller.dispose();
    focusNode.dispose();
    setState(() {
      _items.removeAt(index);
      _postKeys.removeAt(index);
      _liked.removeAt(index);
      _likes.removeAt(index);
      _comments.removeAt(index);
    });
    if (_items.isEmpty) {
      widget.onClose();
    }
  }
}

class _PortfolioFeedHeader extends StatelessWidget {
  const _PortfolioFeedHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const canDelete = false;
    void onDelete() {}

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (canDelete)
            PopupMenuButton<String>(
              tooltip: _actionsTooltip,
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (value) {
                if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(_deletePublicationLabel),
                ),
              ],
            )
          else
            IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Закрыть',
          ),
        ],
      ),
    );
  }
}

class _PortfolioFeedPost extends StatelessWidget {
  const _PortfolioFeedPost({
    required this.item,
    required this.author,
    required this.userName,
    required this.isOwnProfile,
    required this.isLiked,
    required this.likes,
    required this.comments,
    required this.commentController,
    required this.commentFocusNode,
    required this.onToggleLike,
    required this.onFocusComment,
    required this.onShare,
    required this.onSendComment,
    required this.onDelete,
  });

  final _PortfolioImageData item;
  final _PortfolioAuthorData author;
  final String userName;
  final bool isOwnProfile;
  final bool isLiked;
  final int likes;
  final List<_PortfolioCommentData> comments;
  final TextEditingController commentController;
  final FocusNode commentFocusNode;
  final VoidCallback onToggleLike;
  final VoidCallback onFocusComment;
  final VoidCallback onShare;
  final VoidCallback onSendComment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 820;
    final postHeight = MediaQuery.sizeOf(context).height < 780
        ? MediaQuery.sizeOf(context).height - 120
        : 660.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: isDesktop
          ? SizedBox(
              height: postHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _PortfolioPostMedia(
                      item: item,
                      showNavigationButtons: true,
                    ),
                  ),
                  SizedBox(
                    width: 380,
                    child: _PortfolioPostDetails(
                      item: item,
                      author: author,
                      userName: userName,
                      isOwnProfile: isOwnProfile,
                      isLiked: isLiked,
                      likes: likes,
                      comments: comments,
                      commentController: commentController,
                      commentFocusNode: commentFocusNode,
                      commentsScrollable: true,
                      onToggleLike: onToggleLike,
                      onFocusComment: onFocusComment,
                      onShare: onShare,
                      onSendComment: onSendComment,
                      onDelete: onDelete,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 5,
                  child: _PortfolioPostMedia(
                    item: item,
                    showNavigationButtons: false,
                  ),
                ),
                _PortfolioPostDetails(
                  item: item,
                  author: author,
                  userName: userName,
                  isOwnProfile: isOwnProfile,
                  isLiked: isLiked,
                  likes: likes,
                  comments: comments,
                  commentController: commentController,
                  commentFocusNode: commentFocusNode,
                  commentsScrollable: false,
                  onToggleLike: onToggleLike,
                  onFocusComment: onFocusComment,
                  onShare: onShare,
                  onSendComment: onSendComment,
                  onDelete: onDelete,
                ),
              ],
            ),
    );
  }
}

class _PortfolioPostMedia extends StatefulWidget {
  const _PortfolioPostMedia({
    required this.item,
    required this.showNavigationButtons,
  });

  final _PortfolioImageData item;
  final bool showNavigationButtons;

  @override
  State<_PortfolioPostMedia> createState() => _PortfolioPostMediaState();
}

class _PortfolioPostMediaState extends State<_PortfolioPostMedia> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showMediaAt(int index, int total) {
    if (index < 0 || index >= total) {
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaUrls = widget.item.mediaUrls.isEmpty
        ? <String>[widget.item.imageUrl]
        : widget.item.mediaUrls;
    return ColoredBox(
      color: const Color(0xFF0B0F14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (mediaUrls.length <= 1)
            RemoteOrAssetImage(
              assetPath: widget.item.asset,
              imageUrl: mediaUrls.first,
              fit: BoxFit.contain,
            )
          else
            PageView.builder(
              controller: _pageController,
              itemCount: mediaUrls.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) => RemoteOrAssetImage(
                assetPath: widget.item.asset,
                imageUrl: mediaUrls[index],
                fit: BoxFit.contain,
              ),
            ),
          if (mediaUrls.length > 1)
            Positioned(
              right: 14,
              top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentIndex + 1}/${mediaUrls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          if (widget.showNavigationButtons &&
              mediaUrls.length > 1 &&
              _currentIndex > 0)
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: _MediaNavButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Предыдущее фото',
                  onTap: () => _showMediaAt(_currentIndex - 1, mediaUrls.length),
                ),
              ),
            ),
          if (widget.showNavigationButtons &&
              mediaUrls.length > 1 &&
              _currentIndex < mediaUrls.length - 1)
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: _MediaNavButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Следующее фото',
                  onTap: () => _showMediaAt(_currentIndex + 1, mediaUrls.length),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaNavButton extends StatelessWidget {
  const _MediaNavButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.54),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

class _PortfolioPostDetails extends StatelessWidget {
  const _PortfolioPostDetails({
    required this.item,
    required this.author,
    required this.userName,
    required this.isOwnProfile,
    required this.isLiked,
    required this.likes,
    required this.comments,
    required this.commentController,
    required this.commentFocusNode,
    required this.commentsScrollable,
    required this.onToggleLike,
    required this.onFocusComment,
    required this.onShare,
    required this.onSendComment,
    required this.onDelete,
  });

  final _PortfolioImageData item;
  final _PortfolioAuthorData author;
  final String userName;
  final bool isOwnProfile;
  final bool isLiked;
  final int likes;
  final List<_PortfolioCommentData> comments;
  final TextEditingController commentController;
  final FocusNode commentFocusNode;
  final bool commentsScrollable;
  final VoidCallback onToggleLike;
  final VoidCallback onFocusComment;
  final VoidCallback onShare;
  final VoidCallback onSendComment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final displayStyles = item.displayStyles;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PostAuthorHeader(
          handle: author.handle,
          fullName: author.displayName,
          avatarUrl: author.avatarUrl,
          canDelete: isOwnProfile && item.publicationId.trim().isNotEmpty,
          onDelete: onDelete,
          subtitle: author.subtitle,
        ),
        if (displayStyles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: displayStyles
                  .map((style) => _PostStyleChip(label: style))
                  .toList(),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            displayStyles.isNotEmpty ? 10 : 14,
            16,
            4,
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${author.captionName} ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: item.caption),
              ],
            ),
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            item.date,
            style: const TextStyle(color: Color(0xFF99A1AF), fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        _PostActionBar(
          isLiked: isLiked,
          commentCount: comments.length,
          onToggleLike: onToggleLike,
          onFocusComment: onFocusComment,
          onShare: onShare,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            '$likes отметок "Нравится"',
            style: const TextStyle(
              color: Color(0xFF101828),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        if (item.commentsDisabled)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Комментарии отключены',
              style: TextStyle(color: Color(0xFF6A7282), fontSize: 13),
            ),
          )
        else if (commentsScrollable)
          Expanded(child: _CommentsList(comments: comments))
        else
          _CommentsList(comments: comments),
        if (!item.commentsDisabled)
          _CommentInput(
            controller: commentController,
            focusNode: commentFocusNode,
            onSend: onSendComment,
          ),
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.white),
      child: commentsScrollable
          ? content
          : Padding(padding: EdgeInsets.zero, child: content),
    );
  }
}

class _PostAuthorHeader extends StatelessWidget {
  const _PostAuthorHeader({
    required this.handle,
    required this.fullName,
    required this.avatarUrl,
    required this.subtitle,
    required this.canDelete,
    required this.onDelete,
  });

  final String handle;
  final String fullName;
  final String avatarUrl;
  final String subtitle;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          ClipOval(
            child: _PostAuthorAvatar(
              imageUrl: avatarUrl,
              label: fullName.trim().isNotEmpty ? fullName : handle,
              size: 38,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  handle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  fullName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4A5565),
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6A7282),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (canDelete)
            PopupMenuButton<String>(
              tooltip: _actionsTooltip,
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (value) {
                if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(_deletePublicationLabel),
                ),
              ],
            )
          else
            IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: _actionsTooltip,
          ),
        ],
      ),
    );
  }
}

class _PostAuthorAvatar extends StatelessWidget {
  const _PostAuthorAvatar({
    required this.imageUrl,
    required this.label,
    required this.size,
  });

  final String imageUrl;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: GuestDashboardTheme.accent.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        _initial(label),
        style: const TextStyle(
          color: GuestDashboardTheme.accent,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    final url = imageUrl.trim();
    if (url.isEmpty) {
      return fallback;
    }
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        return progress == null ? child : fallback;
      },
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }

  String _initial(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'^@'), '');
    if (trimmed.isEmpty) {
      return 'I';
    }
    return trimmed.characters.first.toUpperCase();
  }
}

class _PostActionBar extends StatelessWidget {
  const _PostActionBar({
    required this.isLiked,
    required this.commentCount,
    required this.onToggleLike,
    required this.onFocusComment,
    required this.onShare,
  });

  final bool isLiked;
  final int commentCount;
  final VoidCallback onToggleLike;
  final VoidCallback onFocusComment;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onToggleLike,
            icon: Icon(
              isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isLiked
                  ? const Color(0xFFE11D48)
                  : const Color(0xFF101828),
            ),
            tooltip: 'Нравится',
          ),
          IconButton(
            onPressed: onFocusComment,
            icon: const Icon(Icons.mode_comment_outlined),
            tooltip: 'Комментарий',
          ),
          Text(
            '$commentCount',
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Поделиться',
          ),
        ],
      ),
    );
  }
}

class _PostStyleChip extends StatelessWidget {
  const _PostStyleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GuestDashboardTheme.accent.withValues(alpha: 0.10),
        border: Border.all(
          color: GuestDashboardTheme.accent.withValues(alpha: 0.22),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: GuestDashboardTheme.accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CommentsList extends StatelessWidget {
  const _CommentsList({required this.comments});

  final List<_PortfolioCommentData> comments;

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Комментариев пока нет. Будьте первым, кто задаст вопрос о работе.',
          style: TextStyle(color: Color(0xFF6A7282), fontSize: 13, height: 1.4),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final comment in comments) ...[
            _CommentRow(comment: comment),
            if (comment != comments.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final _PortfolioCommentData comment;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${comment.author} ',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: comment.text),
          TextSpan(
            text: '  ${comment.time}',
            style: const TextStyle(color: Color(0xFF99A1AF), fontSize: 12),
          ),
        ],
      ),
      style: const TextStyle(
        color: Color(0xFF101828),
        fontSize: 13,
        height: 1.38,
      ),
    );
  }
}

class _CommentInput extends StatelessWidget {
  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Добавить комментарий...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
              ),
            ),
          ),
          TextButton(onPressed: onSend, child: const Text('Отправить')),
        ],
      ),
    );
  }
}

class _AboutMasterContent extends StatelessWidget {
  const _AboutMasterContent({
    required this.isOwnProfile,
    this.profile,
    this.masterSettings,
    this.publicProfile,
  });

  final bool isOwnProfile;
  final UserProfile? profile;
  final MasterSettings? masterSettings;
  final MasterProfile? publicProfile;

  @override
  Widget build(BuildContext context) {
    final bio = (isOwnProfile ? profile?.bio : publicProfile?.bio)?.trim();
    final aboutText = bio != null && bio.isNotEmpty
        ? bio
        : isOwnProfile
        ? 'Вы пока не добавили описание. Заполните поле «О себе» в настройках профиля.'
        : profile != null || publicProfile != null
        ? ''
        : 'Работаю в стиле «Япония» и каллиграфическом леттеринге более 10 лет. Часто беру крупные композиции, тонкую графику и аккуратные надписи.';
    final profileCity = isOwnProfile
        ? (profile?.showCityInProfile == true ? profile?.city.trim() : null)
        : publicProfile?.city.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AboutInfoCard(
          icon: Icons.person_outline,
          title: 'О мастере',
          child: Text(
            aboutText,
            style: const TextStyle(
              color: Color(0xFF364153),
              fontSize: 14,
              height: 1.63,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _AboutInfoCard(
          icon: Icons.badge_outlined,
          title: 'Информация',
          child: _MasterDetailsGrid(
            city: profileCity == null || profileCity.isEmpty
                ? null
                : profileCity,
            isOwnProfile: isOwnProfile,
            useProfileCity: profile != null || publicProfile != null,
            settings: masterSettings,
          ),
        ),
      ],
    );
  }
}

class _AboutInfoCard extends StatelessWidget {
  const _AboutInfoCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: GuestDashboardTheme.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MasterDetailsGrid extends StatelessWidget {
  const _MasterDetailsGrid({
    required this.isOwnProfile,
    this.city,
    this.useProfileCity = false,
    this.settings,
  });

  final bool isOwnProfile;
  final String? city;
  final bool useProfileCity;
  final MasterSettings? settings;

  @override
  Widget build(BuildContext context) {
    final cityDetail = _MasterDetail(
      'Город',
      useProfileCity ? city ?? 'Не указан' : 'Москва',
    );
    final categoryDetail = _MasterDetail(
      'Категория',
      settings?.category ?? 'Тату-мастер',
    );
    final styles = settings?.styles;
    final stylesDetail = _MasterDetail(
      'Стили:',
      styles != null && styles.isNotEmpty
          ? styles.join(', ')
          : isOwnProfile
          ? 'Выберите стили в настройках профиля'
          : useProfileCity
          ? ''
          : 'Япония, Леттеринг',
    );
    final minPriceDetail = _MasterDetail(
      'Минимальная стоимость сеанса',
      'от ${_formatRubles(settings?.minSessionPrice ?? 5000)} ₽',
    );
    final hourlyRateDetail = _MasterDetail(
      'Стоимость за час',
      '${_formatRubles(settings?.hourlyRate ?? 2500)} ₽',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoColumns = constraints.maxWidth >= 680;

        if (!isTwoColumns) {
          return Column(
            children: [
              _MasterDetailRow(detail: cityDetail),
              _MasterDetailRow(detail: categoryDetail),
              _MasterDetailRow(detail: stylesDetail),
              _MasterDetailRow(detail: minPriceDetail),
              _MasterDetailRow(detail: hourlyRateDetail),
            ],
          );
        }

        final columnWidth = (constraints.maxWidth - 12) / 2;
        final fullWidthLabelWidth = columnWidth > 120
            ? columnWidth - 90
            : columnWidth * 0.65;
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: columnWidth,
                  child: _MasterDetailRow(detail: cityDetail),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: columnWidth,
                  child: _MasterDetailRow(detail: categoryDetail),
                ),
              ],
            ),
            _MasterDetailRow(
              detail: stylesDetail,
              labelWidth: fullWidthLabelWidth,
              valueTextAlign: TextAlign.left,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: columnWidth,
                  child: _MasterDetailRow(detail: minPriceDetail),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: columnWidth,
                  child: _MasterDetailRow(detail: hourlyRateDetail),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MasterDetailRow extends StatelessWidget {
  const _MasterDetailRow({
    required this.detail,
    this.labelWidth,
    this.valueTextAlign = TextAlign.right,
  });

  final _MasterDetail detail;
  final double? labelWidth;
  final TextAlign valueTextAlign;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 49),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final defaultLabelWidth = constraints.maxWidth < 420 ? 130.0 : 220.0;
          final maxLabelWidth = constraints.maxWidth * 0.58;
          final requestedLabelWidth = labelWidth ?? defaultLabelWidth;
          final effectiveLabelWidth = requestedLabelWidth > maxLabelWidth
              ? maxLabelWidth
              : requestedLabelWidth;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: effectiveLabelWidth,
                child: Text(
                  detail.label,
                  style: const TextStyle(
                    color: Color(0xFF6A7282),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  detail.value,
                  textAlign: valueTextAlign,
                  softWrap: true,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MasterDetail {
  const _MasterDetail(this.label, this.value);

  final String label;
  final String value;
}

class _ReviewsContent extends StatelessWidget {
  const _ReviewsContent({required this.rating, required this.reviewCount});

  final double rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RatingSummaryCard(rating: rating, reviewCount: reviewCount),
        if (reviewCount > 0) ...[
          const SizedBox(height: 12),
          const _ReviewCard(),
          const SizedBox(height: 12),
          _ShowAllReviewsButton(reviewCount: reviewCount),
        ],
      ],
    );
  }
}

class _RatingSummaryCard extends StatelessWidget {
  const _RatingSummaryCard({required this.rating, required this.reviewCount});

  final double rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 640;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: isCompact
          ? Column(
              children: [
                _RatingTotal(rating: rating, reviewCount: reviewCount),
                const SizedBox(height: 18),
                _RatingDistribution(rating: rating, reviewCount: reviewCount),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 108,
                  child: _RatingTotal(rating: rating, reviewCount: reviewCount),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _RatingDistribution(
                    rating: rating,
                    reviewCount: reviewCount,
                  ),
                ),
              ],
            ),
    );
  }
}

class _RatingTotal extends StatelessWidget {
  const _RatingTotal({required this.rating, required this.reviewCount});

  final double rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final ratingLabel = rating > 0 ? rating.toStringAsFixed(1) : '0.0';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ratingLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 36,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        _LargeStarRating(rating: rating),
        const SizedBox(height: 3),
        Text(
          '$reviewCount отзывов',
          style: const TextStyle(color: Color(0xFF6A7282), fontSize: 12),
        ),
      ],
    );
  }
}

class _LargeStarRating extends StatelessWidget {
  const _LargeStarRating({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            index < rating.round()
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            size: 20,
            color: const Color(0xFFFFB900),
          ),
        ),
      ),
    );
  }
}

class _RatingDistribution extends StatelessWidget {
  const _RatingDistribution({required this.rating, required this.reviewCount});

  final double rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final stats = _ratingStatsFor(rating, reviewCount);
    return Column(
      children: [
        for (final stat in stats) ...[
          _RatingDistributionRow(stat: stat),
          if (stat != stats.last) const SizedBox(height: 6),
        ],
      ],
    );
  }

  List<_RatingStat> _ratingStatsFor(double rating, int reviewCount) {
    if (reviewCount <= 0) {
      return const [
        _RatingStat(5, 0, 0),
        _RatingStat(4, 0, 0),
        _RatingStat(3, 0, 0),
        _RatingStat(2, 0, 0),
        _RatingStat(1, 0, 0),
      ];
    }
    final normalized = rating.clamp(3.0, 5.0);
    final fiveRatio = (0.36 + (normalized - 3) * 0.24).clamp(0.36, 0.84);
    final fourRatio = (0.38 - (normalized - 3) * 0.12).clamp(0.14, 0.38);
    final threeRatio = (0.20 - (normalized - 3) * 0.06).clamp(0.05, 0.20);
    var five = (reviewCount * fiveRatio).round();
    var four = (reviewCount * fourRatio).round();
    var three = (reviewCount * threeRatio).round();
    var two = ((reviewCount - five - four - three) * 0.65).round();
    var one = reviewCount - five - four - three - two;
    if (one < 0) {
      three += one;
      one = 0;
    }
    if (three < 0) {
      four += three;
      three = 0;
    }
    final counts = [five, four, three, two, one];
    return [
      for (var index = 0; index < counts.length; index += 1)
        _RatingStat(5 - index, counts[index], counts[index] / reviewCount),
    ];
  }
}

class _RatingDistributionRow extends StatelessWidget {
  const _RatingDistributionRow({required this.stat});

  final _RatingStat stat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 12,
          child: Text(
            '${stat.stars}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF6A7282), fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFFB900)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: stat.ratio,
              backgroundColor: const Color(0xFFF3F4F6),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB900)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            '${stat.count}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF6A7282), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _RatingStat {
  const _RatingStat(this.stars, this.count, this.ratio);

  final int stars;
  final int count;
  final double ratio;
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                child: Image.asset(
                  GuestMasterProfileAssets.svetlanaReview,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: _ReviewHeader()),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Лучший мастер по японскому стилю в Москве! Кои вышла невероятная.',
            style: TextStyle(
              color: Color(0xFF364153),
              fontSize: 14,
              height: 1.63,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader();

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 560;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isCompact) ...[
          const Text(
            'Светлана Иванова',
            style: TextStyle(
              color: Color(0xFF101828),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '1 мая 2025',
            style: TextStyle(color: Color(0xFF99A1AF), fontSize: 12),
          ),
        ] else
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Светлана Иванова',
                  style: TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '1 мая 2025',
                style: TextStyle(color: Color(0xFF99A1AF), fontSize: 12),
              ),
            ],
          ),
        const SizedBox(height: 2),
        const Row(
          children: [
            _StarRating(),
            SizedBox(width: 8),
            Text(
              'Япония, бедро',
              style: TextStyle(color: Color(0xFF99A1AF), fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShowAllReviewsButton extends StatelessWidget {
  const _ShowAllReviewsButton({required this.reviewCount});

  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        foregroundColor: const Color(0xFF4A5565),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text('Показать все $reviewCount отзывов'),
    );
  }
}

class _ComingSoonProfileContent extends StatelessWidget {
  const _ComingSoonProfileContent();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _ServicesAndPricesContent extends StatelessWidget {
  const _ServicesAndPricesContent({
    required this.onOpenBooking,
    required this.isOwnProfile,
    this.settings,
    this.services,
  });

  final ValueChanged<String?> onOpenBooking;
  final bool isOwnProfile;
  final MasterSettings? settings;
  final List<MasterServiceSettings>? services;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PremiumServicesSettingsSummaryCard(settings: settings),
        const SizedBox(height: 18),
        const Text(
          'Услуги',
          style: TextStyle(
            color: Color(0xFF101828),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        if (services != null && services!.isNotEmpty) ...[
          for (final service in services!) ...[
            _ServicePriceCard(
              serviceId: service.id,
              onSelect: onOpenBooking,
              showSelectButton: !isOwnProfile,
              type: _masterServiceTypeLabel(service.type),
              title: service.name,
              description: service.description,
              duration: _masterServiceDurationLabel(service),
              price: _masterServicePriceLabel(service),
              subPrice: _masterServiceSubPrice(service),
            ),
            const SizedBox(height: 12),
          ],
        ] else if (services != null) ...[
          const _NoPublicServicesCard(),
          const SizedBox(height: 12),
        ] else ...[
          _ServicePriceCard(
            serviceId: 'minimal',
            onSelect: onOpenBooking,
            showSelectButton: !isOwnProfile,
            type: 'Сеанс',
            title: 'Минимальная тату',
            description: 'Небольшие татуировки до 5 см',
            duration: '~ 1 час',
            price: '5 000 ₽',
            subPrice: 'минимальная стоимость сеанса',
          ),
          const SizedBox(height: 12),
          _ServicePriceCard(
            serviceId: 'small',
            onSelect: onOpenBooking,
            showSelectButton: !isOwnProfile,
            type: 'Сеанс',
            title: 'Маленькая тату',
            description: 'Татуировки от 5 до 15 см',
            duration: '~ 2 часа',
            price: '7 500 ₽',
            subPrice: '5 000 + 1 ч x 2 500',
          ),
          const SizedBox(height: 12),
          _ServicePriceCard(
            serviceId: 'medium',
            onSelect: onOpenBooking,
            showSelectButton: !isOwnProfile,
            type: 'Сеанс',
            title: 'Средняя тату',
            description: 'Татуировки от 15 до 25 см',
            duration: '~ 3 часа',
            price: '10 000 ₽',
            subPrice: '5 000 + 2 ч x 2 500',
          ),
          const SizedBox(height: 12),
          _ServicePriceCard(
            serviceId: 'large',
            onSelect: onOpenBooking,
            showSelectButton: !isOwnProfile,
            type: 'Сеанс',
            title: 'Большая тату',
            description: 'Татуировки от 25 см и более',
            duration: '~ 5 часов',
            price: '25 000 ₽',
            subPrice: 'изменено мастером вручную',
          ),
          const SizedBox(height: 12),
          _ServicePriceCard(
            serviceId: 'sketch',
            onSelect: onOpenBooking,
            showSelectButton: !isOwnProfile,
            type: 'Эскиз',
            title: 'Индивидуальный эскиз',
            description:
                'Разработка индивидуального эскиза по пожеланиям клиента',
            duration: '—',
            price: 'от 3 000 ₽',
            subPrice: 'цена зависит от сложности',
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: GuestDashboardTheme.accent.withValues(alpha: 0.05),
            border: Border.all(
              color: GuestDashboardTheme.accent.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'Цены указаны ориентировочно. Итоговая стоимость может измениться после консультации с учётом сложности, стиля, размера и места нанесения.',
            style: TextStyle(
              color: GuestDashboardTheme.accent,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ),
        if (!isOwnProfile) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => onOpenBooking(null),
            style: FilledButton.styleFrom(
              backgroundColor: GuestDashboardTheme.accent,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Записаться к мастеру'),
          ),
        ],
      ],
    );
  }
}

class _PremiumServicesSettingsSummaryCard extends StatelessWidget {
  const _PremiumServicesSettingsSummaryCard({this.settings});

  final MasterSettings? settings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final items = [
          _ServiceSettingPill(
            icon: Icons.spa_outlined,
            label: 'Минимальная стоимость',
            value: 'от ${_formatRubles(settings?.minSessionPrice ?? 5000)} ₽',
          ),
          _ServiceSettingPill(
            icon: Icons.schedule_outlined,
            label: 'Стоимость за час',
            value: '${_formatRubles(settings?.hourlyRate ?? 2500)} ₽ / час',
          ),
        ];

        return Container(
          padding: EdgeInsets.all(compact ? 16 : 18),
          decoration: _lightCardDecoration(),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    items[0],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1, color: Color(0xFFE5E7EB)),
                    ),
                    items[1],
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(child: items[0]),
                      const VerticalDivider(
                        width: 42,
                        thickness: 1,
                        color: Color(0xFFE5E7EB),
                      ),
                      Expanded(child: items[1]),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _ServicesSettingsSummaryCard extends StatelessWidget {
  const _ServicesSettingsSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: const Wrap(
        spacing: 18,
        runSpacing: 12,
        children: [
          _ServiceSettingPill(
            icon: Icons.payments_outlined,
            label: 'Минимальная стоимость',
            value: '5 000 ₽',
          ),
          _ServiceSettingPill(
            icon: Icons.schedule_outlined,
            label: 'Стоимость за час',
            value: '2 500 ₽',
          ),
          _ServiceSettingPill(
            icon: Icons.pause_circle_outline_rounded,
            label: 'Перерыв между клиентами',
            value: '30 минут',
          ),
        ],
      ),
    );
  }
}

class _ServiceSettingPill extends StatelessWidget {
  const _ServiceSettingPill({
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF667085), fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DynamicProfileTabs extends StatefulWidget {
  const _DynamicProfileTabs({
    required this.selectedTab,
    required this.onTabSelected,
    required this.reviewCount,
  });

  final _MasterProfileTab selectedTab;
  final ValueChanged<_MasterProfileTab> onTabSelected;
  final int reviewCount;

  @override
  State<_DynamicProfileTabs> createState() => _DynamicProfileTabsState();
}

class _DynamicProfileTabsState extends State<_DynamicProfileTabs> {
  final ScrollController _scrollController = ScrollController();
  final Map<_MasterProfileTab, GlobalKey> _tabKeys = {
    _MasterProfileTab.portfolio: GlobalKey(),
    _MasterProfileTab.about: GlobalKey(),
    _MasterProfileTab.services: GlobalKey(),
    _MasterProfileTab.reviews: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedTab());
  }

  @override
  void didUpdateWidget(covariant _DynamicProfileTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToSelectedTab(),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: _lightCardDecoration(),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            KeyedSubtree(
              key: _tabKeys[_MasterProfileTab.portfolio],
              child: _DynamicProfileTab(
                icon: Icons.grid_view_outlined,
                label: 'Портфолио',
                selected: widget.selectedTab == _MasterProfileTab.portfolio,
                onTap: () => widget.onTabSelected(_MasterProfileTab.portfolio),
              ),
            ),
            KeyedSubtree(
              key: _tabKeys[_MasterProfileTab.about],
              child: _DynamicProfileTab(
                icon: Icons.person_outline,
                label: 'О мастере',
                selected: widget.selectedTab == _MasterProfileTab.about,
                onTap: () => widget.onTabSelected(_MasterProfileTab.about),
              ),
            ),
            KeyedSubtree(
              key: _tabKeys[_MasterProfileTab.services],
              child: _DynamicProfileTab(
                icon: Icons.checklist_rtl_rounded,
                label: 'Услуги и цены',
                selected: widget.selectedTab == _MasterProfileTab.services,
                onTap: () => widget.onTabSelected(_MasterProfileTab.services),
              ),
            ),
            KeyedSubtree(
              key: _tabKeys[_MasterProfileTab.reviews],
              child: _DynamicProfileTab(
                icon: Icons.chat_bubble_outline,
                label: 'Отзывы (${widget.reviewCount})',
                selected: widget.selectedTab == _MasterProfileTab.reviews,
                onTap: () => widget.onTabSelected(_MasterProfileTab.reviews),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToSelectedTab() {
    if (!mounted || MediaQuery.sizeOf(context).width >= 720) {
      return;
    }

    final selectedContext = _tabKeys[widget.selectedTab]?.currentContext;
    if (selectedContext == null) {
      return;
    }

    Scrollable.ensureVisible(
      selectedContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: widget.selectedTab == _MasterProfileTab.services ? 0.52 : 0.5,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }
}

class _DynamicProfileTab extends StatelessWidget {
  const _DynamicProfileTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? GuestDashboardTheme.accent : Colors.transparent,
              width: 1.4,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? GuestDashboardTheme.accent
                  : const Color(0xFF6A7282),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? GuestDashboardTheme.accent
                    : const Color(0xFF6A7282),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs({
    required this.selectedTab,
    required this.onTabSelected,
    required this.reviewCount,
  });

  final _MasterProfileTab selectedTab;
  final ValueChanged<_MasterProfileTab> onTabSelected;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return _DynamicProfileTabs(
      selectedTab: selectedTab,
      onTabSelected: onTabSelected,
      reviewCount: reviewCount,
    );

    return Container(
      height: 54,
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: const [
            _ProfileTab(icon: Icons.grid_view_outlined, label: 'Портфолио'),
            _ProfileTab(icon: Icons.person_outline, label: 'О мастере'),
            _ProfileTab(
              icon: Icons.checklist_rtl_rounded,
              label: 'Услуги и цены',
              selected: true,
            ),
            _ProfileTab(icon: Icons.chat_bubble_outline, label: 'Отзывы'),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? GuestDashboardTheme.accent : Colors.transparent,
            width: 1.6,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: selected
                ? GuestDashboardTheme.accent
                : const Color(0xFF6A7282),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: selected
                  ? GuestDashboardTheme.accent
                  : const Color(0xFF6A7282),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPublicServicesCard extends StatelessWidget {
  const _NoPublicServicesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _lightCardDecoration(),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: GuestDashboardTheme.accent),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Мастер пока не добавил услуги для записи.',
              style: TextStyle(
                color: Color(0xFF364153),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicePriceCard extends StatefulWidget {
  const _ServicePriceCard({
    required this.serviceId,
    required this.onSelect,
    required this.showSelectButton,
    required this.type,
    required this.title,
    required this.description,
    required this.duration,
    required this.price,
    this.subPrice,
  });

  final String serviceId;
  final ValueChanged<String?> onSelect;
  final bool showSelectButton;
  final String type;
  final String title;
  final String description;
  final String duration;
  final String price;
  final String? subPrice;

  @override
  State<_ServicePriceCard> createState() => _ServicePriceCardState();
}

class _ServicePriceCardState extends State<_ServicePriceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 620;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 16 : 20,
          vertical: isCompact ? 16 : 18,
        ),
        decoration: _serviceCardDecoration(_hovered),
        child: isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServiceCopy(
                    title: widget.title,
                    description: widget.description,
                    duration: widget.duration,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _PriceBlock(
                          price: widget.price,
                          subPrice: widget.subPrice,
                        ),
                      ),
                      if (widget.showSelectButton) ...[
                        const SizedBox(width: 12),
                        _SelectServiceButton(
                          onTap: () => widget.onSelect(widget.serviceId),
                        ),
                      ],
                    ],
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ServiceCopy(
                      title: widget.title,
                      description: widget.description,
                      duration: widget.duration,
                    ),
                  ),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 170,
                    child: _PriceBlock(
                      price: widget.price,
                      subPrice: widget.subPrice,
                    ),
                  ),
                  if (widget.showSelectButton) ...[
                    const SizedBox(width: 18),
                    _SelectServiceButton(
                      onTap: () => widget.onSelect(widget.serviceId),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SelectServiceButton extends StatelessWidget {
  const _SelectServiceButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: GuestDashboardTheme.accent,
        side: const BorderSide(color: GuestDashboardTheme.accent),
        minimumSize: const Size(112, 40),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text(
        'Выбрать',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ServiceCopy extends StatelessWidget {
  const _ServiceCopy({
    required this.title,
    required this.description,
    required this.duration,
  });

  final String title;
  final String description;
  final String duration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(
            color: Color(0xFF6A7282),
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.schedule_outlined,
              size: 12,
              color: Color(0xFF667085),
            ),
            const SizedBox(width: 4),
            Text(
              duration,
              style: const TextStyle(color: Color(0xFF667085), fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _ServiceTypeChip extends StatelessWidget {
  const _ServiceTypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GuestDashboardTheme.accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: GuestDashboardTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.price, this.subPrice});

  final String price;
  final String? subPrice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          price,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subPrice != null) ...[
          const SizedBox(height: 4),
          Text(
            subPrice!,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _MobileProfileNav extends StatelessWidget {
  const _MobileProfileNav({
    required this.onOpenHome,
    required this.onOpenSearch,
    this.onOpenRecommendations,
  });

  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback? onOpenRecommendations;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 65,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MobileNavItem(
            icon: Icons.home_outlined,
            label: 'Главная',
            onTap: onOpenHome,
          ),
          _MobileNavItem(
            icon: Icons.search_rounded,
            label: 'Поиск',
            onTap: onOpenSearch,
          ),
          _MobileNavItem(
            icon: Icons.auto_awesome_outlined,
            label: 'Лента',
            onTap: onOpenRecommendations ?? onOpenSearch,
          ),
          const _MobileNavItem(
            icon: Icons.person_outline,
            label: 'Профиль',
            selected: true,
          ),
        ],
      ),
    );
  }
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? GuestDashboardTheme.accent
        : const Color(0xFF6A7282);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: const [
      BoxShadow(color: Color(0x16000000), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x0C000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
  );
}

BoxDecoration _lightCardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE5E7EB)),
    boxShadow: const [
      BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3)),
    ],
  );
}

BoxDecoration _serviceCardDecoration(bool hovered) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    border: Border.all(
      color: hovered
          ? GuestDashboardTheme.accent.withValues(alpha: 0.42)
          : const Color(0xFFE5E7EB),
    ),
    boxShadow: const [
      BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
    ],
  );
}

class GuestMasterProfileAssets {
  static const String mariaProfile =
      'assets/guest_master_profile/maria_profile.png';
  static const String portfolio01 =
      'assets/guest_master_profile/portfolio_01.png';
  static const String portfolio02 =
      'assets/guest_master_profile/portfolio_02.png';
  static const String portfolio03 =
      'assets/guest_master_profile/portfolio_03.png';
  static const String portfolio04 =
      'assets/guest_master_profile/portfolio_04.png';
  static const String portfolio05 =
      'assets/guest_master_profile/portfolio_05.png';
  static const String portfolio06 =
      'assets/guest_master_profile/portfolio_06.png';
  static const String portfolio07 =
      'assets/guest_master_profile/portfolio_07.png';
  static const String portfolio08 =
      'assets/guest_master_profile/portfolio_08.png';
  static const String portfolio09 =
      'assets/guest_master_profile/portfolio_09.png';
  static const String portfolio10 =
      'assets/guest_master_profile/portfolio_10.png';
  static const String portfolio11 =
      'assets/guest_master_profile/portfolio_11.png';
  static const String svetlanaReview =
      'assets/guest_master_profile/review_svetlana.png';
}
