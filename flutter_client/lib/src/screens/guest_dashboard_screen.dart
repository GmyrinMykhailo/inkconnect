import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../widgets/authenticated_site_header.dart';
import '../widgets/popular_masters_list.dart';

class GuestDashboardScreen extends StatefulWidget {
  const GuestDashboardScreen({
    super.key,
    required this.onOpenLogin,
    required this.onOpenRegister,
    required this.onOpenSearch,
    required this.onOpenMasterProfile,
    required this.api,
    this.sessionToken,
  });

  final VoidCallback onOpenLogin;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenSearch;
  final ValueChanged<String> onOpenMasterProfile;
  final InkConnectApiClient api;
  final String? sessionToken;

  @override
  State<GuestDashboardScreen> createState() => _GuestDashboardScreenState();
}

class _GuestDashboardScreenState extends State<GuestDashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _topKey = GlobalKey();
  final GlobalKey _mastersKey = GlobalKey();
  final GlobalKey _howItWorksKey = GlobalKey();
  final GlobalKey _ctaKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1100;
    final isTablet = width >= 760;
    final horizontalPadding = isDesktop
        ? 32.0
        : isTablet
        ? 24.0
        : 16.0;

    return Scaffold(
      backgroundColor: GuestDashboardTheme.background,
      body: Column(
        children: [
          GuestHeader(
            isDesktop: isDesktop,
            horizontalPadding: horizontalPadding,
            onOpenLogin: widget.onOpenLogin,
            onOpenRegister: widget.onOpenRegister,
            onOpenHome: () => _scrollTo(_topKey),
            onOpenMasters: widget.onOpenSearch,
            activeSection: GuestHeaderSection.home,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(key: _topKey),
                  _HeroSection(
                    isDesktop: isDesktop,
                    isTablet: isTablet,
                    horizontalPadding: horizontalPadding,
                    onFindMaster: widget.onOpenSearch,
                  ),
                  _RecommendationsSection(
                    key: _mastersKey,
                    isDesktop: isDesktop,
                    isTablet: isTablet,
                    horizontalPadding: horizontalPadding,
                    onShowAll: widget.onOpenSearch,
                    onProfilePressed: widget.onOpenMasterProfile,
                    api: widget.api,
                    sessionToken: widget.sessionToken,
                  ),
                  _HowItWorksSection(
                    key: _howItWorksKey,
                    isDesktop: isDesktop,
                    isTablet: isTablet,
                    horizontalPadding: horizontalPadding,
                  ),
                  _GuestCtaSection(
                    key: _ctaKey,
                    isDesktop: isDesktop,
                    horizontalPadding: horizontalPadding,
                    onOpenRegister: widget.onOpenRegister,
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum GuestHeaderSection { home, search }

class GuestHeader extends StatelessWidget {
  const GuestHeader({
    super.key,
    required this.isDesktop,
    required this.horizontalPadding,
    required this.onOpenLogin,
    required this.onOpenRegister,
    required this.onOpenHome,
    required this.onOpenMasters,
    this.activeSection = GuestHeaderSection.home,
    this.isAuthenticated = false,
    this.userName = 'Артём',
    this.onOpenRecommendations,
    this.onOpenFavorites,
    this.onOpenProfile,
  });

  final bool isDesktop;
  final double horizontalPadding;
  final VoidCallback onOpenLogin;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenMasters;
  final GuestHeaderSection activeSection;
  final bool isAuthenticated;
  final String userName;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    if (isAuthenticated) {
      return AuthenticatedSiteHeader(
        isDesktop: isDesktop,
        userName: userName,
        activeSection: activeSection == GuestHeaderSection.search
            ? AuthenticatedHeaderSection.search
            : AuthenticatedHeaderSection.home,
        onOpenHome: onOpenHome,
        onOpenSearch: onOpenMasters,
        onOpenRecommendations: onOpenRecommendations ?? onOpenMasters,
        onOpenFavorites: onOpenFavorites,
        onOpenProfile: onOpenProfile,
        horizontalPadding: horizontalPadding,
      );
    }

    return Container(
      height: isDesktop ? 90 : 76,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          Text(
            'InkConnect',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: GuestDashboardTheme.accent,
              fontWeight: FontWeight.w600,
              fontSize: isDesktop ? 26 : 20,
            ),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 64),
            _HeaderLink(
              label: 'Главная',
              selected: activeSection == GuestHeaderSection.home,
              onTap: onOpenHome,
            ),
            const SizedBox(width: 42),
            _HeaderLink(
              label: 'Поиск мастеров',
              selected: activeSection == GuestHeaderSection.search,
              onTap: onOpenMasters,
            ),
            const Spacer(),
            _HeaderPillButton(
              label: 'Войти',
              filled: true,
              onPressed: onOpenLogin,
            ),
          ] else ...[
            const Spacer(),
            OutlinedButton(
              onPressed: onOpenLogin,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(88, 38),
                side: const BorderSide(color: GuestDashboardTheme.accent),
                foregroundColor: GuestDashboardTheme.accent,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Войти'),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: onOpenRegister,
              icon: const Icon(Icons.menu_rounded),
              color: const Color(0xFF364153),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.isDesktop,
    required this.isTablet,
    required this.horizontalPadding,
    required this.onFindMaster,
  });

  final bool isDesktop;
  final bool isTablet;
  final double horizontalPadding;
  final VoidCallback onFindMaster;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
      fontSize: isDesktop
          ? 62
          : isTablet
          ? 46
          : 34,
      height: isDesktop ? 1.04 : 1.08,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF101828),
    );
    final descriptionStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: isDesktop
          ? 23.45
          : isTablet
          ? 20
          : 17,
      height: 1.55,
      color: const Color(0xFF4A5565),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        84,
        horizontalPadding,
        84,
      ),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 40),
                    child: _HeroCopy(
                      titleStyle: titleStyle,
                      descriptionStyle: descriptionStyle,
                      onFindMaster: onFindMaster,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20.845),
                    child: const AspectRatio(
                      aspectRatio: 705.6 / 529.2,
                      child: Image(
                        image: AssetImage(GuestDashboardAssets.hero),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroCopy(
                  titleStyle: titleStyle,
                  descriptionStyle: descriptionStyle,
                  onFindMaster: onFindMaster,
                ),
                const SizedBox(height: 28),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20.845),
                  child: const AspectRatio(
                    aspectRatio: 705.6 / 529.2,
                    child: Image(
                      image: AssetImage(GuestDashboardAssets.hero),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.titleStyle,
    required this.descriptionStyle,
    required this.onFindMaster,
  });

  final TextStyle? titleStyle;
  final TextStyle? descriptionStyle;
  final VoidCallback onFindMaster;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 706),
          child: Text(
            'Платформа для сопровождения услуг бодимодификаций',
            style: titleStyle,
          ),
        ),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 706),
          child: Text(
            'Находите мастеров, записывайтесь на процедуру и получайте персональные рекомендации с ведением защищённого журнала ухода',
            style: descriptionStyle,
          ),
        ),
        const SizedBox(height: 26),
        _HeaderPillButton(
          label: 'Найти мастера',
          filled: true,
          onPressed: onFindMaster,
          expandedPadding: true,
        ),
      ],
    );
  }
}

