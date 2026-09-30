part of 'vrm_runtime.dart';

/// Renders one VRM avatar through the package's embedded WebGL runtime.
class VrmView extends StatefulWidget {
  const VrmView({
    super.key,
    required this.controller,
    this.onCreated,
    this.initialModelFolder,
    this.initialModelFile,
    this.backgroundColor = const Color(0xFF1E1E2C),
    this.transparent = false,
    this.graphicsPreset = VrmGraphicsPreset.balanced,
    this.adaptiveQuality = const VrmAdaptiveQualitySettings(),
    this.modelPerformancePolicy = const VrmModelPerformancePolicy(),
    this.recoveryPolicy = const VrmRuntimeRecoveryPolicy(),
    this.renderingEnabled = true,
    this.lifecyclePolicy = VrmRenderLifecyclePolicy.platformDefault,
  });

  final VrmController controller;
  final FutureOr<void> Function(VrmController controller)? onCreated;
  final String? initialModelFolder;
  final String? initialModelFile;
  final Color backgroundColor;
  final bool transparent;

  /// Whether the WebGL render loop may run when allowed by [lifecyclePolicy].
  final bool renderingEnabled;

  /// Determines which application lifecycle states pause the render loop.
  final VrmRenderLifecyclePolicy lifecyclePolicy;

  /// Renderer profile applied before [onCreated] and initial model loading.
  final VrmGraphicsPreset graphicsPreset;

  /// Automatic render-resolution policy applied after [graphicsPreset].
  final VrmAdaptiveQualitySettings adaptiveQuality;

  /// Advisory model analysis and proactive render-resolution policy.
  final VrmModelPerformancePolicy modelPerformancePolicy;

  /// Bounded retry policy for failures of the main runtime document.
  final VrmRuntimeRecoveryPolicy recoveryPolicy;

  @override
  State<VrmView> createState() => _VrmViewState();
}

class _VrmViewState extends State<VrmView> with WidgetsBindingObserver {
  late final VrmWebViewAdapter _webView;
  late final VrmRuntimeSessionCoordinator _session;
  bool _isDisposed = false;
  VrmModelAssessment? _modelAssessment;

  Color get _effectiveBackground =>
      widget.transparent ? Colors.transparent : widget.backgroundColor;

