import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../utils.dart';
import '../controller/story_controller.dart';

class VideoLoader {
  String url;
  File? videoFile;
  Map<String, dynamic>? requestHeaders;
  LoadState state = LoadState.loading;

  VideoLoader(this.url, {this.requestHeaders});

  void loadVideo(VoidCallback onComplete) {
    if (this.videoFile != null) {
      this.state = LoadState.success;
      onComplete();
      return;
    }

    final fileStream = DefaultCacheManager().getFileStream(this.url,
        headers: this.requestHeaders as Map<String, String>?);

    fileStream.listen((fileResponse) {
      if (fileResponse is FileInfo) {
        if (this.videoFile == null) {
          this.state = LoadState.success;
          this.videoFile = fileResponse.file;
          onComplete();
        }
      }
    }, onError: (error) {
      this.state = LoadState.failure;
      onComplete();
    });
  }
}

class StoryVideo extends StatefulWidget {
  final StoryController? storyController;
  final VideoLoader videoLoader;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  StoryVideo(
      this.videoLoader, {
        Key? key,
        this.storyController,
        this.loadingWidget,
        this.errorWidget,
      }) : super(key: key ?? UniqueKey());

  static StoryVideo url(
      String url, {
        StoryController? controller,
        Map<String, dynamic>? requestHeaders,
        Key? key,
        Widget? loadingWidget,
        Widget? errorWidget,
      }) {
    return StoryVideo(
      VideoLoader(url, requestHeaders: requestHeaders),
      storyController: controller,
      key: key,
      loadingWidget: loadingWidget,
      errorWidget: errorWidget,
    );
  }

  @override
  State<StatefulWidget> createState() {
    return StoryVideoState();
  }
}

class StoryVideoState extends State<StoryVideo> {
  StreamSubscription? _streamSubscription;
  VideoPlayerController? playerController;
  bool isInitializing = false;

  @override
  void initState() {
    super.initState();

    widget.storyController?.pause();

    widget.videoLoader.loadVideo(() {
      if (widget.videoLoader.state == LoadState.success) {
        if (mounted) {
          setState(() {
            isInitializing = true;
          });
        }

        this.playerController =
            VideoPlayerController.file(widget.videoLoader.videoFile!);

        playerController!.initialize().then((v) {
          if (mounted) {
            setState(() {
              isInitializing = false;
            });
            widget.storyController?.play();
          }
        }).catchError((error) {
          if (mounted) {
            setState(() {
              isInitializing = false;
            });
          }
        });

        if (widget.storyController != null) {
          _streamSubscription =
              widget.storyController!.playbackNotifier.listen((playbackState) {
                if (playbackState == PlaybackState.pause) {
                  playerController?.pause();
                } else {
                  playerController?.play();
                }
              });
        }
      } else {
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  Widget getContentView() {
    // Case 1: Video is successfully loaded and initialized
    if (widget.videoLoader.state == LoadState.success &&
        playerController != null &&
        playerController!.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: playerController!.value.aspectRatio,
          child: VideoPlayer(playerController!),
        ),
      );
    }

    // Case 2: Still loading file OR initializing the player
    // This is the CRITICAL FIX: show loading while initializing even if state is success
    if (widget.videoLoader.state == LoadState.loading || isInitializing) {
      return Center(
        child: widget.loadingWidget ??
            const SizedBox(
              width: 70,
              height: 70,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
            ),
      );
    }

    // Case 3: Failed to load or initialize
    return Center(
      child: widget.errorWidget ??
          const Text(
            "Media failed to load.",
            style: TextStyle(
              color: Colors.white,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      height: double.infinity,
      width: double.infinity,
      child: getContentView(),
    );
  }

  @override
  void dispose() {
    playerController?.dispose();
    _streamSubscription?.cancel();
    super.dispose();
  }
}
