import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../city/city_catalog.dart';
import '../mock/guest_search_mock_data.dart';
import '../models.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/city_autocomplete_field.dart';
import '../widgets/master_search_card.dart';
import 'guest_dashboard_screen.dart';

class GuestSearchFilters {
  GuestSearchFilters({
    required this.selectedCategory,
    required this.selectedCity,
    required this.selectedSort,
    required this.searchQuery,
    required this.priceRange,
    this.selectedCityOption,
    Set<String> selectedStyles = const <String>{},
  }) : selectedStyles = Set.unmodifiable(selectedStyles);

  factory GuestSearchFilters.initial() {
    return GuestSearchFilters(
      selectedCategory: guestTattooCategory,
      selectedCity: _GuestSearchScreenState._allCitiesLabel,
      selectedSort:
          '\u041f\u043e \u043f\u043e\u043f\u0443\u043b\u044f\u0440\u043d\u043e\u0441\u0442\u0438',
      searchQuery: '',
      priceRange: const RangeValues(0, 20000),
    );
  }

  final String selectedCategory;
  final String selectedCity;
  final CityOption? selectedCityOption;
  final String selectedSort;
  final String searchQuery;
  final RangeValues priceRange;
  final Set<String> selectedStyles;
}

class GuestSearchScreen extends StatefulWidget {
  const GuestSearchScreen({
    super.key,
    required this.onOpenHome,
    required this.onOpenLogin,
    required this.onOpenRegister,
    required this.onOpenMasterProfile,
    this.api,
    this.sessionToken,
    this.onOpenBooking,
    this.onOpenRecommendations,
    this.onOpenFavorites,
    this.onOpenMessages,
    this.onOpenMyProfile,
    this.isAuthenticated = false,
    this.currentUsername,
    this.currentUserRole,
    this.initialFilters,
    this.onFiltersChanged,
    this.userName = 'Артём',
  });

  final VoidCallback onOpenHome;
  final VoidCallback onOpenLogin;
  final VoidCallback onOpenRegister;
  final ValueChanged<String> onOpenMasterProfile;
  final InkConnectApiClient? api;
  final String? sessionToken;
  final ValueChanged<String>? onOpenBooking;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenMyProfile;
  final bool isAuthenticated;
  final String? currentUsername;
  final String? currentUserRole;
  final GuestSearchFilters? initialFilters;
  final ValueChanged<GuestSearchFilters>? onFiltersChanged;
  final String userName;

  @override
  State<GuestSearchScreen> createState() => _GuestSearchScreenState();
}

class _GuestSearchScreenState extends State<GuestSearchScreen> {
  static const String _hiddenCityLabel =
      '\u0413\u043e\u0440\u043e\u0434 \u0441\u043a\u0440\u044b\u0442';
  static const String _allCitiesLabel = 'Все города';

  late final TextEditingController _cityFilterController;
  final Set<String> _selectedStyles = <String>{};
  String _selectedCategory = guestTattooCategory;
  String _selectedCity = _allCitiesLabel;
  CityOption? _selectedCityOption;
  String _selectedSort = 'По популярности';
  String _searchQuery = '';
  RangeValues _priceRange = const RangeValues(0, 20000);
  List<GuestMasterSearchItem>? _backendMasters;
  final Set<String> _favoriteActionIds = <String>{};
  Timer? _searchDebounce;
  int _searchRequestNonce = 0;
  bool _loading = true;
  String? _loadError;

  bool get _isPiercing => _selectedCategory == guestPiercingCategory;

  List<String> get _activeStyleOptions =>
      _isPiercing ? guestPiercingStyles : guestTattooStyles;

  List<GuestMasterSearchItem> get _activeMasters {
    final backendMasters = _backendMasters;
    return backendMasters ?? const <GuestMasterSearchItem>[];
  }

  String get _descriptionText => _isPiercing
      ? 'Найдите мастера по пирсингу по виду прокола, городу, рейтингу и цене'
      : 'Найдите мастера по татуировке по стилю, городу, рейтингу и цене';

  String get _styleGroupLabel => _isPiercing ? 'Вид пирсинга' : 'Стиль';

