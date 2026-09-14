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
  });

  final VrmController controller;
  final FutureOr<void> Function(VrmController controller)? onCreated;
  final String? initialModelFolder;
  final String? initialModelFile;
  final Color backgroundColor;
  final bool transparent;

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
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<StreamSubscription<dynamic>> _controllerSubscriptions = [];

  LocalAssetsServer? _contentHost;
  bool _transportAttached = false;
  bool _isRuntimeReady = false;
  bool _isDisposed = false;
  String? _errorMessage;
  VrmModelAssessment? _modelAssessment;
  int _recoveryAttempts = 0;
  bool _recoveryInProgress = false;
  bool _recoveryRequested = false;

  Color get _effectiveBackground =>
      widget.transparent ? Colors.transparent : widget.backgroundColor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webView = createVrmWebViewAdapter(backgroundColor: _effectiveBackground);
    _subscriptions.add(_webView.errors.listen(_handleRuntimeResourceError));
    _bindController(widget.controller);
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant VrmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      final hadModel = oldWidget.controller.isModelLoaded;
      oldWidget.controller._bridge.detachTransport(_webView);
      final contentHost = _contentHost;
      if (contentHost != null) {
        oldWidget.controller._detachContentHost(contentHost);
        widget.controller._attachContentHost(contentHost);
      }
      for (final subscription in _controllerSubscriptions) {
        unawaited(subscription.cancel());
      }
      _controllerSubscriptions.clear();
      widget.controller._isModelLoaded = hadModel;
      _bindController(widget.controller);
      if (_transportAttached) {
        _attachTransport(widget.controller);
      }
    }
    if (_isRuntimeReady &&
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
    if (_isRuntimeReady &&
        (oldWidget.backgroundColor != widget.backgroundColor ||
            oldWidget.transparent != widget.transparent)) {
      widget.controller.setBackground(
        color: _effectiveBackground,
        transparent: widget.transparent,
      );
    }
  }

  void _bindController(VrmController controller) {
    _controllerSubscriptions
      ..add(
        controller.onStateChanged.listen((event) {
          if (event.state == 'initialized') {
            unawaited(_onRuntimeInitialized());
          }
        }),
      )
      ..add(
        controller.onError.listen((event) {
          if (!_isRuntimeReady) {
            _showError(event.message);
          }
        }),
      )
      ..add(
        controller.onModelReport.listen((event) {
          _assessModel(event.report);
          unawaited(_applyAdaptiveQuality());
        }),
      )
      ..add(
        controller.onModelUnloaded.listen((_) {
          if (_modelAssessment == null) return;
          _modelAssessment = null;
          unawaited(_applyAdaptiveQuality());
        }),
      )
      ..add(
        _webView.messages.listen(
          controller._bridge.handleJsMessage,
          onError: (Object error, StackTrace stackTrace) {
            _showError('WebView bridge error: $error');
            debugPrintStack(stackTrace: stackTrace);
          },
        ),
      );
  }

  void _attachTransport(VrmController controller) {
    controller._bridge.attachTransport(
      owner: _webView,
      runJavaScript: _webView.runJavaScript,
      reloadRuntime: _reloadRuntimePage,
      runtimeReady: _isRuntimeReady,
    );
  }

  Future<void> _initialize() async {
    try {
      await _webView.initialize();
      if (_isDisposed) {
        await _webView.dispose();
        return;
      }

      _transportAttached = true;
      _attachTransport(widget.controller);
      await _loadRuntimePage();
    } on Object catch (error, stackTrace) {
      debugPrint('VrmView initialization failed: $error\n$stackTrace');
      _showError('Failed to initialize the VRM runtime: $error');
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
    _contentHost = contentHost;
    await contentHost.start();

    if (_isDisposed) {
      await contentHost.close();
      return;
    }

    widget.controller._attachContentHost(contentHost);
    await _webView.load(contentHost.runtimeUri);
  }

  Future<void> _onRuntimeInitialized() async {
    if (!mounted || _isRuntimeReady) {
      return;
    }

    setState(() {
      _isRuntimeReady = true;
      _errorMessage = null;
    });
    _recoveryAttempts = 0;
    _recoveryInProgress = false;
    _recoveryRequested = false;

    try {
      await _applyGraphicsConfiguration();
      widget.controller.setBackground(
        color: _effectiveBackground,
        transparent: widget.transparent,
      );

      final folder = widget.initialModelFolder;
      final file = widget.initialModelFile;
      if (folder != null && file != null) {
        await widget.controller.loadModel(folder, file);
      }

      if (mounted) {
        await widget.onCreated?.call(widget.controller);
      }
    } on Object catch (error, stackTrace) {
      widget.controller._bridge.reportAsyncError(error, stackTrace);
      _showError('Failed to configure restored VRM runtime: $error');
    }
  }

  void _handleRuntimeResourceError(String message) {
    final error = StateError('WebView runtime resource error: $message');
    widget.controller._markRuntimeUnavailable(error);
    if (mounted && !_isDisposed) {
      setState(() {
        _isRuntimeReady = false;
        _modelAssessment = null;
        _errorMessage = message;
      });
    }
    if (_recoveryInProgress) {
      _recoveryRequested = true;
      return;
    }
    unawaited(_scheduleRuntimeRecovery());
  }

  Future<void> _scheduleRuntimeRecovery() async {
    final policy = widget.recoveryPolicy;
    if (_isDisposed ||
        !policy.enabled ||
        _recoveryInProgress ||
        _recoveryAttempts >= policy.maxAttempts) {
      return;
    }
    _recoveryInProgress = true;
    _recoveryRequested = false;
    _recoveryAttempts += 1;
    try {
      await Future<void>.delayed(policy.delayForAttempt(_recoveryAttempts));
      if (!_isDisposed) {
        await _reloadRuntimePage();
      }
    } on Object catch (error, stackTrace) {
      _recoveryRequested = true;
      widget.controller._bridge.reportAsyncError(error, stackTrace);
      _showError('Failed to recover VRM runtime: $error');
    } finally {
      _recoveryInProgress = false;
      if (_recoveryRequested && !_isDisposed) {
        _recoveryRequested = false;
        unawaited(_scheduleRuntimeRecovery());
      }
    }
  }

  Future<void> _reloadRuntimePage() async {
    if (_isDisposed) {
      throw StateError('VrmView has already been disposed.');
    }
    final contentHost = _contentHost;
    if (contentHost == null || !contentHost.isStarted) {
      throw StateError('VRM runtime content host is not available.');
    }
    widget.controller._markRuntimeUnavailable(
      StateError('VRM runtime is reloading.'),
    );
    if (mounted) {
      setState(() {
        _isRuntimeReady = false;
        _modelAssessment = null;
        _errorMessage = null;
      });
    }
    await _webView.load(contentHost.runtimeUri);
  }

  Future<void> _applyGraphicsConfiguration() async {
    try {
      await widget.controller.setGraphicsPreset(widget.graphicsPreset);
      await _applyAdaptiveQuality();
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to configure VRM graphics: $error\n$stackTrace');
      _showError('Failed to configure VRM graphics: $error');
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

  void _showError(String message) {
    if (!mounted || _isDisposed) {
      return;
    }
    setState(() => _errorMessage = message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_transportAttached) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(widget.controller.resumeRendering());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(widget.controller.pauseRendering());
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    for (final subscription in [
      ..._subscriptions,
      ..._controllerSubscriptions,
    ]) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _controllerSubscriptions.clear();

    widget.controller._bridge.detachTransport(_webView);
    final contentHost = _contentHost;
    if (contentHost != null) {
      widget.controller._detachContentHost(contentHost);
      unawaited(contentHost.close());
    }
    unawaited(_webView.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _effectiveBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _webView.buildWidget(),
          if (_errorMessage case final message?)
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
          else if (!_isRuntimeReady)
            ColoredBox(color: _effectiveBackground),
        ],
      ),
    );
  }
}
