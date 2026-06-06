import 'package:flutter/material.dart';

class RemoteOrAssetImage extends StatelessWidget {
  const RemoteOrAssetImage({
    super.key,
    required this.assetPath,
    this.imageUrl = '',
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  final String assetPath;
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final fallback = _fallback();
    final url = imageUrl.trim();
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

  Widget _fallback() {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return placeholder ??
            ColoredBox(
              color: const Color(0xFFE5E7EB),
              child: SizedBox(width: width, height: height),
            );
      },
    );
  }
}
