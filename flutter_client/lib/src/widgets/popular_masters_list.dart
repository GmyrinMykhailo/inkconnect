import 'dart:math';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import 'remote_or_asset_image.dart';

class PopularMastersList extends StatefulWidget {
  const PopularMastersList({
    super.key,
    required this.api,
    required this.sessionToken,
    required this.isDesktop,
    required this.onOpenMasterProfile,
    this.showProfileButton = true,
    this.desktopCount = 4,
    this.mobileCount = 3,
  });

  final InkConnectApiClient api;
  final String? sessionToken;
  final bool isDesktop;
  final ValueChanged<String> onOpenMasterProfile;
  final bool showProfileButton;
  final int desktopCount;
  final int mobileCount;

  @override
  State<PopularMastersList> createState() => _PopularMastersListState();
}

class _PopularMastersListState extends State<PopularMastersList> {
  List<MasterProfile> _masters = const <MasterProfile>[];
  Set<String> _favoriteIds = const <String>{};
  final Map<String, bool> _favoriteOverrides = <String, bool>{};
  final Set<String> _favoriteBusyIds = <String>{};
  bool _loading = true;
  bool _hasError = false;

  static const _fallbackImages = [
    'assets/guest_dashboard/master_maria.png',
    'assets/guest_dashboard/master_anna.png',
    'assets/guest_dashboard/master_dmitry.png',
    'assets/guest_dashboard/master_alexander.png',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PopularMastersList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.sessionToken != widget.sessionToken) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
      _favoriteOverrides.clear();
      _favoriteBusyIds.clear();
    });

    try {
      final response = await widget.api.searchMasters(
        query: '',
        sessionToken: widget.sessionToken,
      );
      final favorites = await _loadFavoriteIds();
      if (!mounted) {
        return;
      }
      setState(() {
        _masters = _pickRandom(response.items);
        _favoriteIds = favorites;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _masters = const <MasterProfile>[];
        _favoriteIds = const <String>{};
        _loading = false;
        _hasError = true;
      });
    }
  }

  Future<Set<String>> _loadFavoriteIds() async {
    final token = widget.sessionToken;
    if (token == null || token.isEmpty) {
      return const <String>{};
    }

    try {
      final favorites = await widget.api.getFavoriteMasters(
        sessionToken: token,
      );
      return favorites
          .map((master) => master.id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  List<MasterProfile> _pickRandom(List<MasterProfile> source) {
    final clean = source
        .where((master) => master.id.trim().isNotEmpty)
        .toList(growable: false);
    final shuffled = [...clean]..shuffle(Random());

    // TODO: when reviews and real ranking are ready, replace this random
    // selection with sorting by rating, review count, and booking activity.
    final limit = widget.isDesktop ? widget.desktopCount : widget.mobileCount;
    return shuffled.take(limit).toList(growable: false);
  }

  bool _isFavorite(MasterProfile master) {
    final id = master.id.trim();
    if (id.isEmpty) {
      return false;
    }
    return _favoriteOverrides[id] ??
        (master.isFavorite || _favoriteIds.contains(id));
  }

  Future<void> _toggleFavorite(MasterProfile master) async {
    final token = widget.sessionToken;
    final id = master.id.trim();
    if (token == null || token.isEmpty) {
      _showSnackBar('Войдите, чтобы добавлять мастеров в избранное');
      return;
    }
    if (id.isEmpty || _favoriteBusyIds.contains(id)) {
      return;
    }

    final nextValue = !_isFavorite(master);
    setState(() {
      _favoriteOverrides[id] = nextValue;
      _favoriteBusyIds.add(id);
    });

    try {
      if (nextValue) {
        await widget.api.addFavoriteMaster(sessionToken: token, masterId: id);
        _showSnackBar('Добавлено в избранное');
      } else {
        await widget.api.removeFavoriteMaster(
          sessionToken: token,
          masterId: id,
        );
        _showSnackBar('Удалено из избранного');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _favoriteOverrides[id] = !nextValue;
        });
        _showSnackBar('Не удалось обновить избранное');
      }
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusyIds.remove(id);
        });
      } else {
        _favoriteBusyIds.remove(id);
      }
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _PopularMastersStateCard(
        icon: Icons.hourglass_empty_rounded,
        title: 'Загружаем мастеров...',
      );
    }

    if (_hasError) {
      return _PopularMastersStateCard(
        icon: Icons.wifi_off_rounded,
        title: 'Не удалось загрузить популярных мастеров',
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Повторить'),
        ),
      );
    }

    if (_masters.isEmpty) {
      return const _PopularMastersStateCard(
        icon: Icons.person_search_outlined,
        title: 'Пока нет мастеров для отображения',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobileCarousel = !widget.isDesktop && width < 760;
        if (isMobileCarousel) {
          final cardWidth = width < 340 ? 260.0 : 282.0;
          final cardHeight = cardWidth + 220;

          return SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: _masters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final master = _masters[index];
                return SizedBox(
                  width: cardWidth,
                  child: _PopularMasterCard(
                    master: master,
                    imagePath: _fallbackImages[index % _fallbackImages.length],
                    imageHeight: cardWidth,
                    isFavorite: _isFavorite(master),
                    favoriteBusy: _favoriteBusyIds.contains(master.id.trim()),
                    showProfileButton: widget.showProfileButton,
                    onOpenProfile: () =>
                        widget.onOpenMasterProfile(master.username),
                    onToggleFavorite: () => _toggleFavorite(master),
                  ),
                );
              },
            ),
          );
        }

        final columns = width >= 920 ? 4 : 2;
        const spacing = 24.0;
        final cardWidth = (width - spacing * (columns - 1)) / columns;
        final imageHeight = max(220.0, cardWidth);
        final cardHeight = imageHeight + 220;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _masters.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: cardHeight,
          ),
          itemBuilder: (context, index) {
            final master = _masters[index];
            return _PopularMasterCard(
              master: master,
              imagePath: _fallbackImages[index % _fallbackImages.length],
              imageHeight: imageHeight,
              isFavorite: _isFavorite(master),
              favoriteBusy: _favoriteBusyIds.contains(master.id.trim()),
              showProfileButton: widget.showProfileButton,
              onOpenProfile: () => widget.onOpenMasterProfile(master.username),
              onToggleFavorite: () => _toggleFavorite(master),
            );
          },
        );
      },
    );
  }
}

