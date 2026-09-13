import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'android_vrm_webview_adapter.dart';
import 'vrm_webview_adapter.dart';
import 'windows_vrm_webview_adapter.dart';

VrmWebViewAdapter createVrmWebViewAdapter({required Color backgroundColor}) {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => AndroidVrmWebViewAdapter(
      backgroundColor: backgroundColor,
    ),
    TargetPlatform.windows => WindowsVrmWebViewAdapter(
      backgroundColor: backgroundColor,
    ),
    _ => throw UnsupportedError(
      'flutter_three_vrm supports Android and Windows only.',
    ),
  };
}
