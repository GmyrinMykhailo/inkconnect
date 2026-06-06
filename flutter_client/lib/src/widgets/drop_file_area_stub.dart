import 'package:flutter/widgets.dart';

import 'dropped_upload_file.dart';

class DropFileAreaPlatform extends StatelessWidget {
  const DropFileAreaPlatform({
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
    return child;
  }
}
