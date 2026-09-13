# Changelog

## 0.2.0-dev.1

- Raise the minimum versions to Dart 3.12 and Flutter 3.44.
- Add dedicated Android and Windows WebView adapters.
- Upgrade to `webview_flutter 4.14.1` and `webview_flutter_windows 1.2.0`.
- Replace vendored JavaScript modules with a reproducible pnpm/esbuild runtime using `three 0.180.0`, `@pixiv/three-vrm 3.5.5`, and `@pixiv/three-vrm-animation 3.5.5`.
- Add a versioned command/response bridge with correlation ids, errors, and timeouts.
- Replace the global fixed-port server with a session-scoped loopback content host using random ports, opaque resource ids, and strict Host validation.
- Add authenticated-download handoff through `loadModelFromFile()` and `loadModelFromBytes()` without exposing credentials to WebView.
- Remove the WebView IndexedDB model cache and release hosted resources after parsing.
- Remove camera preset API and report serializable pan/zoom camera state.
- Pause rendering automatically with the Flutter application lifecycle.
- Add strict analysis, unit tests, Android/Windows CI, MIT license, and updated documentation.