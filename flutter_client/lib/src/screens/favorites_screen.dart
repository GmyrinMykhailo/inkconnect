import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../mock/guest_search_mock_data.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/authenticated_site_header.dart';
import '../widgets/master_search_card.dart';
import 'guest_dashboard_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    super.key,
    required this.user,
    required this.userName,
    required this.api,
    required this.sessionToken,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenMessages,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenRecommendations,
    required this.onOpenProfile,
    required this.onOpenMasterProfile,
  });

  final AuthUser? user;
  final String userName;
  final InkConnectApiClient api;
  final String? sessionToken;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenMessages;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenRecommendations;
  final VoidCallback onOpenProfile;
  final ValueChanged<String> onOpenMasterProfile;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<MasterProfile> _masters = const <MasterProfile>[];
  final Set<String> _removingIds = <String>{};
  bool _loading = true;
  String? _error;

  static const _images = [
    GuestDashboardAssets.maria,
    GuestDashboardAssets.anna,
    GuestDashboardAssets.dmitry,
    GuestDashboardAssets.alexander,
  ];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void didUpdateWidget(covariant FavoritesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.api != widget.api) {
      _loadFavorites();
    }
  }

  Future<void> _loadFavorites() async {
    final token = widget.sessionToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _masters = const <MasterProfile>[];
        _loading = false;
        _error = 'Избранное доступно после входа.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await widget.api.getFavoriteMasters(sessionToken: token);
      if (!mounted) {
        return;
      }
      setState(() {
        _masters = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _masters = const <MasterProfile>[];
        _loading = false;
        _error = 'Не удалось загрузить избранное';
      });
    }
  }

  Future<void> _removeFavorite(MasterProfile master) async {
    final token = widget.sessionToken;
    if (token == null || token.isEmpty || _removingIds.contains(master.id)) {
      return;
    }

    final previous = _masters;
    setState(() {
      _removingIds.add(master.id);
      _masters = _masters.where((item) => item.id != master.id).toList();
    });

    try {
      await widget.api.removeFavoriteMaster(
        sessionToken: token,
        masterId: master.id,
      );
      _showSnackBar('Удалено из избранного');
    } catch (_) {
      if (mounted) {
        setState(() => _masters = previous);
        _showSnackBar('Не удалось удалить из избранного');
      }
    } finally {
      if (mounted) {
        setState(() => _removingIds.remove(master.id));
      } else {
        _removingIds.remove(master.id);
      }
    }
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedPageShell(
      user: widget.user,
      userName: widget.userName,
      activeSidebarItem: AuthenticatedSidebarItem.favorites,
      activeMobileNavItem: AuthenticatedMobileNavItem.none,
      headerSection: AuthenticatedHeaderSection.home,
      onOpenHome: widget.onOpenHome,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: widget.onOpenAppointments,
      onOpenMasterAppointments: widget.onOpenMasterAppointments,
      onOpenMessages: () => widget.onOpenMessages('messages'),
      onOpenCareJournal: () => widget.onOpenCareJournal('journal'),
      onOpenClientJournals: widget.onOpenClientJournals,
      onOpenServicesPrices: widget.onOpenServicesPrices,
      onOpenRecommendations: widget.onOpenRecommendations,
      onOpenProfile: widget.onOpenProfile,
      onOpenFavorites: () {},
      onMockAction: _showSnackBar,
      bodyBuilder: (context, isDesktop) => _body(isDesktop),
    );
  }

  Widget _body(bool isDesktop) {
    final horizontalPadding = isDesktop ? 32.0 : 16.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isDesktop ? 32 : 20,
        horizontalPadding,
        isDesktop ? 48 : 96,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Избранные',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: isDesktop ? 36 : 28,
                  fontWeight: FontWeight.w800,
                  color: AuthenticatedDashboardTheme.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Здесь будут мастера, которых вы добавили в избранное.',
                style: TextStyle(
                  color: AuthenticatedDashboardTheme.muted,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              if (_loading)
                const _FavoritesLoadingState()
              else if (_error != null)
                _FavoritesErrorState(message: _error!, onRetry: _loadFavorites)
              else if (_masters.isEmpty)
                _FavoritesEmptyState(onOpenSearch: widget.onOpenSearch)
              else
                _FavoritesList(
                  masters: _masters,
                  isDesktop: isDesktop,
                  removingIds: _removingIds,
                  toSearchItem: _toSearchItem,
                  onOpenProfile: widget.onOpenMasterProfile,
                  onRemove: _removeFavorite,
                ),
            ],
          ),
        ),
      ),
    );
  }

  GuestMasterSearchItem _toSearchItem(MasterProfile master, int index) {
    final displayName = master.displayName.trim();
    final category = master.category.trim();
    final styles = master.styles
        .where((style) => style.trim().isNotEmpty)
        .take(3)
        .toList(growable: false);
    final tags = <String>[
      if (category.isNotEmpty) category,
      ...styles,
    ].take(4).toList(growable: false);
    final description = master.bio.trim().isNotEmpty
        ? master.bio.trim()
        : master.studioName.trim().isNotEmpty
        ? 'Мастер из студии ${master.studioName.trim()}.'
        : 'Мастер InkConnect.';

    return GuestMasterSearchItem(
      id: master.id,
      username: _handle(master.username),
      name: displayName,
      city: master.city.trim().isNotEmpty
          ? master.city.trim()
          : 'Город не указан',
      rating: master.rating,
      reviewCount: master.reviewCount,
      priceLabel: master.minSessionPrice > 0
          ? 'от ${_formatRubles(master.minSessionPrice)} ₽'
          : 'Цена уточняется у мастера',
      priceValue: master.minSessionPrice,
      tags: tags,
      description: description,
      assetPath: _images[index % _images.length],
      avatarUrl: master.avatarUrl,
      showFullName: displayName.isNotEmpty,
      studioName: master.studioName,
      isFavorite: true,
    );
  }
}

