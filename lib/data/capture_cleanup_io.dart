import 'dart:io';

/// Deletes only the temporary image path returned by our camera capture.
Future<void> discardCameraCapture(String path) async {
  if (path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // A device/OS may already have removed its temporary file.
  }
}
