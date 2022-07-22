import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:video_editor/domain/bloc/controller.dart';
import 'package:video_editor/domain/entities/thumbnail_request_data.dart';
import 'package:video_editor/domain/entities/transform_data.dart';
import 'package:video_editor/ui/crop/crop_grid_painter.dart';
import 'package:video_editor/ui/transform.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:visibility_detector/visibility_detector.dart';

class ThumbnailSlider extends StatefulWidget {
  const ThumbnailSlider({
    Key? key,
    required this.controller,
    this.height = 60,
    this.quality = 10,
  }) : super(key: key);

  /// The [quality] param specifies the quality of the generated thumbnails, from 0 to 100, (([more info](https://pub.dev/packages/video_thumbnail)))
  final int quality;

  /// The [height] param specifies the height of the generated thumbnails
  final double height;

  final VideoEditorController controller;

  @override
  State<ThumbnailSlider> createState() => _ThumbnailSliderState();
}

class _ThumbnailSliderState extends State<ThumbnailSlider> {
  final ValueNotifier<Rect> _rect = ValueNotifier<Rect>(Rect.zero);
  final ValueNotifier<TransformData> _transform =
      ValueNotifier<TransformData>(TransformData());
  Future<File>? _pendingListRunner;

  double _aspect = 1.0, _width = 1.0;
  int _thumbnails = 8;

  Size _layout = Size.zero;
  List<ThumbnailRequestData> _currentThumbnailFiles = [];
  late final Stream<List<ThumbnailRequestData>> _stream =
      (() => _generateThumbnails().map((thumbnailFiles) {
            _currentThumbnailFiles = thumbnailFiles;
            return thumbnailFiles;
          }))();

  @override
  void initState() {
    super.initState();
    _aspect = widget.controller.video.value.aspectRatio;
    widget.controller.addListener(_scaleRect);

    // init the widget with controller values
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaleRect();
    });

    super.initState();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scaleRect);
    _transform.dispose();
    _rect.dispose();

    _deleteAllThumbnailFiles();

    super.dispose();
  }

  /// Deletes all thumbnail files currently cached in [_currentThumbnailFiles] to
  /// clean up all documents/images created for this thumbnail-slider.
  void _deleteAllThumbnailFiles() async {
    for (var thumbnailFile in _currentThumbnailFiles) {
      thumbnailFile.deleteFile().then((fileEntity) {
        debugPrint('Deleted file $fileEntity');
      });
    }
  }

  void _scaleRect() {
    _rect.value = _calculateTrimRect();
    _transform.value = TransformData.fromRect(
      _rect.value,
      _layout,
      widget.controller,
    );
  }

  Stream<List<ThumbnailRequestData>> _generateThumbnails() async* {
    final String path = widget.controller.file.path;
    final int durationMs =
        widget.controller.video.value.duration.inMilliseconds;
    final double eachPart = durationMs / _thumbnails;
    List<ThumbnailRequestData> fileList = [];
    for (int i = 1; i <= _thumbnails; i++) {
      try {
        final timeMs = math.min(
          (eachPart * i).toInt(),
          durationMs,
        );

        final fileName = '${path.split("/").last.split('.').first}_$timeMs.jpg';
        final thumbnailPath = join(dirname(path), fileName);

        fileList.add(
          ThumbnailRequestData(
            thumbnailRequest: () async {
              final String? outputPath = await VideoThumbnail.thumbnailFile(
                imageFormat: ImageFormat.JPEG,
                video: path,
                thumbnailPath: thumbnailPath,
                timeMs: timeMs,
                quality: widget.quality,
              );
              if (outputPath != null) {
                return File(outputPath);
              } else {
                throw 'Thumbnail-generation failed for video $path.';
              }
            },
          ),
        );
      } catch (e) {
        debugPrint(e.toString());
      }
      yield fileList;
    }
  }

  Future<File> _workPendingList(ThumbnailRequestData thumbnailData) async {
    final result = await thumbnailData.execute();

    final nextJob = _currentThumbnailFiles.firstWhereOrNull(
      (thumbnailData) =>
          !thumbnailData.alreadyRequested && thumbnailData.inViewPort,
    );
    if (nextJob != null) {
      _pendingListRunner = _workPendingList(nextJob);
    } else {
      _pendingListRunner = null;
    }
    return result;
  }

  Rect _calculateTrimRect() {
    final Offset min = widget.controller.minCrop;
    final Offset max = widget.controller.maxCrop;
    return Rect.fromPoints(
      Offset(
        min.dx * _layout.width,
        min.dy * _layout.height,
      ),
      Offset(
        max.dx * _layout.width,
        max.dy * _layout.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) {
        final double width = box.maxWidth;
        if (_width != width) {
          _width = width;
          _layout = _aspect <= 1.0
              ? Size(widget.height * _aspect, widget.height)
              : Size(widget.height, widget.height / _aspect);
          _thumbnails = (_width ~/ _layout.width) + 1;
          _rect.value = _calculateTrimRect();
        }
        final thumbnailLoadingReplacement = SizedBox(
          width: _layout.width,
          height: _layout.height,
        );

        return StreamBuilder(
          stream: _stream,
          builder: (_, AsyncSnapshot<List<ThumbnailRequestData>> snapshot) {
            final data = snapshot.data;
            return snapshot.hasData
                ? ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: data!.length,
                    itemBuilder: (_, int index) {
                      return ValueListenableBuilder(
                        valueListenable: _transform,
                        builder: (_, TransformData transform, __) {
                          return CropTransform(
                            transform: transform,
                            child: Container(
                              alignment: Alignment.center,
                              height: _layout.height,
                              width: _layout.width,
                              child: Stack(
                                children: [
                                  VisibilityDetector(
                                    key: ValueKey('thumbnail-$index'),
                                    onVisibilityChanged:
                                        (visibilityInfo) async {
                                      final visiblePercentage =
                                          visibilityInfo.visibleFraction * 100;
                                      if (visiblePercentage == 0) {
                                        data[index].inViewPort = false;
                                      } else {
                                        data[index].inViewPort = true;
                                        if (!data[index].alreadyRequested) {
                                          debugPrint(
                                            'Requested thumbnail $index due to $visiblePercentage',
                                          );

                                          _pendingListRunner ??=
                                              _workPendingList(
                                            data[index],
                                          );
                                        }
                                      }
                                    },
                                    child: FutureBuilder<File>(
                                      future: data[index].thumbnailFile$,
                                      initialData: data[index].thumbnailFile,
                                      builder: (context, snapshot) {
                                        final file = snapshot.data;
                                        if (!snapshot.hasData || file == null) {
                                          return thumbnailLoadingReplacement;
                                        }

                                        return Image.file(
                                          file,
                                          width: _layout.width,
                                          height: _layout.height,
                                          alignment: Alignment.topLeft,
                                        );
                                      },
                                    ),
                                  ),
                                  CustomPaint(
                                    size: _layout,
                                    painter: CropGridPainter(
                                      _rect.value,
                                      showGrid: false,
                                      style: widget.controller.cropStyle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  )
                : const SizedBox();
          },
        );
      },
    );
  }
}
