import 'package:flutter/material.dart';

import 'remote_or_asset_image.dart';

class ProfileImage extends StatelessWidget {
  const ProfileImage({
    super.key,
    this.avatarUrl = '',
    this.fallbackAssetPath,
    this.letterFallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.circular = false,
    this.backgroundColor = const Color(0xFF2F5D50),
    this.letterStyle,
  });

  final String avatarUrl;
  final String? fallbackAssetPath;
  final String? letterFallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final bool circular;
  final Color backgroundColor;
  final TextStyle? letterStyle;

  @override
  Widget build(BuildContext context) {
    final radius = circular ? 999.0 : borderRadius;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: _image(),
      ),
    );
  }

  Widget _image() {
    final assetPath = fallbackAssetPath?.trim() ?? '';
    final fallback = _letterFallback();
    if (assetPath.isNotEmpty) {
      return RemoteOrAssetImage(
        assetPath: assetPath,
        imageUrl: avatarUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: fallback,
      );
    }

    final url = avatarUrl.trim();
    if (url.isEmpty) {
      return fallback;
    }

    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return fallback;
      },
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }

  Widget _letterFallback() {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Text(
          _letter,
          style: letterStyle ??
              const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }

  String get _letter {
    final value = letterFallback?.trim() ?? '';
    if (value.isEmpty) {
      return '?';
    }
    return String.fromCharCode(value.runes.first).toUpperCase();
  }
}
