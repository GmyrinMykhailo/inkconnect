import 'package:flutter/widgets.dart';

class AuthenticatedProfileAvatarScope extends InheritedWidget {
  const AuthenticatedProfileAvatarScope({
    super.key,
    required this.avatarUrl,
    required super.child,
  });

  final String avatarUrl;

  static String avatarUrlOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<
                AuthenticatedProfileAvatarScope>()
            ?.avatarUrl ??
        '';
  }

  @override
  bool updateShouldNotify(AuthenticatedProfileAvatarScope oldWidget) {
    return avatarUrl != oldWidget.avatarUrl;
  }
}
