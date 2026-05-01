import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class CallPipService {
  Future<bool> enterPictureInPicture({
    int aspectRatioWidth = 16,
    int aspectRatioHeight = 9,
  });
}

class MethodChannelCallPipService implements CallPipService {
  const MethodChannelCallPipService({
    MethodChannel channel = const MethodChannel('rodnya/call_pip'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<bool> enterPictureInPicture({
    int aspectRatioWidth = 16,
    int aspectRatioHeight = 9,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'enterPictureInPicture',
            <String, int>{
              'width': aspectRatioWidth,
              'height': aspectRatioHeight,
            },
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
