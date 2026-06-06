import 'package:flutter/material.dart';

import '../mock/guest_search_mock_data.dart';
import '../screens/guest_dashboard_screen.dart';
import 'remote_or_asset_image.dart';

enum MasterCardLayout { desktop, mobile }

enum MasterCardAction { favorite, removeFavorite, none }

class MasterSearchCard extends StatefulWidget {
  const MasterSearchCard({
    super.key,
    required this.master,
    required this.layout,
    required this.onOpenProfile,
    this.isOwnMaster = false,
    this.onOpenMyProfile,
    this.onOpenBooking,
    this.action = MasterCardAction.favorite,
    this.onToggleFavorite,
    this.onRemoveFavorite,
    this.actionBusy = false,
  });

  final GuestMasterSearchItem master;
  final MasterCardLayout layout;
  final bool isOwnMaster;
  final VoidCallback? onOpenMyProfile;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<String>? onOpenBooking;
  final MasterCardAction action;
  final ValueChanged<GuestMasterSearchItem>? onToggleFavorite;
  final VoidCallback? onRemoveFavorite;
  final bool actionBusy;

  @override
  State<MasterSearchCard> createState() => _MasterSearchCardState();
}

class _MasterSearchCardState extends State<MasterSearchCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.layout == MasterCardLayout.mobile) {
      return _mobileCard(context);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _desktopCard(context),
    );
  }

  Widget _desktopCard(BuildContext context) {
    final master = widget.master;

    return Material(
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
                child: RemoteOrAssetImage(
                  assetPath: master.assetPath,
                  imageUrl: master.avatarUrl,
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
                        Expanded(child: _MasterTitleBlock(master: master)),
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
                    _Tags(tags: master.tags),
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
                      child: _actions(compact: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileCard(BuildContext context) {
    final master = widget.master;

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
                    child: RemoteOrAssetImage(
                      assetPath: master.assetPath,
                      imageUrl: master.avatarUrl,
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
                        _MasterTitleBlock(master: master, compact: true),
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
              _Tags(tags: master.tags),
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
              _actions(compact: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions({required bool compact}) {
    final children = <Widget>[];

    if (widget.isOwnMaster) {
      final badge = _OwnMasterBadge(height: compact ? 46 : 48);
      children.add(
        compact ? Expanded(child: badge) : SizedBox(width: 178, child: badge),
      );
    } else if (widget.onOpenBooking != null) {
      final button = FilledButton(
        onPressed: () => widget.onOpenBooking!(widget.master.username),
        style: FilledButton.styleFrom(
          minimumSize: compact
              ? const Size.fromHeight(46)
              : const Size(178, 48),
          backgroundColor: GuestDashboardTheme.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Записаться',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      children.add(
        compact ? Expanded(child: button) : SizedBox(width: 178, child: button),
      );
    } else if (compact) {
      children.add(const Spacer());
    }

    final action = _actionButton(compact: compact);
    if (action != null) {
      if (children.isNotEmpty) {
        children.add(SizedBox(width: compact ? 12 : 16));
      }
      children.add(action);
    }

    return Row(
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
      children: children,
    );
  }

  Widget? _actionButton({required bool compact}) {
    switch (widget.action) {
      case MasterCardAction.favorite:
        final onToggle = widget.onToggleFavorite;
        if (widget.isOwnMaster || onToggle == null) {
          return null;
        }
        return _BookmarkButton(
          compact: compact,
          selected: widget.master.isFavorite,
          onPressed: widget.actionBusy ? null : () => onToggle(widget.master),
        );
      case MasterCardAction.removeFavorite:
        final onRemove = widget.onRemoveFavorite;
        if (onRemove == null) {
          return null;
        }
        return _RemoveFavoriteButton(
          compact: compact,
          onPressed: widget.actionBusy ? null : onRemove,
        );
      case MasterCardAction.none:
        return null;
    }
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

class _MasterTitleBlock extends StatelessWidget {
  const _MasterTitleBlock({required this.master, this.compact = false});

  final GuestMasterSearchItem master;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          master.handle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0B2A5B),
          ),
        ),
        if (master.showFullName) ...[
          SizedBox(height: compact ? 3 : 4),
          Text(
            master.name,
            style: TextStyle(
              fontSize: compact ? 15 : 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF355072),
            ),
          ),
        ],
        SizedBox(height: compact ? 4 : 6),
        Row(
          children: [
            const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFC107)),
            const SizedBox(width: 4),
            Text(
              master.ratingLabel,
              style: TextStyle(
                fontSize: compact ? 16 : 18,
                color: const Color(0xFF355072),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 10),
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: Color(0xFF355072),
              ),
              const SizedBox(width: 4),
              Text(
                master.city,
                style: const TextStyle(fontSize: 18, color: Color(0xFF355072)),
              ),
            ],
          ],
        ),
        if (compact) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 15,
                color: Color(0xFF355072),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  master.city,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF355072),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OwnMasterBadge extends StatelessWidget {
  const _OwnMasterBadge({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
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

class _Tags extends StatelessWidget {
  const _Tags({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.map((tag) => _TagPill(label: tag)).toList(growable: false),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, color: Color(0xFF0B2A5B)),
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

  final VoidCallback? onPressed;
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

class _RemoveFavoriteButton extends StatelessWidget {
  const _RemoveFavoriteButton({required this.onPressed, this.compact = false});

  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 40.0;

    return Tooltip(
      message: 'Удалить из избранного',
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.delete_outline_rounded,
              size: compact ? 20 : 22,
              color: const Color(0xFF355072),
            ),
          ),
        ),
      ),
    );
  }
}
