import 'dart:typed_data';

class DroppedUploadFile {
  const DroppedUploadFile({
    required this.name,
    required this.size,
    required this.bytes,
  });

  final String name;
  final int size;
  final Uint8List bytes;
}
