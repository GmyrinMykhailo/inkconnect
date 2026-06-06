import 'package:flutter/widgets.dart';

import 'dropped_upload_file.dart';
import 'drop_file_area_stub.dart'
    if (dart.library.html) 'drop_file_area_web.dart' as platform;

class DropFileArea extends StatelessWidget {
  const DropFileArea({
    super.key,
    required this.child,
    required this.onTap,
    required this.onFilesDropped,
    this.onHoverChanged,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onTap;
  final Future<void> Function(List<DroppedUploadFile> files) onFilesDropped;
  final ValueChanged<bool>? onHoverChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return platform.DropFileAreaPlatform(
      enabled: enabled,
      onTap: onTap,
      onFilesDropped: onFilesDropped,
      onHoverChanged: onHoverChanged,
      child: child,
    );
  }
}