class _FavoritesList extends StatelessWidget {
  const _FavoritesList({
    required this.masters,
    required this.isDesktop,
    required this.removingIds,
    required this.toSearchItem,
    required this.onOpenProfile,
    required this.onRemove,
  });

  final List<MasterProfile> masters;
  final bool isDesktop;
  final Set<String> removingIds;
  final GuestMasterSearchItem Function(MasterProfile master, int index)
  toSearchItem;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<MasterProfile> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < masters.length; index++) ...[
          MasterSearchCard(
            master: toSearchItem(masters[index], index),
            layout: isDesktop
                ? MasterCardLayout.desktop
                : MasterCardLayout.mobile,
            action: MasterCardAction.removeFavorite,
            actionBusy: removingIds.contains(masters[index].id),
            onOpenProfile: onOpenProfile,
            onRemoveFavorite: () => onRemove(masters[index]),
          ),
          if (index != masters.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _FavoritesLoadingState extends StatelessWidget {
  const _FavoritesLoadingState();

  @override
  Widget build(BuildContext context) {
    return const _FavoritesStateCard(
      icon: Icons.bookmark_border_rounded,
      title: 'Загружаем избранных мастеров…',
      description: 'Собираем список мастеров, к которым вы хотели вернуться.',
    );
  }
}

class _FavoritesErrorState extends StatelessWidget {
  const _FavoritesErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _FavoritesStateCard(
      icon: Icons.wifi_off_rounded,
      title: message,
      description: 'Проверьте подключение и попробуйте снова.',
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Повторить'),
      ),
    );
  }
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState({required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return _FavoritesStateCard(
      icon: Icons.bookmark_add_outlined,
      title: 'Пока нет избранных мастеров',
      description:
          'Добавляйте мастеров в избранное из поиска, чтобы быстро возвращаться к ним позже.',
      action: FilledButton(
        onPressed: onOpenSearch,
        style: FilledButton.styleFrom(
          backgroundColor: AuthenticatedDashboardTheme.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text('Перейти к поиску мастеров'),
      ),
    );
  }
}

class _FavoritesStateCard extends StatelessWidget {
  const _FavoritesStateCard({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AuthenticatedDashboardTheme.line),
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AuthenticatedDashboardTheme.soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AuthenticatedDashboardTheme.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AuthenticatedDashboardTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: AuthenticatedDashboardTheme.muted,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 14), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _handle(String username) {
  final value = username.trim();
  if (value.isEmpty) {
    return '@master';
  }
  return value.startsWith('@') ? value : '@$value';
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
