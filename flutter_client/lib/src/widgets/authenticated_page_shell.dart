import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import 'authenticated_mobile_navigation.dart';
import 'authenticated_sidebar.dart';
import 'authenticated_site_header.dart';

typedef AuthenticatedBodyBuilder = Widget Function(
  BuildContext context,
  bool isDesktop,
);

class AuthenticatedPageShell extends StatelessWidget {
  const AuthenticatedPageShell({
    super.key,
    required this.user,
    required this.userName,
    required this.activeSidebarItem,
    required this.activeMobileNavItem,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenMessages,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenRecommendations,
    required this.onMockAction,
    required this.bodyBuilder,
    this.sidebarFooter,
    this.headerSection = AuthenticatedHeaderSection.home,
    this.desktopBreakpoint = 980,
    this.onOpenProfile,
    this.onOpenFavorites,
  });

  final AuthUser? user;
  final String userName;
  final AuthenticatedSidebarItem? activeSidebarItem;
  final AuthenticatedMobileNavItem activeMobileNavItem;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenRecommendations;
  final ValueChanged<String> onMockAction;
  final AuthenticatedBodyBuilder bodyBuilder;
  final Widget? sidebarFooter;
  final AuthenticatedHeaderSection headerSection;
  final double desktopBreakpoint;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenFavorites;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= desktopBreakpoint;
        final horizontalPadding = isDesktop ? 32.0 : 16.0;

        return Scaffold(
          backgroundColor: AuthenticatedDashboardTheme.background,
          bottomNavigationBar: isDesktop
              ? null
              : AuthenticatedMobileNavigation(
                  activeItem: activeMobileNavItem,
                  onOpenHome: onOpenHome,
                  onOpenSearch: onOpenSearch,
                  onOpenMessages: onOpenMessages,
                  onOpenRecommendations: onOpenRecommendations,
                  onOpenCareJournal: onOpenCareJournal,
                ),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                AuthenticatedSiteHeader(
                  isDesktop: isDesktop,
                  userName: userName,
                  activeSection: headerSection,
                  horizontalPadding: horizontalPadding,
                  onOpenHome: onOpenHome,
                  onOpenSearch: onOpenSearch,
                  onOpenRecommendations: onOpenRecommendations,
                  onOpenFavorites:
                      onOpenFavorites ?? () => onMockAction('Избранное'),
                  onOpenProfile: onOpenProfile,
                ),
                Expanded(
                  child: isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AuthenticatedSidebar(
                              activeItem: activeSidebarItem,
                              isMaster: user?.role == 'master',
                              onOpenHome: onOpenHome,
                              onOpenAppointments: onOpenAppointments,
                              onOpenMasterAppointments:
                                  onOpenMasterAppointments,
                              onOpenMessages: onOpenMessages,
                              onOpenCareJournal: onOpenCareJournal,
                              onOpenClientJournals: onOpenClientJournals,
                              onOpenServicesPrices: onOpenServicesPrices,
                              onMockAction: onMockAction,
                              footer: sidebarFooter,
                            ),
                            Expanded(child: bodyBuilder(context, true)),
                          ],
                        )
                      : bodyBuilder(context, false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
