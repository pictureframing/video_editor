import 'dart:io';
import 'dart:async';

/// A request to create a video´s thumbnail image,.
///
/// Use [execute] to trigger the provided [thumbnailRequest].
class ThumbnailRequestData {
  /// The request to trigger a video´s thumbnail creation
  /// which is triggered by [execute].
  Future<File> Function() thumbnailRequest;

  /// A Completer that completes after the [thumbnailRequest]
  /// was triggered by [execute] and successfully completed.
  final Completer<File> _fileCompleter;

  /// The Future of the [_fileCompleter].
  Future<File> get thumbnailFile$ => _fileCompleter.future;

  /// The [File] the [_fileCompleter] was completed with.
  ///
  /// May be null if the [_fileCompleter] has not been completed yet.
  File? _cachedFile;

  /// The [thumbnailFile$]’s current value.
  ///
  /// May be null if the [_fileCompleter] has not been completed yet.
  File? get thumbnailFile => _cachedFile;

  /// Whether or not [execute] has already been triggered once.
  ///
  /// Defaults to `false`.
  bool _alreadyRequested = false;

  bool get alreadyRequested => _alreadyRequested;

  /// Whether the [Image.file]-widget corresponding to this _ThumbnailRequestData
  /// was once or is currently in the thumbnail-slider’s viewport.
  bool inViewPort = false;

  /// A request to create a video´s thumbnail image,.
  ///
  /// Use [execute] to trigger the provided [thumbnailRequest].
  ThumbnailRequestData({
    required this.thumbnailRequest,
  }) : _fileCompleter = Completer<File>();

  /// Triggers the [thumbnailRequest].
  ///
  /// If the [thumbnailRequest] completes successfully, the [_fileCompleter]
  /// is completed with its result.
  Future<File> execute() async {
    if (_fileCompleter.isCompleted || _alreadyRequested) {
      return _fileCompleter.future;
    }
    _alreadyRequested = true;

    final File file = await thumbnailRequest();
    _cachedFile = file;
    _fileCompleter.complete(file);
    return file;
  }

  /// Deletes the [thumbnailFile] if it exists.
  Future<FileSystemEntity?> deleteFile() async {
    if (_fileCompleter.isCompleted) {
      return _fileCompleter.future.then((value) {
        return value.exists().then((exists) {
          if (exists) {
            return value.delete();
          }
        });
      });
    }
    return null;
  }
}