  @override
  void initState() {
    super.initState();
    _restoreFilters(widget.initialFilters ?? GuestSearchFilters.initial());
    _loadBackendMasters();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _cityFilterController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GuestSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken) {
      _loadBackendMasters();
    }
  }

  void _restoreFilters(GuestSearchFilters filters) {
    _selectedCategory = filters.selectedCategory;
    _selectedCity = filters.selectedCity;
    _selectedCityOption = filters.selectedCityOption;
    _selectedSort = filters.selectedSort;
    _searchQuery = filters.searchQuery;
    _priceRange = filters.priceRange;
    _selectedStyles
      ..clear()
      ..addAll(filters.selectedStyles);

    final cityText = filters.selectedCityOption?.displayName ??
        (filters.selectedCity == _allCitiesLabel ? '' : filters.selectedCity);
    _cityFilterController = TextEditingController(text: cityText);
  }

  GuestSearchFilters get _currentFilters => GuestSearchFilters(
        selectedCategory: _selectedCategory,
        selectedCity: _selectedCity,
        selectedCityOption: _selectedCityOption,
        selectedSort: _selectedSort,
        searchQuery: _searchQuery,
        priceRange: _priceRange,
        selectedStyles: _selectedStyles,
      );

  void _notifyFiltersChanged() {
    widget.onFiltersChanged?.call(_currentFilters);
  }

  List<GuestMasterSearchItem> get _visibleMasters {
    final masters = _activeMasters.where((master) {
      final matchesCity =
          _selectedCity == _allCitiesLabel || master.city == _selectedCity;
      final matchesStyle =
          _selectedStyles.isEmpty ||
          master.tags.any((tag) => _selectedStyles.contains(tag));
      final matchesPrice =
          master.priceValue >= _priceRange.start &&
          master.priceValue <= _priceRange.end;
      final query = _searchQuery.trim().toLowerCase();
      final searchableName = master.showFullName ? master.name : '';
      final searchableStudio = master.studioName.trim();
      final searchableTags = master.tags.join(' ');
      final matchesSearch =
          query.isEmpty ||
          master.username.toLowerCase().contains(query) ||
          master.handle.toLowerCase().contains(query) ||
          searchableName.toLowerCase().contains(query) ||
          searchableStudio.toLowerCase().contains(query) ||
          master.city.toLowerCase().contains(query) ||
          master.description.toLowerCase().contains(query) ||
          searchableTags.toLowerCase().contains(query);
      return matchesCity && matchesStyle && matchesPrice && matchesSearch;
    }).toList();

    if (_selectedSort == 'Сначала дешевле') {
      masters.sort((a, b) => a.priceValue.compareTo(b.priceValue));
    } else if (_selectedSort == 'Сначала дороже') {
      masters.sort((a, b) => b.priceValue.compareTo(a.priceValue));
    } else {
      masters.sort((a, b) => b.rating.compareTo(a.rating));
    }

    return masters;
  }

  void _changeCategory(String value) {
    setState(() {
      _selectedCategory = value;
      _selectedStyles.clear();
      _priceRange = const RangeValues(0, 20000);
    });
    _notifyFiltersChanged();
  }

  void _selectCity(CityOption? option) {
    setState(() {
      _selectedCityOption = option;
      _selectedCity = option?.displayName ?? _allCitiesLabel;
      if (option == null) {
        _cityFilterController.clear();
      }
    });
    _notifyFiltersChanged();
  }

  void _handleCityInputChanged() {
    final selected = _selectedCityOption;
    if (_cityFilterController.text.trim().isEmpty) {
      _selectCity(null);
      return;
    }
    if (selected != null &&
        selected.displayName != _cityFilterController.text.trim()) {
      setState(() {
        _selectedCityOption = null;
        _selectedCity = _allCitiesLabel;
      });
      _notifyFiltersChanged();
    }
  }

  void _handleSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
    _notifyFiltersChanged();

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadBackendMasters(query: _searchQuery);
    });
  }

  void _changeSort(String value) {
    setState(() {
      _selectedSort = value;
    });
    _notifyFiltersChanged();
  }

  void _toggleStyle(String style) {
    setState(() {
      if (_selectedStyles.contains(style)) {
        _selectedStyles.remove(style);
      } else {
        _selectedStyles.add(style);
      }
    });
    _notifyFiltersChanged();
  }

  void _changePrice(RangeValues range) {
    setState(() {
      _priceRange = range;
    });
    _notifyFiltersChanged();
  }

  void _updateSheetFilters(StateSetter setSheetState, VoidCallback update) {
    setSheetState(update);
    setState(() {});
    _notifyFiltersChanged();
  }

  Future<void> _loadBackendMasters({String? query}) async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _backendMasters = const <GuestMasterSearchItem>[];
        _loading = false;
        _loadError = 'Не удалось загрузить поиск: backend API недоступен.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });
    final requestNonce = ++_searchRequestNonce;
    final backendQuery = (query ?? _searchQuery).trim();
    try {
      final response = await api.searchMasters(
        query: backendQuery,
        limit: 200,
        sessionToken: widget.sessionToken,
      );
      final favorites = await _loadFavoriteIds(api);
      if (!mounted || requestNonce != _searchRequestNonce) {
        return;
      }
      setState(() {
        _backendMasters = [
          for (var i = 0; i < response.items.length; i++)
            _mapBackendMaster(response.items[i], i, favorites),
        ];
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || requestNonce != _searchRequestNonce) {
        return;
      }
      setState(() {
        _backendMasters = const <GuestMasterSearchItem>[];
        _loading = false;
        _loadError = 'Не удалось загрузить мастеров: $error';
      });
    }
  }

  Future<Set<String>> _loadFavoriteIds(InkConnectApiClient api) async {
    final token = widget.sessionToken;
    if (token == null || token.isEmpty) {
      return const <String>{};
    }
    try {
      final favorites = await api.getFavoriteMasters(sessionToken: token);
      return favorites
          .map((master) => master.id)
          .where((id) => id.trim().isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  GuestMasterSearchItem _mapBackendMaster(
    MasterProfile master,
    int index,
    Set<String> favoriteIds,
  ) {
    const assets = [
      GuestDashboardAssets.maria,
      GuestDashboardAssets.anna,
      GuestDashboardAssets.dmitry,
      GuestDashboardAssets.alexander,
    ];
    final displayName = master.displayName.trim().isNotEmpty
        ? master.displayName.trim()
        : '@${master.username}';
    final priceValue = master.minSessionPrice > 0
        ? master.minSessionPrice
        : (master.services.isNotEmpty ? master.services.first.price : 0);
    final tags = master.styles
        .where((style) => style.trim().isNotEmpty)
        .toList(growable: false);

    return GuestMasterSearchItem(
      id: master.id,
      username: master.username,
      name: displayName,
      studioName: master.studioName.trim(),
      city: master.city.trim().isEmpty ? _hiddenCityLabel : master.city.trim(),
      rating: master.rating > 0 ? master.rating : 0,
      reviewCount: master.reviewCount,
      priceLabel: priceValue > 0
          ? '\u043e\u0442 ${_formatSearchRubles(priceValue)} \u20bd'
          : '',
      priceValue: priceValue,
      tags: tags,
      description: master.bio.trim().isNotEmpty
          ? master.bio.trim()
          : master.category.trim(),
      assetPath: assets[index % assets.length],
      avatarUrl: master.avatarUrl,
      showFullName: !displayName.startsWith('@'),
      isFavorite: master.isFavorite || favoriteIds.contains(master.id),
    );
  }

  Future<void> _toggleFavorite(GuestMasterSearchItem master) async {
    final api = widget.api;
    final token = widget.sessionToken;
    if (api == null || token == null || token.isEmpty) {
      _showSnackBar('Войдите, чтобы добавлять мастеров в избранное');
      return;
    }
    if (_isOwnMasterSearchItem(
      master,
      currentUsername: widget.currentUsername,
      currentUserRole: widget.currentUserRole,
    )) {
      _showSnackBar('Свой профиль нельзя добавить в избранное');
      return;
    }
    if (master.id.trim().isEmpty || _favoriteActionIds.contains(master.id)) {
      return;
    }

    final nextValue = !master.isFavorite;
    _setFavoriteState(master.id, nextValue);
    _favoriteActionIds.add(master.id);

    try {
      if (nextValue) {
        await api.addFavoriteMaster(sessionToken: token, masterId: master.id);
        _showSnackBar('Добавлено в избранное');
      } else {
        await api.removeFavoriteMaster(
          sessionToken: token,
          masterId: master.id,
        );
        _showSnackBar('Удалено из избранного');
      }
    } catch (_) {
      if (mounted) {
        _setFavoriteState(master.id, !nextValue);
        _showSnackBar('Не удалось обновить избранное');
      }
    } finally {
      _favoriteActionIds.remove(master.id);
    }
  }

  void _setFavoriteState(String masterId, bool value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _backendMasters = _backendMasters
          ?.map(
            (item) =>
                item.id == masterId ? item.copyWith(isFavorite: value) : item,
          )
          .toList();
    });
  }

  void _showSnackBar(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatSearchRubles(int value) {
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1100;
    final isTablet = width >= 760;
    final horizontalPadding = isDesktop ? 31.0 : (isTablet ? 24.0 : 16.0);
    final masters = _visibleMasters;
    const desktopScale = 0.9;

    return Scaffold(
      backgroundColor: GuestDashboardTheme.background,
      bottomNavigationBar: widget.isAuthenticated && !isDesktop
          ? AuthenticatedMobileNavigation(
              activeItem: AuthenticatedMobileNavItem.search,
              onOpenHome: widget.onOpenHome,
              onOpenSearch: () {},
              onOpenMessages:
                  widget.onOpenMessages ?? () => _showMockAction('Сообщения'),
              onOpenRecommendations:
                  widget.onOpenRecommendations ?? widget.onOpenHome,
              onOpenCareJournal: () => _showMockAction('Журнал ухода'),
            )
          : null,
      body: Column(
        children: [
          GuestHeader(
            isDesktop: isDesktop,
            horizontalPadding: horizontalPadding,
            onOpenLogin: widget.onOpenLogin,
            onOpenRegister: widget.onOpenRegister,
            onOpenHome: widget.onOpenHome,
            onOpenMasters: () {},
            activeSection: GuestHeaderSection.search,
            isAuthenticated: widget.isAuthenticated,
            userName: widget.userName,
            onOpenRecommendations: widget.onOpenRecommendations,
            onOpenFavorites: widget.onOpenFavorites,
            onOpenProfile: widget.onOpenMyProfile,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                isDesktop ? 39 : 16,
                horizontalPadding,
                widget.isAuthenticated && !isDesktop ? 96 : 28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  if (_loadError != null) ...[
                    const SizedBox(height: 12),
                    _SearchErrorState(
                      message: _loadError!,
                      onRetry: _loadBackendMasters,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (isDesktop)
                    Transform.scale(
                      scale: desktopScale,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: (width - horizontalPadding * 2) / desktopScale,
                        child: _DesktopSearchLayout(
                          masters: masters,
                          descriptionText: _descriptionText,
                          selectedCategory: _selectedCategory,
                          selectedCity: _selectedCity,
                          selectedCityOption: _selectedCityOption,
                          cityController: _cityFilterController,
                          selectedSort: _selectedSort,
                          searchQuery: _searchQuery,
                          selectedStyles: _selectedStyles,
                          styleOptions: _activeStyleOptions,
                          styleGroupLabel: _styleGroupLabel,
                          priceRange: _priceRange,
                          onChangeCategory: _changeCategory,
                          onSelectCity: _selectCity,
                          onCityInputChanged: _handleCityInputChanged,
                          onResetCity: () => _selectCity(null),
                          onChangeSort: _changeSort,
                          onChangeSearch: _handleSearchChanged,
                          onToggleStyle: _toggleStyle,
                          onChangePrice: _changePrice,
                          currentUsername: widget.currentUsername,
                          currentUserRole: widget.currentUserRole,
                          onOpenMyProfile: widget.onOpenMyProfile,
                          onOpenProfile: widget.onOpenMasterProfile,
                          onOpenBooking:
                              widget.onOpenBooking ??
                              ((_) => widget.onOpenLogin()),
                          onToggleFavorite: _toggleFavorite,
                        ),
                      ),
                    )
                  else
                    _MobileSearchLayout(
                      masters: masters,
                      selectedSort: _selectedSort,
                      searchQuery: _searchQuery,
                      onChangeSort: _changeSort,
                      onChangeSearch: _handleSearchChanged,
                      onOpenFilters: () => _openFiltersSheet(context),
                      currentUsername: widget.currentUsername,
                      currentUserRole: widget.currentUserRole,
                      onOpenMyProfile: widget.onOpenMyProfile,
                      onOpenProfile: widget.onOpenMasterProfile,
                      onOpenBooking:
                          widget.onOpenBooking ?? ((_) => widget.onOpenLogin()),
                      onToggleFavorite: _toggleFavorite,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFiltersSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _FiltersPanel(
                      selectedCategory: _selectedCategory,
                      selectedCity: _selectedCity,
                      selectedCityOption: _selectedCityOption,
                      cityController: _cityFilterController,
                      selectedStyles: _selectedStyles,
                      styleOptions: _activeStyleOptions,
                      styleGroupLabel: _styleGroupLabel,
                      priceRange: _priceRange,
                      compactTitle: true,
                      showApplyButton: true,
                      onChangeCategory: (value) {
                        _updateSheetFilters(setSheetState, () {
                          _selectedCategory = value;
                          _selectedStyles.clear();
                          _priceRange = const RangeValues(0, 20000);
                        });
                      },
                      onSelectCity: (option) {
                        _updateSheetFilters(setSheetState, () {
                          _selectedCityOption = option;
                          _selectedCity =
                              option?.displayName ?? _allCitiesLabel;
                          if (option == null) {
                            _cityFilterController.clear();
                          }
                        });
                      },
                      onCityInputChanged: () {
                        final selected = _selectedCityOption;
                        final text = _cityFilterController.text.trim();
                        _updateSheetFilters(setSheetState, () {
                          if (text.isEmpty) {
                            _selectedCityOption = null;
                            _selectedCity = _allCitiesLabel;
                          } else if (selected != null &&
                              selected.displayName != text) {
                            _selectedCityOption = null;
                            _selectedCity = _allCitiesLabel;
                          }
                        });
                      },
                      onResetCity: () {
                        _updateSheetFilters(setSheetState, () {
                          _selectedCityOption = null;
                          _selectedCity = _allCitiesLabel;
                          _cityFilterController.clear();
                        });
                      },
                      onToggleStyle: (style) {
                        _updateSheetFilters(setSheetState, () {
                          if (_selectedStyles.contains(style)) {
                            _selectedStyles.remove(style);
                          } else {
                            _selectedStyles.add(style);
                          }
                        });
                      },
                      onChangePrice: (range) {
                        _updateSheetFilters(setSheetState, () {
                          _priceRange = range;
                        });
                      },
                      onApply: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2D48A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFF9A6700)),
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
          TextButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

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
      child: const Text(
        'По вашему запросу пока нет мастеров.',
        style: TextStyle(color: Color(0xFF355072), fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DesktopSearchLayout extends StatelessWidget {
  const _DesktopSearchLayout({
    required this.masters,
    required this.descriptionText,
    required this.selectedCategory,
    required this.selectedCity,
    required this.selectedCityOption,
    required this.cityController,
    required this.selectedSort,
    required this.searchQuery,
    required this.selectedStyles,
    required this.styleOptions,
    required this.styleGroupLabel,
    required this.priceRange,
    required this.onChangeCategory,
    required this.onSelectCity,
    required this.onCityInputChanged,
    required this.onResetCity,
    required this.onChangeSort,
    required this.onChangeSearch,
    required this.onToggleStyle,
    required this.onChangePrice,
    required this.currentUsername,
    required this.currentUserRole,
    required this.onOpenMyProfile,
    required this.onOpenProfile,
    required this.onOpenBooking,
    required this.onToggleFavorite,
  });

  final List<GuestMasterSearchItem> masters;
  final String descriptionText;
  final String selectedCategory;
  final String selectedCity;
  final CityOption? selectedCityOption;
  final TextEditingController cityController;
  final String selectedSort;
  final String searchQuery;
  final Set<String> selectedStyles;
  final List<String> styleOptions;
  final String styleGroupLabel;
  final RangeValues priceRange;
  final ValueChanged<String> onChangeCategory;
  final ValueChanged<CityOption?> onSelectCity;
  final VoidCallback onCityInputChanged;
  final VoidCallback onResetCity;
  final ValueChanged<String> onChangeSort;
  final ValueChanged<String> onChangeSearch;
  final ValueChanged<String> onToggleStyle;
  final ValueChanged<RangeValues> onChangePrice;
  final String? currentUsername;
  final String? currentUserRole;
  final VoidCallback? onOpenMyProfile;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<String> onOpenBooking;
  final ValueChanged<GuestMasterSearchItem> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Поиск мастеров',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: 44,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0B2A5B),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          descriptionText,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: 18,
            color: const Color(0xFF355072),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 327,
              child: _FiltersPanel(
                selectedCategory: selectedCategory,
                selectedCity: selectedCity,
                selectedCityOption: selectedCityOption,
                cityController: cityController,
                selectedStyles: selectedStyles,
                styleOptions: styleOptions,
                styleGroupLabel: styleGroupLabel,
                priceRange: priceRange,
                onChangeCategory: onChangeCategory,
                onSelectCity: onSelectCity,
                onCityInputChanged: onCityInputChanged,
                onResetCity: onResetCity,
                onToggleStyle: onToggleStyle,
                onChangePrice: onChangePrice,
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _mastersCountLabel(masters.length),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 18,
                          color: const Color(0xFF355072),
                        ),
                      ),
                      const SizedBox(width: 28),
                      Expanded(
                        child: _SearchInput(
                          value: searchQuery,
                          onChanged: onChangeSearch,
                        ),
                      ),
                      const SizedBox(width: 28),
                      SizedBox(
                        width: 180,
                        child: _GuestDropdown(
                          value: selectedSort,
                          options: const [
                            'По популярности',
                            'Сначала дешевле',
                            'Сначала дороже',
                          ],
                          onChanged: onChangeSort,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (masters.isEmpty)
                    const _SearchEmptyState()
                  else
                    ...masters.map(
                      (master) => Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: MasterSearchCard(
                          master: master,
                          layout: MasterCardLayout.desktop,
                          isOwnMaster: _isOwnMasterSearchItem(
                            master,
                            currentUsername: currentUsername,
                            currentUserRole: currentUserRole,
                          ),
                          onOpenMyProfile: onOpenMyProfile,
                          onOpenProfile: onOpenProfile,
                          onOpenBooking: onOpenBooking,
                          onToggleFavorite: onToggleFavorite,
                          action: MasterCardAction.favorite,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MobileSearchLayout extends StatelessWidget {
  const _MobileSearchLayout({
    required this.masters,
    required this.selectedSort,
    required this.searchQuery,
    required this.onChangeSort,
    required this.onChangeSearch,
    required this.onOpenFilters,
    required this.currentUsername,
    required this.currentUserRole,
    required this.onOpenMyProfile,
    required this.onOpenProfile,
    required this.onOpenBooking,
    required this.onToggleFavorite,
  });

  final List<GuestMasterSearchItem> masters;
  final String selectedSort;
  final String searchQuery;
  final ValueChanged<String> onChangeSort;
  final ValueChanged<String> onChangeSearch;
  final VoidCallback onOpenFilters;
  final String? currentUsername;
  final String? currentUserRole;
  final VoidCallback? onOpenMyProfile;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<String> onOpenBooking;
  final ValueChanged<GuestMasterSearchItem> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Поиск мастеров',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0B2A5B),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onOpenFilters,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Фильтры'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(118, 38),
                foregroundColor: const Color(0xFF0B2A5B),
                side: const BorderSide(color: Color(0xFFD7DDE6)),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              _mastersCountLabel(masters.length),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 17,
                color: const Color(0xFF355072),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 164,
              child: _GuestDropdown(
                value: selectedSort,
                options: const [
                  'По популярности',
                  'Сначала дешевле',
                  'Сначала дороже',
                ],
                onChanged: onChangeSort,
                dense: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SearchInput(
          value: searchQuery,
          onChanged: onChangeSearch,
          dense: true,
        ),
        const SizedBox(height: 16),
        if (masters.isEmpty)
          const _SearchEmptyState()
        else
          ...masters.map(
            (master) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MasterSearchCard(
                master: master,
                layout: MasterCardLayout.mobile,
                isOwnMaster: _isOwnMasterSearchItem(
                  master,
                  currentUsername: currentUsername,
                  currentUserRole: currentUserRole,
                ),
                onOpenMyProfile: onOpenMyProfile,
                onOpenProfile: onOpenProfile,
                onOpenBooking: onOpenBooking,
                onToggleFavorite: onToggleFavorite,
                action: MasterCardAction.favorite,
              ),
            ),
          ),
      ],
    );
  }
}

bool _isOwnMasterSearchItem(
  GuestMasterSearchItem master, {
  required String? currentUsername,
  required String? currentUserRole,
}) {
  final username = currentUsername?.trim().toLowerCase() ?? '';
  if (username.isEmpty || currentUserRole?.trim() != 'master') {
    return false;
  }
  return master.username.trim().toLowerCase() == username;
}

String _mastersCountLabel(int count) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  final word = mod100 >= 11 && mod100 <= 14
      ? 'мастеров'
      : (mod10 >= 1 && mod10 <= 4 ? 'мастера' : 'мастеров');
  return '$count $word';
}

class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.selectedCategory,
    required this.selectedCity,
    required this.selectedCityOption,
    required this.cityController,
    required this.selectedStyles,
    required this.styleOptions,
    required this.styleGroupLabel,
    required this.priceRange,
    required this.onChangeCategory,
    required this.onSelectCity,
    required this.onCityInputChanged,
    required this.onResetCity,
    required this.onToggleStyle,
    required this.onChangePrice,
    this.compactTitle = false,
    this.showApplyButton = false,
    this.onApply,
  });

  final String selectedCategory;
  final String selectedCity;
  final CityOption? selectedCityOption;
  final TextEditingController cityController;
  final Set<String> selectedStyles;
  final List<String> styleOptions;
  final String styleGroupLabel;
  final RangeValues priceRange;
  final ValueChanged<String> onChangeCategory;
  final ValueChanged<CityOption?> onSelectCity;
  final VoidCallback onCityInputChanged;
  final VoidCallback onResetCity;
  final ValueChanged<String> onToggleStyle;
  final ValueChanged<RangeValues> onChangePrice;
  final bool compactTitle;
  final bool showApplyButton;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compactTitle ? 20 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFEBE7E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Фильтры',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: compactTitle ? 28 : 24,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0B2A5B),
            ),
          ),
          const SizedBox(height: 26),
          const _FilterLabel('Категория'),
          const SizedBox(height: 10),
          _GuestDropdown(
            value: selectedCategory,
            options: const [guestTattooCategory, guestPiercingCategory],
            onChanged: onChangeCategory,
          ),
          const SizedBox(height: 20),
          _FilterLabel(styleGroupLabel),
          const SizedBox(height: 12),
          ...styleOptions.map(
            (style) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StyleCheckbox(
                label: style,
                value: selectedStyles.contains(style),
                onChanged: () => onToggleStyle(style),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(child: _FilterLabel('Город')),
              if (selectedCity != _GuestSearchScreenState._allCitiesLabel)
                TextButton(
                  onPressed: onResetCity,
                  child: const Text('Все города'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          CityAutocompleteField(
            controller: cityController,
            selectedOption: selectedCityOption,
            labelText: 'Город',
            hintText: 'Все города',
            onSelected: onSelectCity,
            onChanged: onCityInputChanged,
          ),
          const SizedBox(height: 20),
          const _FilterLabel('Цена'),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: GuestDashboardTheme.accent,
              inactiveTrackColor: const Color(0xFFD6DDD6),
              thumbColor: Colors.white,
              overlayColor: GuestDashboardTheme.accent.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 4,
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 8,
              ),
            ),
            child: RangeSlider(
              values: priceRange,
              min: 0,
              max: 20000,
              onChanged: onChangePrice,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _PricePill(
                  prefix: 'от',
                  value: priceRange.start.round(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PricePill(prefix: 'до', value: priceRange.end.round()),
              ),
            ],
          ),
          if (showApplyButton) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onApply,
                style: FilledButton.styleFrom(
                  backgroundColor: GuestDashboardTheme.accent,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Показать мастеров'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopMasterCard extends StatefulWidget {
  const _DesktopMasterCard({
    required this.master,
    required this.isOwnMaster,
    required this.onOpenMyProfile,
    required this.onOpenProfile,
    required this.onOpenBooking,
    required this.onToggleFavorite,
  });

  final GuestMasterSearchItem master;
  final bool isOwnMaster;
  final VoidCallback? onOpenMyProfile;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<String> onOpenBooking;
  final ValueChanged<GuestMasterSearchItem> onToggleFavorite;

  @override
  State<_DesktopMasterCard> createState() => _DesktopMasterCardState();
}

class _DesktopMasterCardState extends State<_DesktopMasterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final master = widget.master;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openProfile,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _hovered
                      ? const Color(0x1F0F172A)
                      : const Color(0x120F172A),
                  blurRadius: _hovered ? 20 : 14,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: _hovered
                    ? GuestDashboardTheme.accent.withValues(alpha: 0.42)
                    : const Color(0xFFEBE7E0),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    master.assetPath,
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
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
                                  master.handle,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0B2A5B),
                                      ),
                                ),
                                if (master.showFullName) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    master.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF355072),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 18,
                                      color: Color(0xFFFFC107),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      master.ratingLabel,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Color(0xFF355072),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 16,
                                      color: Color(0xFF355072),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      master.city,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Color(0xFF355072),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                master.priceLabel,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0B2A5B),
                                    ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Минимальная цена',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF6A7282),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: master.tags
                            .map((tag) => _TagPill(label: tag))
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          master.description,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.35,
                            color: Color(0xFF355072),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.isOwnMaster)
                              const _OwnMasterBadge(minWidth: 178, height: 48)
                            else
                              FilledButton(
                                onPressed: () =>
                                    widget.onOpenBooking(master.username),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(178, 48),
                                  backgroundColor: GuestDashboardTheme.accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Записаться',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            if (!widget.isOwnMaster) ...[
                              const SizedBox(width: 16),
                              _BookmarkButton(
                                selected: master.isFavorite,
                                onPressed: () =>
                                    widget.onToggleFavorite(master),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openProfile() {
    if (widget.isOwnMaster) {
      final openMyProfile = widget.onOpenMyProfile;
      if (openMyProfile != null) {
        openMyProfile();
        return;
      }
    }
    widget.onOpenProfile(widget.master.username);
  }
}

class _MobileMasterCard extends StatelessWidget {
  const _MobileMasterCard({
    required this.master,
    required this.isOwnMaster,
    required this.onOpenMyProfile,
    required this.onOpenProfile,
    required this.onOpenBooking,
    required this.onToggleFavorite,
  });

  final GuestMasterSearchItem master;
  final bool isOwnMaster;
  final VoidCallback? onOpenMyProfile;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<String> onOpenBooking;
  final ValueChanged<GuestMasterSearchItem> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openProfile,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFFEBE7E0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      master.assetPath,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          master.handle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0B2A5B),
                              ),
                        ),
                        if (master.showFullName) ...[
                          const SizedBox(height: 3),
                          Text(
                            master.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF355072),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: Color(0xFFFFC107),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              master.ratingLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF355072),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: Color(0xFF355072),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              master.city,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF355072),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          master.priceLabel,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0B2A5B),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: master.tags
                    .map((tag) => _TagPill(label: tag))
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              Text(
                master.description,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: Color(0xFF355072),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: isOwnMaster
                        ? const _OwnMasterBadge(height: 46)
                        : FilledButton(
                            onPressed: () => onOpenBooking(master.username),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              backgroundColor: GuestDashboardTheme.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Записаться',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                  if (!isOwnMaster) ...[
                    const SizedBox(width: 12),
                    _BookmarkButton(
                      compact: true,
                      selected: master.isFavorite,
                      onPressed: () => onToggleFavorite(master),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProfile() {
    if (isOwnMaster) {
      final openMyProfile = onOpenMyProfile;
      if (openMyProfile != null) {
        openMyProfile();
        return;
      }
    }
    onOpenProfile(master.username);
  }
}

class _OwnMasterBadge extends StatelessWidget {
  const _OwnMasterBadge({this.minWidth, required this.height});

  final double? minWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: minWidth ?? 0),
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GuestDashboardTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: GuestDashboardTheme.accent.withValues(alpha: 0.22),
        ),
      ),
      child: const Text(
        'Да, это Вы',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: GuestDashboardTheme.accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({
    required this.onPressed,
    required this.selected,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 36.0;

    return Tooltip(
      message: selected ? 'В избранном' : 'В избранное',
      child: Material(
        color: selected
            ? GuestDashboardTheme.accent.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              selected ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              size: compact ? 19 : 21,
              color: GuestDashboardTheme.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Поиск по нику или имени мастера',
        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF8A94A6)),
        isDense: dense,
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: dense ? 12 : 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD7DDE6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD7DDE6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: GuestDashboardTheme.accent),
        ),
      ),
      style: const TextStyle(fontSize: 16, color: Color(0xFF0B2A5B)),
    );
  }
}

class _GuestDropdown extends StatelessWidget {
  const _GuestDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
    this.dense = false,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7DDE6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: const TextStyle(fontSize: 16, color: Color(0xFF0B2A5B)),
          dropdownColor: Colors.white,
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
          items: options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Color(0xFF0B2A5B),
      ),
    );
  }
}

class _StyleCheckbox extends StatelessWidget {
  const _StyleCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: (_) => onChanged(),
              activeColor: GuestDashboardTheme.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              side: const BorderSide(color: Color(0xFF8A94A6)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: Color(0xFF355072)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.prefix, required this.value});

  final String prefix;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7DDE6)),
      ),
      child: Row(
        children: [
          Text(
            prefix,
            style: const TextStyle(fontSize: 16, color: Color(0xFF6A7282)),
          ),
          const SizedBox(width: 14),
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, color: Color(0xFF0B2A5B)),
          ),
        ],
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, color: Color(0xFF355072)),
      ),
    );
  }
}