class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({
    super.key,
    required this.isDesktop,
    required this.isTablet,
    required this.horizontalPadding,
    required this.onShowAll,
    required this.onProfilePressed,
    required this.api,
    this.sessionToken,
  });

  final bool isDesktop;
  final bool isTablet;
  final double horizontalPadding;
  final VoidCallback onShowAll;
  final ValueChanged<String> onProfilePressed;
  final InkConnectApiClient api;
  final String? sessionToken;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        62.5,
        horizontalPadding,
        62.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Популярные мастера',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: isDesktop ? 31.267 : 26,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF101828),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onShowAll,
                style: TextButton.styleFrom(
                  foregroundColor: GuestDashboardTheme.accent,
                  textStyle: TextStyle(
                    fontSize: isDesktop ? 20.845 : 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                label: const Text('Смотреть всех'),
              ),
            ],
          ),
          const SizedBox(height: 42),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 1280 : double.infinity,
            ),
            child: PopularMastersList(
              api: api,
              sessionToken: sessionToken,
              isDesktop: isDesktop,
              onOpenMasterProfile: onProfilePressed,
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection({
    super.key,
    required this.isDesktop,
    required this.isTablet,
    required this.horizontalPadding,
  });

  final bool isDesktop;
  final bool isTablet;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GuestDashboardTheme.background,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        83.379,
        horizontalPadding,
        83.379,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Как это работает',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: isDesktop ? 39.084 : 30,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 62.534),
          isDesktop
              ? Row(
                  children: [
                    for (var i = 0; i < howItWorksSteps.length; i++) ...[
                      Expanded(
                        child: _HowItWorksCard(step: howItWorksSteps[i]),
                      ),
                      if (i != howItWorksSteps.length - 1)
                        const SizedBox(width: 31.267),
                    ],
                  ],
                )
              : Column(
                  children: [
                    for (var i = 0; i < howItWorksSteps.length; i++) ...[
                      _HowItWorksCard(step: howItWorksSteps[i]),
                      if (i != howItWorksSteps.length - 1)
                        SizedBox(height: isTablet ? 20 : 16),
                    ],
                  ],
                ),
        ],
      ),
    );
  }
}

