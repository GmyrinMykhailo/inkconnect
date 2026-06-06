import 'package:flutter/material.dart';

import '../theme/authenticated_dashboard_theme.dart';
import 'authenticated_badge_counts_scope.dart';

enum AuthenticatedSidebarItem {
  home,
  appointments,
  masterAppointments,
  messages,
  favorites,
  careJournal,
  clientJournals,
  settings,
}

class AuthenticatedSidebar extends StatelessWidget {
  const AuthenticatedSidebar({
    super.key,
    required this.activeItem,
    required this.isMaster,
    required this.onOpenHome,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenMessages,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onMockAction,
    this.footer,
    this.width = 292,
  });

  final AuthenticatedSidebarItem? activeItem;
  final bool isMaster;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final ValueChanged<String> onMockAction;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    final counts = AuthenticatedBadgeCountsScope.maybeOf(context);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AuthenticatedDashboardTheme.line)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarItem(
            icon: Icons.home_outlined,
            label: 'Главная',
            active: activeItem == AuthenticatedSidebarItem.home,
            onTap: onOpenHome,
          ),
          _SidebarItem(
            icon: Icons.calendar_today_outlined,
            label: 'Мои записи',
            badge: _badgeText(counts?.clientAppointmentsBadge, '2'),
            active: activeItem == AuthenticatedSidebarItem.appointments,
            onTap: onOpenAppointments,
          ),
          if (isMaster)
            _SidebarItem(
              icon: Icons.assignment_turned_in_outlined,
              label: 'Управление записями',
              badge: _badgeText(counts?.masterAppointmentsBadge, '3'),
              active: activeItem == AuthenticatedSidebarItem.masterAppointments,
              onTap: onOpenMasterAppointments,
            ),
          _SidebarItem(
            icon: Icons.chat_bubble_outline,
            label: 'Сообщения',
            badge: counts == null
                ? (isMaster ? '5' : '2')
                : _optionalBadgeText(counts.messagesBadge),
            active: activeItem == AuthenticatedSidebarItem.messages,
            onTap: onOpenMessages,
          ),
          _SidebarItem(
            icon: Icons.menu_book_outlined,
            label: 'Журнал ухода',
            active: activeItem == AuthenticatedSidebarItem.careJournal,
            onTap: onOpenCareJournal,
          ),
          if (isMaster)
            _SidebarItem(
              icon: Icons.fact_check_outlined,
              label: 'Журналы клиентов',
              active: activeItem == AuthenticatedSidebarItem.clientJournals,
              onTap: onOpenClientJournals,
            ),
          if (footer != null) ...[
            const Spacer(),
            footer!,
          ],
        ],
      ),
    );
  }

  String _badgeText(int? value, String fallback) {
    return value == null ? fallback : value.toString();
  }

  String? _optionalBadgeText(int? value) {
    return value == null ? null : value.toString();
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : AuthenticatedDashboardTheme.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? AuthenticatedDashboardTheme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.22)
                          : AuthenticatedDashboardTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
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
