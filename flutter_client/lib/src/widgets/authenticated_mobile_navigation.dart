import 'package:flutter/material.dart';

import '../theme/authenticated_dashboard_theme.dart';
import 'authenticated_badge_counts_scope.dart';

enum AuthenticatedMobileNavItem {
  none,
  home,
  search,
  messages,
  recommendations,
  careJournal,
}

class AuthenticatedMobileNavigation extends StatelessWidget {
  const AuthenticatedMobileNavigation({
    super.key,
    required this.activeItem,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenMessages,
    required this.onOpenRecommendations,
    required this.onOpenCareJournal,
  });

  final AuthenticatedMobileNavItem activeItem;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenRecommendations;
  final VoidCallback onOpenCareJournal;

  @override
  Widget build(BuildContext context) {
    final counts = AuthenticatedBadgeCountsScope.maybeOf(context);
    return Container(
      height: 74,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: AuthenticatedDashboardTheme.cardShadow(),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _MobileNavButton(
              icon: Icons.home,
              label: 'Главная',
              active: activeItem == AuthenticatedMobileNavItem.home,
              onTap: onOpenHome,
            ),
            _MobileNavButton(
              icon: Icons.search,
              label: 'Поиск',
              active: activeItem == AuthenticatedMobileNavItem.search,
              onTap: onOpenSearch,
            ),
            _MobileNavButton(
              icon: Icons.chat_bubble_outline,
              label: 'Сообщения',
              badge: counts == null
                  ? '2'
                  : _optionalBadgeText(counts.messagesBadge),
              active: activeItem == AuthenticatedMobileNavItem.messages,
              onTap: onOpenMessages,
            ),
            _MobileNavButton(
              icon: Icons.auto_awesome_outlined,
              label: 'Лента',
              active: activeItem == AuthenticatedMobileNavItem.recommendations,
              onTap: onOpenRecommendations,
            ),
            _MobileNavButton(
              icon: Icons.menu_book_outlined,
              label: 'Журнал\nухода',
              active: activeItem == AuthenticatedMobileNavItem.careJournal,
              onTap: onOpenCareJournal,
            ),
          ],
        ),
      ),
    );
  }

  String? _optionalBadgeText(int? value) {
    return value == null ? null : value.toString();
  }
}

class _MobileNavButton extends StatelessWidget {
  const _MobileNavButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AuthenticatedDashboardTheme.accent
        : AuthenticatedDashboardTheme.text;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: AuthenticatedDashboardTheme.accent.withValues(alpha: 0.08),
        highlightColor:
            AuthenticatedDashboardTheme.accent.withValues(alpha: 0.05),
        child: SizedBox(
          width: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (badge != null)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: _NavBadge(text: badge!),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  height: 1.05,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AuthenticatedDashboardTheme.accent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
