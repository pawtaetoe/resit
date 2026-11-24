import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

/// Hands a downloaded file to another app on the device (Word, Slides,
/// Sheets, an archive viewer...). An interface so tests can stand in for the
/// device.
abstract interface class FileOpener {
  /// Whether an app took the file.
  Future<bool> open(String path);
}

/// The device's own "open with": Android and iOS through their share
/// mechanisms, desktops through the system's default app.
class SystemFileOpener implements FileOpener {
  const SystemFileOpener();

  @override
  Future<bool> open(String path) async {
    try {
      return (await OpenFilex.open(path)).type == ResultType.done;
    } catch (_) {
      return false;
    }
  }
}

final fileOpenerProvider = Provider<FileOpener>((ref) => const SystemFileOpener());
