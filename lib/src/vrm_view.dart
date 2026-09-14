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
  });

  final VrmController controller;
  final void Function(VrmController controller)? onCreated;
  final String? initialModelFolder;
  final String? initialModelFile;
  final Color backgroundColor;
  final bool transparent;

  /// Renderer profile applied before [onCreated] and initial model loading.
  final VrmGraphicsPreset graphicsPreset;

  /// Automatic render-resolution policy applied after [graphicsPreset].
  final VrmAdaptiveQualitySettings adaptiveQuality;

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

  Color get _effectiveBackground =>
      widget.transparent ? Colors.transparent : widget.backgroundColor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webView = createVrmWebViewAdapter(backgroundColor: _effectiveBackground);
    _subscriptions.add(
      _webView.errors.listen(
        (message) => _showError('WebView resource error: $message'),
      ),
    );
    _bindController(widget.controller);
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant VrmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
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
      _bindController(widget.controller);
      if (_transportAttached) {
        _attachTransport(widget.controller);
      }
    }
    if (_isRuntimeReady &&
        (oldWidget.graphicsPreset != widget.graphicsPreset ||
            oldWidget.adaptiveQuality != widget.adaptiveQuality)) {
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
      widget.onCreated?.call(widget.controller);
    }
  }

  Future<void> _applyGraphicsConfiguration() async {
    try {
      await widget.controller.setGraphicsPreset(widget.graphicsPreset);
      await widget.controller.setAdaptiveQuality(widget.adaptiveQuality);
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to configure VRM graphics: $error\n$stackTrace');
      _showError('Failed to configure VRM graphics: $error');
    }
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
