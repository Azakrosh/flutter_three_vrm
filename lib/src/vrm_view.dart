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
  late final VrmViewLifecycleCoordinator _viewLifecycle;
  late final VrmLatestTaskDispatcher<_VrmGraphicsConfiguration>
  _graphicsConfigurations;
  late final VrmLatestTaskDispatcher<_VrmBackgroundConfiguration>
  _backgroundConfigurations;
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
    _graphicsConfigurations = VrmLatestTaskDispatcher(
      dispatch: _dispatchGraphicsConfiguration,
    );
    _backgroundConfigurations = VrmLatestTaskDispatcher(
      dispatch: _dispatchBackgroundConfiguration,
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
        await _synchronizeGraphicsConfiguration();
      },
      onModelUnloaded: () async {
        if (_modelAssessment == null) return;
        _modelAssessment = null;
        await _synchronizeGraphicsConfiguration();
      },
      onBridgeMessageError: (error, stackTrace) {
        _session.showError('WebView bridge error: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
      onRuntimeResourceError: _session.handleRuntimeResourceError,
    );
    _session.attachControllerBinding(controllerBinding);
    _viewLifecycle = VrmViewLifecycleCoordinator(initialize: _initialize);
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
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    if (controllerChanged) {
      _session.rebindController(widget.controller._createRuntimeEndpoint());
    }
    if (_session.isRuntimeReady &&
        (controllerChanged ||
            oldWidget.graphicsPreset != widget.graphicsPreset ||
            oldWidget.adaptiveQuality != widget.adaptiveQuality ||
            oldWidget.modelPerformancePolicy !=
                widget.modelPerformancePolicy)) {
      final report = _modelAssessment?.report;
      if (report != null) {
        _assessModel(report);
      }
      _queueGraphicsConfiguration();
    }
    if (_session.isRuntimeReady &&
        (controllerChanged ||
            oldWidget.backgroundColor != widget.backgroundColor ||
            oldWidget.transparent != widget.transparent)) {
      _queueBackgroundConfiguration();
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
      if (_isDisposed) return;

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
        applyGraphics: _synchronizeGraphicsConfiguration,
        applyBackground: _synchronizeBackgroundConfiguration,
        loadPackageModel: folder != null && file != null
            ? () => widget.controller.loadModel(folder, file)
            : null,
        applyApplicationState: () async =>
            widget.onCreated?.call(widget.controller),
      ),
    );
  }

  void _queueGraphicsConfiguration() {
    final configuration = _captureGraphicsConfiguration();
    unawaited(
      _graphicsConfigurations.submit(configuration).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (_isCurrentConfiguration(configuration.controller)) {
          debugPrint('Failed to configure VRM graphics: $error');
          debugPrintStack(stackTrace: stackTrace);
          _session.showError('Failed to configure VRM graphics: $error');
        }
      }),
    );
  }

  Future<void> _synchronizeGraphicsConfiguration() {
    return _graphicsConfigurations.submit(_captureGraphicsConfiguration());
  }

  _VrmGraphicsConfiguration _captureGraphicsConfiguration() {
    final assessment = _modelAssessment;
    final adaptiveQuality = assessment == null
        ? widget.adaptiveQuality
        : widget.modelPerformancePolicy.applyTo(
            widget.adaptiveQuality,
            assessment,
          );
    return _VrmGraphicsConfiguration(
      controller: widget.controller,
      preset: widget.graphicsPreset,
      adaptiveQuality: adaptiveQuality,
    );
  }

  Future<void> _dispatchGraphicsConfiguration(
    _VrmGraphicsConfiguration configuration,
  ) async {
    await configuration.controller.setGraphicsPreset(configuration.preset);
    await configuration.controller.setAdaptiveQuality(
      configuration.adaptiveQuality,
    );
  }

  void _queueBackgroundConfiguration() {
    final configuration = _captureBackgroundConfiguration();
    unawaited(
      _backgroundConfigurations.submit(configuration).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (error is VrmRuntimeException && error.code == 'canceled') return;
        if (_isCurrentConfiguration(configuration.controller)) {
          configuration.controller._bridge.reportAsyncError(error, stackTrace);
        }
      }),
    );
  }

  Future<void> _synchronizeBackgroundConfiguration() {
    return _backgroundConfigurations.submit(_captureBackgroundConfiguration());
  }

  _VrmBackgroundConfiguration _captureBackgroundConfiguration() {
    return _VrmBackgroundConfiguration(
      controller: widget.controller,
      color: _effectiveBackground,
      transparent: widget.transparent,
    );
  }

  Future<void> _dispatchBackgroundConfiguration(
    _VrmBackgroundConfiguration configuration,
  ) {
    return configuration.controller.setBackground(
      color: configuration.color,
      transparent: configuration.transparent,
    );
  }

  bool _isCurrentConfiguration(VrmController controller) {
    return _session.isRuntimeReady &&
        !_isDisposed &&
        identical(controller, widget.controller);
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
    _graphicsConfigurations.close();
    _backgroundConfigurations.close();
    final declarativeTaskSettlement = Future.wait<void>([
      _graphicsConfigurations.idle,
      _backgroundConfigurations.idle,
    ]);
    final sessionDisposal = _session.dispose();
    WidgetsBinding.instance.removeObserver(this);
    observeVrmViewLifecycleDisposal(
      _viewLifecycle.dispose(
        settleBeforeCleanup: () => declarativeTaskSettlement,
        cleanup: () =>
            _disposeRuntimeAndWebView(shouldDisposeRuntime, sessionDisposal),
      ),
      reportError: (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'flutter_three_vrm',
            context: ErrorDescription('while disposing a VrmView'),
          ),
        );
      },
    );

    super.dispose();
  }

  Future<void> _disposeRuntimeAndWebView(
    bool disposeRuntime,
    Future<void> sessionDisposal,
  ) async {
    if (disposeRuntime) {
      try {
        await _webView.runJavaScript('window.flutterVrmDispose?.();');
      } on Object {
        // The native WebView may already have destroyed the document.
      }
    }

    try {
      await sessionDisposal;
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to dispose the VRM runtime session: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      await _webView.dispose();
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to dispose the VRM WebView: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
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

final class _VrmGraphicsConfiguration {
  const _VrmGraphicsConfiguration({
    required this.controller,
    required this.preset,
    required this.adaptiveQuality,
  });

  final VrmController controller;
  final VrmGraphicsPreset preset;
  final VrmAdaptiveQualitySettings adaptiveQuality;
}

final class _VrmBackgroundConfiguration {
  const _VrmBackgroundConfiguration({
    required this.controller,
    required this.color,
    required this.transparent,
  });

  final VrmController controller;
  final Color color;
  final bool transparent;
}