  @override
  void initState() {
    super.initState();
    _validateConfiguration();
    _webView = createVrmWebViewAdapter(backgroundColor: _effectiveBackground);
    WidgetsBinding.instance.addObserver(this);
    _session = VrmRuntimeSessionCoordinator(
      platform: defaultTargetPlatform,
      initialLifecycleState: WidgetsBinding.instance.lifecycleState,
      renderingEnabled: widget.renderingEnabled,
      lifecyclePolicy: widget.lifecyclePolicy,
      recoveryPolicy: widget.recoveryPolicy,
      dispatchRenderingPaused: (paused) =>
          widget.controller._setRenderingPaused(paused),
      reloadRuntimeDocument: _reloadRuntimeDocument,
      markRuntimeUnavailable: (reason) {
        _modelAssessment = null;
        widget.controller._markRuntimeUnavailable(reason);
      },
      reportAsyncError: (error, stackTrace) =>
          widget.controller._bridge.reportAsyncError(error, stackTrace),
      onChanged: () {
        if (mounted && !_isDisposed) setState(() {});
      },
      readCameraTransform: () => widget.controller._lastKnownCameraTransform,
      readCameraRevision: () => widget.controller._cameraTransformRevision,
      isModelLoaded: () => widget.controller.isModelLoaded,
      applyCameraTransform: (transform) =>
          widget.controller.setTransform(transform),
    );
    final controllerBinding = VrmRuntimeControllerBinding(
      endpoint: widget.controller._createRuntimeEndpoint(),
      webView: _webView,
      reloadRuntime: _session.reloadRuntime,
      isRuntimeReady: () => _session.isRuntimeReady,
      onRuntimeInitialized: _onRuntimeInitialized,
      onControllerError: (message) {
        if (!_session.isRuntimeReady) _session.showError(message);
      },
      onModelLoaded: _session.restoreCameraAfterModelLoad,
      onModelReport: (report) async {
        _assessModel(report);
        await _applyAdaptiveQuality();
      },
      onModelUnloaded: () async {
        if (_modelAssessment == null) return;
        _modelAssessment = null;
        await _applyAdaptiveQuality();
      },
      onBridgeMessageError: (error, stackTrace) {
        _session.showError('WebView bridge error: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
      onRuntimeResourceError: _session.handleRuntimeResourceError,
    );
    _session.attachControllerBinding(controllerBinding);
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant VrmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateConfiguration();
    _session.updateConfiguration(
      renderingEnabled: widget.renderingEnabled,
      lifecyclePolicy: widget.lifecyclePolicy,
      recoveryPolicy: widget.recoveryPolicy,
    );
    if (!identical(oldWidget.controller, widget.controller)) {
      _session.rebindController(widget.controller._createRuntimeEndpoint());
    }
    if (_session.isRuntimeReady &&
        (oldWidget.graphicsPreset != widget.graphicsPreset ||
            oldWidget.adaptiveQuality != widget.adaptiveQuality ||
            oldWidget.modelPerformancePolicy !=
                widget.modelPerformancePolicy)) {
      final report = _modelAssessment?.report;
      if (report != null) {
        _assessModel(report);
      }
      unawaited(_applyGraphicsConfiguration());
    }
    if (_session.isRuntimeReady &&
        (oldWidget.backgroundColor != widget.backgroundColor ||
            oldWidget.transparent != widget.transparent)) {
      unawaited(_applyBackgroundSafely());
    }
  }

  void _validateConfiguration() {
    widget.adaptiveQuality.validate();
    widget.modelPerformancePolicy.validate();
    widget.recoveryPolicy.validate();
  }

  Future<void> _initialize() async {
    try {
      await _webView.initialize();
      if (_isDisposed) {
        await _webView.dispose();
        return;
      }

      _session.attachTransport();
      await _loadRuntimePage();
    } on Object catch (error, stackTrace) {
      debugPrint('VrmView initialization failed: $error\n$stackTrace');
      _session.showError('Failed to initialize the VRM runtime: $error');
    }
  }

  Future<void> _loadRuntimePage() async {
    var runtimeAssetRoot = 'assets/web';
    try {
      await rootBundle.load('packages/flutter_three_vrm/assets/web/index.html');
      runtimeAssetRoot = 'packages/flutter_three_vrm/assets/web';
    } on FlutterError {
      // Running inside this package's example application.
    }

    final contentHost = LocalAssetsServer(runtimeAssetRoot: runtimeAssetRoot);
    await contentHost.start();

    if (_isDisposed) {
      await contentHost.close();
      return;
    }

    _session.attachContentHost(contentHost);
    await _webView.load(contentHost.runtimeUri);
  }

  Future<void> _onRuntimeInitialized() async {
    if (!mounted || _session.isRuntimeReady) return;
    final folder = widget.initialModelFolder;
    final file = widget.initialModelFile;
    await _session.activateRuntime(
      VrmRuntimeSessionReplayPlan(
        applyGraphics: _applyGraphicsConfiguration,
        applyBackground: () => widget.controller.setBackground(
          color: _effectiveBackground,
          transparent: widget.transparent,
        ),
        loadPackageModel: folder != null && file != null
            ? () => widget.controller.loadModel(folder, file)
            : null,
        applyApplicationState: () async =>
            widget.onCreated?.call(widget.controller),
      ),
    );
  }

  Future<void> _applyBackgroundSafely() async {
    final controller = widget.controller;
    try {
      await controller.setBackground(
        color: _effectiveBackground,
        transparent: widget.transparent,
      );
    } on VrmRuntimeException catch (error, stackTrace) {
      if (error.code == 'canceled') return;
      if (_session.isRuntimeReady &&
          !_isDisposed &&
          identical(controller, widget.controller)) {
        controller._bridge.reportAsyncError(error, stackTrace);
      }
    } on Object catch (error, stackTrace) {
      if (_session.isRuntimeReady &&
          !_isDisposed &&
          identical(controller, widget.controller)) {
        controller._bridge.reportAsyncError(error, stackTrace);
      }
    }
  }

  Future<void> _reloadRuntimeDocument() async {
    if (_isDisposed) {
      throw StateError('VrmView has already been disposed.');
    }
    final contentHost = _session.contentHost;
    if (contentHost == null || !contentHost.isStarted) {
      throw StateError('VRM runtime content host is not available.');
    }
    await _webView.load(contentHost.runtimeUri);
  }

  Future<void> _applyGraphicsConfiguration() async {
    try {
      await widget.controller.setGraphicsPreset(widget.graphicsPreset);
      await _applyAdaptiveQuality();
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to configure VRM graphics: $error\n$stackTrace');
      _session.showError('Failed to configure VRM graphics: $error');
    }
  }

  void _assessModel(VrmModelReport report) {
    try {
      final assessment = widget.modelPerformancePolicy.assess(report);
      _modelAssessment = assessment;
      widget.controller._publishModelAssessment(assessment);
    } on Object catch (error, stackTrace) {
      _modelAssessment = null;
      widget.controller._bridge.reportAsyncError(error, stackTrace);
    }
  }

  Future<void> _applyAdaptiveQuality() {
    final assessment = _modelAssessment;
    final settings = assessment == null
        ? widget.adaptiveQuality
        : widget.modelPerformancePolicy.applyTo(
            widget.adaptiveQuality,
            assessment,
          );
    return widget.controller.setAdaptiveQuality(settings);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.updateLifecycleState(state);
  }

  @override
  void didHaveMemoryPressure() {
    _session.recordHostMemoryPressure();
  }

  @override
  void dispose() {
    final shouldDisposeRuntime =
        _session.isTransportAttached && _session.isRuntimeReady;
    _isDisposed = true;
    _session.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeRuntimeAndWebView(shouldDisposeRuntime));

    super.dispose();
  }

  Future<void> _disposeRuntimeAndWebView(bool disposeRuntime) async {
    if (disposeRuntime) {
      try {
        await _webView.runJavaScript('window.flutterVrmDispose?.();');
      } on Object {
        // The native WebView may already have destroyed the document.
      }
    }
    await _webView.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _effectiveBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _webView.buildWidget(),
          if (_session.errorMessage case final message?)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading VRM engine:\n$message',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else if (!_session.isRuntimeReady)
            ColoredBox(color: _effectiveBackground),
        ],
      ),
    );
  }
}
