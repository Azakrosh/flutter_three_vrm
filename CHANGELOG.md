# Changelog

## 0.2.0-dev.1

- Preserve user camera pan/zoom across runtime recovery and emit reliable user-initiated camera change events.

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
- Add a typed normalized humanoid Pose API backed by `VRMHumanoid`.
- Add rest-pose-aware Mixamo-style GLB/glTF retargeting, named clip selection, and configurable root motion.
- Add protected multi-file resource bundles for glTF files with external buffers or textures.
- Make the renderer FPS cap effective and use mobile-safe 60 FPS / 1.5 pixel-ratio defaults.
- Add graphics presets, adaptive resolution, performance telemetry, and WebGL context recovery.
- Move all runtime events to versioned protocol envelopes and remove legacy message entry points.
- Replace the legacy example with a focused app demonstrating the production API.
- Add abortable, race-safe model and animation loading while retaining the current avatar until replacement succeeds.
- Add typed model diagnostics for geometry, textures, rig complexity, and source size.
- Add configurable model-complexity assessments, decoded texture memory estimates, and proactive adaptive-resolution caps without rejecting assets.
- Add versioned animation-queue snapshots, automatic replay after model/runtime recreation, and a typed queue error stream.
- Add runtime readiness waiting, typed Three/WebGL health diagnostics, manual reload, and bounded main-frame recovery.
- Add strict analysis, unit tests, Android/Windows CI, MIT license, and updated documentation.
