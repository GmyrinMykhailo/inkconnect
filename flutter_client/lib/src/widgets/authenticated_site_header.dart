import 'package:flutter/material.dart';

import '../theme/authenticated_dashboard_theme.dart';
import 'authenticated_profile_avatar_scope.dart';
import 'profile_image.dart';

enum AuthenticatedHeaderSection { home, search, recommendations }

class AuthenticatedSiteHeader extends StatelessWidget {
  const AuthenticatedSiteHeader({
    super.key,
    required this.isDesktop,
    required this.userName,
    required this.activeSection,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenRecommendations,
    this.horizontalPadding = 24,
    this.onOpenFavorites,
    this.onOpenNotifications,
    this.onOpenProfile,
  });

  final bool isDesktop;
  final String userName;
  final AuthenticatedHeaderSection activeSection;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenRecommendations;
  final double horizontalPadding;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenProfile;

  void _openFavorites(BuildContext context) {
    final callback = onOpenFavorites;
    if (callback != null) {
      callback();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Избранное: раздел будет подключен следующим шагом',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = AuthenticatedProfileAvatarScope.avatarUrlOf(context);
    return Container(
      height: isDesktop ? 68 : 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AuthenticatedDashboardTheme.line),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpenHome,
              borderRadius: BorderRadius.circular(10),
              splashColor:
                  AuthenticatedDashboardTheme.accent.withValues(alpha: 0.08),
              highlightColor:
                  AuthenticatedDashboardTheme.accent.withValues(alpha: 0.05),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'InkConnect',
                  style: TextStyle(
                    color: AuthenticatedDashboardTheme.accent,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 48),
            _HeaderNavLink(
              label: 'Главная',
              active: activeSection == AuthenticatedHeaderSection.home,
              onTap: onOpenHome,
            ),
            const SizedBox(width: 32),
            _HeaderNavLink(
              label: 'Поиск мастеров',
              active: activeSection == AuthenticatedHeaderSection.search,
              onTap: onOpenSearch,
            ),
            const SizedBox(width: 32),
            _HeaderNavLink(
              label: 'Лента рекомендаций',
              active:
                  activeSection == AuthenticatedHeaderSection.recommendations,
              onTap: onOpenRecommendations,
            ),
          ],
          const Spacer(),
          if (isDesktop) ...[
            const Icon(
              Icons.location_on_outlined,
              size: 18,
              color: AuthenticatedDashboardTheme.muted,
            ),
            const SizedBox(width: 6),
            const Text(
              'Москва',
              style: TextStyle(
                color: AuthenticatedDashboardTheme.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 22),
          ],
          IconButton(
            onPressed: () => _openFavorites(context),
            tooltip: 'Избранное',
            splashRadius: 22,
            icon: const Icon(Icons.bookmark_border_rounded, size: 22),
            color: AuthenticatedDashboardTheme.accent,
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onOpenNotifications,
            tooltip: 'Уведомления',
            splashRadius: 22,
            icon: const Icon(Icons.notifications_none_rounded, size: 22),
            color: AuthenticatedDashboardTheme.text,
          ),
          const SizedBox(width: 10),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: onOpenProfile,
              borderRadius: BorderRadius.circular(999),
              child: ProfileImage(
                avatarUrl: avatarUrl,
                letterFallback: userName,
                width: 34,
                height: 34,
                circular: true,
                backgroundColor: AuthenticatedDashboardTheme.accent,
                letterStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onOpenProfile,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 6,
                  ),
                  child: Text(
                    userName,
                    style: const TextStyle(
                      color: AuthenticatedDashboardTheme.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderNavLink extends StatelessWidget {
  const _HeaderNavLink({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: AuthenticatedDashboardTheme.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: active
                  ? AuthenticatedDashboardTheme.accent
                  : const Color(0xFF0B2A5B),
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
