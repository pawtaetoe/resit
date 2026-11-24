import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/data/file_opener.dart';
import 'package:resit/features/lms/data/topic_files.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';

/// Draws a PDF from a local file. A provider so tests can stand in for the
/// native PDF engine (PDFium), which isn't available to widget tests.
final pdfViewBuilderProvider = Provider<Widget Function(String path)>(
  (ref) => (path) => PdfViewer.file(
        path,
        params: const PdfViewerParams(
          margin: 8,
          backgroundColor: Colors.transparent,
        ),
      ),
);

/// A downloaded course file shown in the app: a PDF in a viewer, or an
/// image that can be zoomed. Its bar offers the file to another app, or
/// the item on xSiTe.
class FileViewScreen extends ConsumerWidget {
  final SavedFile file;

  /// The item's page on xSiTe.
  final Uri onXsite;

  const FileViewScreen({super.key, required this.file, required this.onXsite});

  Future<void> _openElsewhere(BuildContext context, WidgetRef ref) async {
    final opened = await ref.read(fileOpenerProvider).open(file.path);
    if (!opened && context.mounted) showError(context, 'No app on this device opens ${file.name}.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPdf = viewFor(file.name) == FileView.pdf;
    return AppScaffold(
      appBar: thumbAppBar(file.name, subtitle: fileSizeLabel(file.size)),
      body: isPdf
          ? ref.watch(pdfViewBuilderProvider)(file.path)
          : InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.file(
                  File(file.path),
                  semanticLabel: file.name,
                  errorBuilder: (context, error, stack) => const MessageView(
                    icon: Icons.broken_image_outlined,
                    title: "Couldn't show this image",
                    message: 'Open it in another app or on xSiTe.',
                  ),
                ),
              ),
            ),
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _openElsewhere(context, ref),
                icon: const Icon(Icons.ios_share),
                label: const Text('Open in another app', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            ThumbIconButton(
              tooltip: 'Open on xSiTe',
              icon: Icons.open_in_new,
              onPressed: () => openInBrowser(context, onXsite),
            ),
          ],
        ),
      ),
    );
  }
}