class _PopularMasterCard extends StatefulWidget {
  const _PopularMasterCard({
    required this.master,
    required this.imagePath,
    required this.imageHeight,
    required this.isFavorite,
    required this.favoriteBusy,
    required this.showProfileButton,
    required this.onOpenProfile,
    required this.onToggleFavorite,
  });

  final MasterProfile master;
  final String imagePath;
  final double imageHeight;
  final bool isFavorite;
  final bool favoriteBusy;
  final bool showProfileButton;
  final VoidCallback onOpenProfile;
  final VoidCallback onToggleFavorite;

  @override
  State<_PopularMasterCard> createState() => _PopularMasterCardState();
}

class _PopularMasterCardState extends State<_PopularMasterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final name = _displayName(widget.master);
    final styles = _stylesLabel(widget.master);
    final city = widget.master.city.trim();
    final price = _priceLabel(widget.master);
    final rating = _ratingLabel(widget.master);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onOpenProfile,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _hovered
                    ? _accent.withValues(alpha: 0.36)
                    : const Color(0xFFE5E7EB),
              ),
              boxShadow: [
                BoxShadow(
                  color: _hovered
                      ? const Color(0x240F172A)
                      : const Color(0x140F172A),
                  blurRadius: _hovered ? 22 : 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: widget.imageHeight,
                      width: double.infinity,
                      child: RemoteOrAssetImage(
                        assetPath: widget.imagePath,
                        imageUrl: widget.master.avatarUrl,
                        fit: BoxFit.cover,
                        placeholder: const _PopularMasterImagePlaceholder(),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _FavoriteButton(
                        selected: widget.isFavorite,
                        busy: widget.favoriteBusy,
                        onPressed: widget.onToggleFavorite,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          styles,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF355072),
                            fontSize: 16,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            if (rating != null) _RatingMeta(label: rating),
                            if (city.isNotEmpty) _CityMeta(city: city),
                          ],
                        ),
                        const Spacer(),
                        _PopularMasterBottomRow(
                          price: price,
                          showProfileButton: widget.showProfileButton,
                          onOpenProfile: widget.onOpenProfile,
                        ),
                      ],
                    ),
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

class _PopularMasterBottomRow extends StatelessWidget {
  const _PopularMasterBottomRow({
    required this.price,
    required this.showProfileButton,
    required this.onOpenProfile,
  });

  final String price;
  final bool showProfileButton;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final priceText = Text(
      price,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _text,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );

    if (!showProfileButton) {
      return SizedBox(width: double.infinity, child: priceText);
    }

    return Row(
      children: [
        Expanded(child: priceText),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: onOpenProfile,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(116, 46),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: const Text('Профиль'),
        ),
      ],
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.selected,
    required this.busy,
    required this.onPressed,
  });

  final bool selected;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: selected ? 'В избранном' : 'В избранное',
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 42,
            height: 42,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    selected
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: _accent,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}

class _RatingMeta extends StatelessWidget {
  const _RatingMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 19, color: Color(0xFFFFB020)),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: _text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CityMeta extends StatelessWidget {
  const _CityMeta({required this.city});

  final String city;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.location_on_outlined,
          size: 18,
          color: Color(0xFF0B2A5B),
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            city,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF355072),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _PopularMasterImagePlaceholder extends StatelessWidget {
  const _PopularMasterImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF0ED),
      alignment: Alignment.center,
      child: const Icon(Icons.person_outline_rounded, color: _accent, size: 42),
    );
  }
}

class _PopularMastersStateCard extends StatelessWidget {
  const _PopularMastersStateCard({
    required this.icon,
    required this.title,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: _accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

String _displayName(MasterProfile master) {
  final displayName = master.displayName.trim();
  if (displayName.isNotEmpty) {
    return displayName;
  }
  return _handle(master.username);
}

String _stylesLabel(MasterProfile master) {
  final styles = master.styles
      .map((style) => style.trim())
      .where((style) => style.isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (styles.isNotEmpty) {
    return styles.join(', ');
  }

  final category = master.category.trim();
  if (category.isNotEmpty) {
    return category;
  }

  final studioName = master.studioName.trim();
  if (studioName.isNotEmpty) {
    return studioName;
  }

  return 'Мастер InkConnect';
}

String? _ratingLabel(MasterProfile master) {
  if (master.rating <= 0) {
    return null;
  }
  final rating = master.rating > 0
      ? master.rating.toStringAsFixed(1).replaceAll('.0', '')
      : '0';
  return '$rating (${master.reviewCount})';
}

String _priceLabel(MasterProfile master) {
  final price = master.minSessionPrice > 0
      ? master.minSessionPrice
      : master.services.isNotEmpty
      ? master.services.first.price
      : 0;
  if (price <= 0) {
    return 'Цена не указана';
  }
  return 'от ${_formatRubles(price)} ₽';
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

const _accent = Color(0xFF2F5D50);
const _text = Color(0xFF0B1228);
