import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import 'dropped_upload_file.dart';

class DropFileAreaPlatform extends StatefulWidget {
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
  State<DropFileAreaPlatform> createState() => _DropFileAreaPlatformState();
}

class _DropFileAreaPlatformState extends State<DropFileAreaPlatform> {
  late final String _viewType;
  late final html.DivElement _element;
  final List<StreamSubscription<html.Event>> _subscriptions = [];
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _viewType =
        'inkconnect-drop-file-area-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    _element = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'transparent'
      ..style.cursor = 'pointer';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _element,
    );

    _subscriptions
      ..add(_element.onClick.listen(_handleClick))
      ..add(_element.onDragEnter.listen(_handleDragEnter))
      ..add(_element.onDragOver.listen(_handleDragOver))
      ..add(_element.onDragLeave.listen(_handleDragLeave))
      ..add(_element.onDrop.listen(_handleDrop));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DropFileAreaPlatform oldWidget) {
    super.didUpdateWidget(oldWidget);
    _element.style.cursor = widget.enabled ? 'pointer' : 'default';
    if (!widget.enabled && _hovered) {
      _setHovered(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: HtmlElementView(viewType: _viewType),
        ),
      ],
    );
  }

  void _handleClick(html.Event event) {
    if (!widget.enabled) {
      return;
    }
    event.preventDefault();
    widget.onTap();
  }

  void _handleDragEnter(html.Event event) {
    if (!widget.enabled) {
      return;
    }
    event.preventDefault();
    _setHovered(true);
  }

  void _handleDragOver(html.Event event) {
    if (!widget.enabled) {
      return;
    }
    event.preventDefault();
    final mouseEvent = event;
    if (mouseEvent is html.MouseEvent) {
      mouseEvent.dataTransfer?.dropEffect = 'copy';
    }
    _setHovered(true);
  }

  void _handleDragLeave(html.Event event) {
    if (!widget.enabled) {
      return;
    }
    event.preventDefault();
    _setHovered(false);
  }

  Future<void> _handleDrop(html.Event event) async {
    if (!widget.enabled) {
      return;
    }
    event.preventDefault();
    _setHovered(false);

    final mouseEvent = event;
    if (mouseEvent is! html.MouseEvent) {
      return;
    }
    final fileList = mouseEvent.dataTransfer?.files;
    if (fileList == null || fileList.isEmpty) {
      return;
    }

    final files = <DroppedUploadFile>[];
    for (var index = 0; index < fileList.length; index += 1) {
      final file = fileList[index];
      final bytes = await _readFile(file);
      files.add(
        DroppedUploadFile(
          name: file.name,
          size: file.size,
          bytes: bytes,
        ),
      );
    }
    if (files.isNotEmpty) {
      await widget.onFilesDropped(files);
    }
  }

  Future<Uint8List> _readFile(html.File file) {
    final completer = Completer<Uint8List>();
    final reader = html.FileReader();
    late final StreamSubscription<html.ProgressEvent> loadSubscription;
    late final StreamSubscription<html.ProgressEvent> errorSubscription;

    loadSubscription = reader.onLoad.listen((event) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(Uint8List.view(result));
      } else if (result is Uint8List) {
        completer.complete(result);
      } else {
        completer.complete(Uint8List(0));
      }
      loadSubscription.cancel();
      errorSubscription.cancel();
    });
    errorSubscription = reader.onError.listen((event) {
      completer.completeError(reader.error ?? StateError('read dropped file'));
      loadSubscription.cancel();
      errorSubscription.cancel();
    });
    reader.readAsArrayBuffer(file);
    return completer.future;
  }

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    _hovered = value;
    widget.onHoverChanged?.call(value);
  }
}