class _GuestCtaSection extends StatelessWidget {
  const _GuestCtaSection({
    super.key,
    required this.isDesktop,
    required this.horizontalPadding,
    required this.onOpenRegister,
  });

  final bool isDesktop;
  final double horizontalPadding;
  final VoidCallback onOpenRegister;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        83.379,
        horizontalPadding,
        83.379,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: GuestDashboardTheme.accent,
          borderRadius: BorderRadius.circular(31.267),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2F5D50), Color(0xFF1F4D40)],
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 84 : 24,
          vertical: isDesktop ? 84 : 36,
        ),
        child: Column(
          children: [
            Text(
              'Готовы найти своего мастера?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: isDesktop ? 46.901 : 32,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 875),
              child: Text(
                'Присоединяйтесь к InkConnect и получите доступ к лучшим мастерам в вашем городе',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: isDesktop ? 23.45 : 18,
                  height: 1.55,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: onOpenRegister,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: GuestDashboardTheme.accent,
                minimumSize: const Size(271.064, 62.534),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 18,
                ),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 20.845,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: const Text('Создать аккаунт →'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MasterRecommendationCard extends StatelessWidget {
  const _MasterRecommendationCard({
    required this.master,
    required this.width,
    required this.onPressed,
  });

  final GuestDashboardMaster master;
  final double width;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.845),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3.908,
            offset: Offset(0, 1.303),
          ),
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 2.606,
            offset: Offset(0, 1.303),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.845),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Image.asset(master.assetPath, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(26.056),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    master.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 23.45,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 5.211),
                  Text(
                    master.specialty,
                    style: const TextStyle(
                      fontSize: 18.239,
                      height: 1.43,
                      color: Color(0xFF4A5565),
                    ),
                  ),
                  const SizedBox(height: 15.634),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF4B844),
                        size: 20.845,
                      ),
                      const SizedBox(width: 5.211),
                      Text(
                        master.rating,
                        style: const TextStyle(
                          fontSize: 18.239,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0A0A0A),
                        ),
                      ),
                      const SizedBox(width: 5.211),
                      Text(
                        master.reviewCount,
                        style: const TextStyle(
                          fontSize: 18.239,
                          color: Color(0xFF6A7282),
                        ),
                      ),
                      const SizedBox(width: 20.845),
                      const Icon(
                        Icons.location_on_outlined,
                        color: Color(0xFF4A5565),
                        size: 20.845,
                      ),
                      const SizedBox(width: 5.211),
                      Expanded(
                        child: Text(
                          master.city,
                          style: const TextStyle(
                            fontSize: 18.239,
                            color: Color(0xFF4A5565),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15.634),
                  Row(
                    children: [
                      RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            const TextSpan(
                              text: 'от ',
                              style: TextStyle(
                                fontSize: 18.239,
                                color: Color(0xFF4A5565),
                              ),
                            ),
                            TextSpan(
                              text: master.price,
                              style: const TextStyle(
                                fontSize: 20.845,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF101828),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 46.901,
                        child: FilledButton(
                          onPressed: onPressed,
                          style: FilledButton.styleFrom(
                            backgroundColor: GuestDashboardTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.845,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 18.239,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const Text('Профиль'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.step});

  final GuestHowItWorksStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 453.374),
      padding: const EdgeInsets.all(41.69),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(31.267),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3.908,
            offset: Offset(0, 1.303),
          ),
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 2.606,
            offset: Offset(0, 1.303),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 72.957,
                height: 72.957,
                decoration: const BoxDecoration(
                  color: GuestDashboardTheme.accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(step.icon, color: Colors.white, size: 36.478),
              ),
              const SizedBox(width: 20.845),
              Text(
                step.number,
                style: const TextStyle(
                  fontSize: 78.168,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE5E7EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36.478),
          Text(
            step.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 26.056,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            step.description,
            style: const TextStyle(
              fontSize: 20.845,
              height: 1.6,
              color: Color(0xFF4A5565),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderLink extends StatelessWidget {
  const _HeaderLink({
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
      child: Text(
        label,
        style: TextStyle(
          fontSize: 18.239,
          color: selected
              ? GuestDashboardTheme.accent
              : const Color(0xFF364153),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _HeaderPillButton extends StatelessWidget {
  const _HeaderPillButton({
    required this.label,
    required this.filled,
    required this.onPressed,
    this.expandedPadding = false,
  });

  final String label;
  final bool filled;
  final VoidCallback onPressed;
  final bool expandedPadding;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: filled ? GuestDashboardTheme.accent : Colors.white,
        foregroundColor: filled ? Colors.white : GuestDashboardTheme.accent,
        minimumSize: Size(expandedPadding ? 207.471 : 103.833, 46.901),
        padding: EdgeInsets.symmetric(
          horizontal: expandedPadding ? 26.056 : 20,
          vertical: 10.16,
        ),
        shape: const StadiumBorder(),
        textStyle: TextStyle(
          fontSize: expandedPadding ? 20.845 : 18.239,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

class GuestDashboardTheme {
  static const Color background = Colors.white;
  static const Color accent = Color(0xFF2F5D50);
}

class GuestDashboardAssets {
  static const String hero = 'assets/guest_dashboard/hero.png';
  static const String anna = 'assets/guest_dashboard/master_anna.png';
  static const String dmitry = 'assets/guest_dashboard/master_dmitry.png';
  static const String maria = 'assets/guest_dashboard/master_maria.png';
  static const String alexander = 'assets/guest_dashboard/master_alexander.png';
}

class GuestDashboardMaster {
  const GuestDashboardMaster({
    required this.name,
    required this.specialty,
    required this.rating,
    required this.reviewCount,
    required this.city,
    required this.price,
    required this.assetPath,
  });

  final String name;
  final String specialty;
  final String rating;
  final String reviewCount;
  final String city;
  final String price;
  final String assetPath;
}

class GuestHowItWorksStep {
  const GuestHowItWorksStep({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;
}

const List<GuestDashboardMaster> guestDashboardMasters = [
  GuestDashboardMaster(
    name: 'Анна Петрова',
    specialty: 'Реализм, портреты',
    rating: '4.9',
    reviewCount: '(127)',
    city: 'Москва',
    price: '8 000 ₽',
    assetPath: GuestDashboardAssets.anna,
  ),
  GuestDashboardMaster(
    name: 'Дмитрий Козлов',
    specialty: 'Дотворк, геометрия',
    rating: '4.8',
    reviewCount: '(95)',
    city: 'Санкт-Петербург',
    price: '6 000 ₽',
    assetPath: GuestDashboardAssets.dmitry,
  ),
  GuestDashboardMaster(
    name: 'Мария Соколова',
    specialty: 'Акварель, флористика',
    rating: '5',
    reviewCount: '(203)',
    city: 'Москва',
    price: '10 000 ₽',
    assetPath: GuestDashboardAssets.maria,
  ),
  GuestDashboardMaster(
    name: 'Александр Волков',
    specialty: 'Олдскул, традишнл',
    rating: '4.7',
    reviewCount: '(84)',
    city: 'Казань',
    price: '7 000 ₽',
    assetPath: GuestDashboardAssets.alexander,
  ),
];

const List<GuestHowItWorksStep> howItWorksSteps = [
  GuestHowItWorksStep(
    number: '1',
    title: 'Выбор мастера',
    description:
        'Изучите портфолио, прочитайте отзывы и выберите специалиста по вашим предпочтениям',
    icon: Icons.search_rounded,
  ),
  GuestHowItWorksStep(
    number: '2',
    title: 'Запись на сеанс',
    description:
        'Забронируйте удобное время онлайн и получите подтверждение от мастера',
    icon: Icons.calendar_today_outlined,
  ),
  GuestHowItWorksStep(
    number: '3',
    title: 'Получение рекомендаций',
    description:
        'После процедуры получайте персональные советы по уходу за татуировкой',
    icon: Icons.check_circle_outline_rounded,
  ),
  GuestHowItWorksStep(
    number: '4',
    title: 'Фиксируйте выполнение рекомендаций',
    description:
        'Ведите защищенный журнал ухода и отслеживайте прогресс заживления',
    icon: Icons.menu_book_outlined,
  ),
];
