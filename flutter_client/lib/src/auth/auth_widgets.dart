import 'package:flutter/material.dart';

import 'auth_styles.dart';

class AuthPageCard extends StatelessWidget {
  const AuthPageCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: authSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(authCardRadius),
        border: Border.all(color: authOutline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < authCompactBreakpoint;
          return SingleChildScrollView(
            padding: EdgeInsets.all(
              compact ? authPageCompactPadding : authPagePadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: compact ? 0 : authPageDesktopMinHeight,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class AuthFormCard extends StatelessWidget {
  const AuthFormCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? authDefaultFormCardPadding,
      decoration: BoxDecoration(
        color: authSurface,
        borderRadius: BorderRadius.circular(authCardRadius),
        border: Border.all(color: authOutline.withValues(alpha: 0.85)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17000000),
            blurRadius: 42,
            offset: Offset(0, 22),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: authHeaderGap),
        Text(subtitle, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class AuthBrand extends StatelessWidget {
  const AuthBrand({super.key, this.center = false});

  final bool center;

  @override
  Widget build(BuildContext context) {
    final logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: authBrandIconSize,
          height: authBrandIconSize,
          decoration: BoxDecoration(
            color: authSurface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: authOutline.withValues(alpha: 0.85)),
          ),
          child: const Icon(Icons.spa_outlined, size: 16, color: authAccent),
        ),
        const SizedBox(width: authBrandGap),
        const Text(
          'InkConnect',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: authText,
          ),
        ),
      ],
    );

    if (center) {
      return Center(child: logo);
    }
    return logo;
  }
}

class AuthHeroPanel extends StatelessWidget {
  const AuthHeroPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<AuthHeroItemData> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: authSoftPanel,
        borderRadius: BorderRadius.circular(authCardRadius),
        border: Border.all(color: authOutline.withValues(alpha: 0.9)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8F5F0), Color(0xFFF4F0EA)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(authCardRadius),
        child: Stack(
          children: [
            Positioned(
              left: -72,
              bottom: -84,
              child: IgnorePointer(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: authText.withValues(alpha: 0.08),
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: -24,
              bottom: -26,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: -0.55,
                  child: Container(
                    width: 120,
                    height: 190,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(80),
                      border: Border.all(
                        color: authText.withValues(alpha: 0.08),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: authHeroPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AuthBrand(),
                  const SizedBox(height: authHeroBrandGap),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: authHeroTitleWidth),
                    child: Text(title, style: theme.textTheme.headlineLarge),
                  ),
                  const SizedBox(height: authHeroTextGap),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: authHeroSubtitleWidth,
                    ),
                    child: Text(subtitle, style: theme.textTheme.bodyLarge),
                  ),
                  const SizedBox(height: authHeroItemsGap),
                  ...items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: authHeroItemGap),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: authHeroItemIconWrap,
                            height: authHeroItemIconWrap,
                            decoration: BoxDecoration(
                              color: authSoftAccent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Icon(
                              item.icon,
                              color: authAccent,
                              size: authHeroItemIconSize,
                            ),
                          ),
                          const SizedBox(width: authHeroItemRowGap),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: authText,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 12.5,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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

enum AuthStepStatus { pending, active, completed }

class AuthStepItemData {
  const AuthStepItemData({
    required this.label,
    required this.status,
  });

  final String label;
  final AuthStepStatus status;
}

class AuthStepperSidebar extends StatelessWidget {
  const AuthStepperSidebar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<AuthStepItemData> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: authStepperSidebarPadding,
      decoration: BoxDecoration(
        color: authSoftPanel,
        borderRadius: BorderRadius.circular(authCardRadius),
        border: Border.all(color: authOutline),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F6F2), Color(0xFFF2EEE8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthBrand(),
          const SizedBox(height: authStepperHeaderGap),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: authText,
            ),
          ),
          const SizedBox(height: authHeaderGap),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: authStepperItemsGap),
          ...List.generate(
            items.length,
            (index) => AuthStepperRow(
              item: items[index],
              showConnector: index != items.length - 1,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthStepperRow extends StatelessWidget {
  const AuthStepperRow({
    super.key,
    required this.item,
    required this.showConnector,
  });

  final AuthStepItemData item;
  final bool showConnector;

  bool get _highlighted => item.status != AuthStepStatus.pending;

  @override
  Widget build(BuildContext context) {
    final active = item.status == AuthStepStatus.active;
    final completed = item.status == AuthStepStatus.completed;

    return Padding(
      padding: const EdgeInsets.only(bottom: authStepperItemGap),
      child: Container(
        padding: authStepperItemPadding,
        decoration: BoxDecoration(
          color: active
              ? authAccent.withValues(alpha: 0.1)
              : completed
              ? authSoftAccent.withValues(alpha: 0.72)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? authAccent.withValues(alpha: 0.28)
                : completed
                ? authAccent.withValues(alpha: 0.14)
                : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: authStepperIndicatorColumnWidth,
              child: Column(
                children: [
                  _AuthStepBadge(status: item.status),
                  if (showConnector)
                    Container(
                      width: authStepperConnectorWidth,
                      height: authStepperConnectorHeight,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: completed
                          ? authAccent.withValues(alpha: 0.48)
                          : authOutline,
                    ),
                ],
              ),
            ),
            const SizedBox(width: authStepperTextGap),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: authStepperTextTopPadding),
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight:
                        _highlighted ? FontWeight.w700 : FontWeight.w500,
                    color: _highlighted ? authText : authHint,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthStepStrip extends StatelessWidget {
  const AuthStepStrip({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<AuthStepItemData> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: authTabletStepPadding,
      decoration: BoxDecoration(
        color: authSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: authOutline.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: authText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final completed = item.status == AuthStepStatus.completed;
              final active = item.status == AuthStepStatus.active;

              return Expanded(
                child: Row(
                  children: [
                    Container(
                      width: authTabletStepDotSize,
                      height: authTabletStepDotSize,
                      decoration: BoxDecoration(
                        color: completed || active ? authAccent : authSurface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: completed || active ? authAccent : authOutline,
                        ),
                      ),
                      child: Icon(
                        completed
                            ? Icons.check_rounded
                            : active
                            ? Icons.radio_button_checked_rounded
                            : Icons.circle_outlined,
                        size: 13,
                        color: completed || active ? Colors.white : authHint,
                      ),
                    ),
                    if (index != items.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          color: completed
                              ? authAccent.withValues(alpha: 0.38)
                              : authOutline,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              items.length,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == items.length - 1 ? 0 : 8,
                  ),
                  child: Text(
                    items[index].label,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: items[index].status == AuthStepStatus.active
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: items[index].status == AuthStepStatus.pending
                          ? authHint
                          : authText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthMobileProgressCard extends StatelessWidget {
  const AuthMobileProgressCard({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.title,
    required this.progress,
  });

  final int currentStep;
  final int totalSteps;
  final String title;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: authMobileProgressPadding,
      decoration: BoxDecoration(
        color: authSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: authOutline.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Этап $currentStep из $totalSteps',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: authAccent,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: authSoftPanel,
              valueColor: const AlwaysStoppedAnimation<Color>(authAccent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: authText,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthFieldBlock extends StatelessWidget {
  const AuthFieldBlock({
    super.key,
    required this.field,
    this.note,
    this.minNoteHeight = authFieldNoteMinHeight,
  });

  final Widget field;
  final Widget? note;
  final double minNoteHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        const SizedBox(height: authFieldNoteGap),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minNoteHeight),
          child: note ?? const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class AuthHeroItemData {
  const AuthHeroItemData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class AuthFieldHint extends StatelessWidget {
  const AuthFieldHint(this.message, {super.key, this.color = authHint});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(color: color, height: 1.4, fontSize: 12.5),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0C9C9)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: authError, fontSize: 13.5, height: 1.35),
      ),
    );
  }
}

class AuthSuccessBanner extends StatelessWidget {
  const AuthSuccessBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: authSoftAccent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: authAccent.withValues(alpha: 0.24)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: authSuccess,
          fontSize: 13.5,
          height: 1.35,
        ),
      ),
    );
  }
}

class AuthSectionLabel extends StatelessWidget {
  const AuthSectionLabel(this.text, {super.key, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: authText,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class AuthSectionCard extends StatelessWidget {
  const AuthSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: authSectionCardPadding,
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: authOutline.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthSectionLabel(title, subtitle: subtitle),
          const SizedBox(height: authSectionContentGap),
          child,
        ],
      ),
    );
  }
}

class AuthFooterRow extends StatelessWidget {
  const AuthFooterRow({
    super.key,
    required this.prompt,
    required this.actionLabel,
    required this.onPressed,
    this.center = true,
  });

  final String prompt;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 0,
      children: [
        Text(prompt, style: const TextStyle(color: authHint)),
        TextButton(
          onPressed: onPressed,
          child: Text(
            actionLabel,
            style: const TextStyle(
              color: authAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthStepBadge extends StatelessWidget {
  const _AuthStepBadge({required this.status});

  final AuthStepStatus status;

  @override
  Widget build(BuildContext context) {
    final highlighted = status != AuthStepStatus.pending;

    return Container(
      width: authStepperBadgeSize,
      height: authStepperBadgeSize,
      decoration: BoxDecoration(
        color: highlighted
            ? authAccent
            : authSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted ? authAccent : authOutline,
        ),
        boxShadow: highlighted
            ? const [
                BoxShadow(
                  color: Color(0x18306B5F),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(
        switch (status) {
          AuthStepStatus.completed => Icons.check_rounded,
          AuthStepStatus.active => Icons.radio_button_checked_rounded,
          AuthStepStatus.pending => Icons.circle_outlined,
        },
        size: 15,
        color: highlighted ? Colors.white : authHint,
      ),
    );
  }
}
