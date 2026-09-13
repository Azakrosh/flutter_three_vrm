import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'bridge/local_server.dart';
import 'vrm_controller.dart';

/// Flutter widget that renders a VRM 1.0 3D avatar scene inside a WebGL WebView canvas.
class VrmView extends StatefulWidget {
  /// Controller to interact with the VRM avatar scene.
  final VrmController controller;

  /// Callback fired when the WebView and WebGL engine have finished initialization.
  final void Function(VrmController controller)? onCreated;

  /// Optional initial model folder path (e.g. `'assets/vrm/'`).
  final String? initialModelFolder;

  /// Optional initial model file name (e.g. `'avatar.vrm'`).
  final String? initialModelFile;

  /// Background color of the 3D viewport canvas.
  final Color backgroundColor;

  /// Whether the WebGL canvas should have a transparent background.
  final bool transparent;

  const VrmView({
    super.key,
    required this.controller,
    this.onCreated,
    this.initialModelFolder,
    this.initialModelFile,
    this.backgroundColor = const Color(0xFF1E1E2C),
    this.transparent = false,
  });

  @override
  State<VrmView> createState() => _VrmViewState();
}

class _VrmViewState extends State<VrmView> {
  late final WebViewController _webViewController;
  bool _isWebViewReady = false;
  bool _hasError = false;
  String _errorMessage = '';
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _initWebView();

    // Подписываемся на события от JS-движка, чтобы убедиться, что он реально готов
    _subscriptions.add(
      widget.controller.onStateChanged.listen((event) {
        if (event.state == 'initialized' && mounted) {
          _onWebViewFullyInitialized();
        }
      }),
    );

    _subscriptions.add(
      widget.controller.onError.listen((event) {
        if (mounted && !_isWebViewReady) {
          setState(() {
            _hasError = true;
            _errorMessage = event.message;
          });
        }
      }),
    );
  }

  void _onWebViewFullyInitialized() async {
    setState(() {
      _isWebViewReady = true;
      _hasError = false;
    });

    if (widget.transparent) {
      widget.controller
          .setBackground(color: Colors.transparent, transparent: true);
    } else {
      widget.controller
          .setBackground(color: widget.backgroundColor, transparent: false);
    }

    if (widget.initialModelFolder != null && widget.initialModelFile != null) {
      await widget.controller
          .loadModel(widget.initialModelFolder!, widget.initialModelFile!);
    }

    widget.onCreated?.call(widget.controller);
  }

  void _initWebView() {
    final params = const PlatformWebViewControllerCreationParams();

    _webViewController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(
          widget.transparent ? Colors.transparent : widget.backgroundColor)
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (JavaScriptMessage message) {
          widget.controller.bridge.handleJsMessage(message);
        },
      )
      ..setOnConsoleMessage((message) {
        debugPrint(
            'VRM WebView JS Console [${message.level.name}]: ${message.message}');
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            debugPrint('VrmView: onPageFinished for URL: $url');
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('VrmView Web Resource Error: ${error.description}');
            if (mounted) {
              setState(() {
                _hasError = true;
                _errorMessage = 'Web Resource Error: ${error.description}';
              });
            }
          },
        ),
      );

    // Привязываем контроллер сразу, чтобы мост был готов принимать команды.
    // Команды все равно будут выполняться после события 'initialized' от JS.
    widget.controller.attachWebViewController(_webViewController);

    _loadRunnerPage();
  }

  Future<void> _loadRunnerPage() async {
    try {
      debugPrint('VrmView: Starting LocalAssetsServer...');
      String basePath = 'assets/web';
      try {
        await rootBundle
            .load('packages/flutter_three_vrm/assets/web/index.html');
        basePath = 'packages/flutter_three_vrm/assets/web';
      } catch (_) {
        // Fallback
      }

      final port = await LocalAssetsServer.start(basePath);
      debugPrint(
          'VrmView: LocalAssetsServer started on port $port, basePath: $basePath');

      final url = 'http://127.0.0.1:$port/index.html';
      debugPrint('VrmView: Loading WebView with URL: $url');
      await _webViewController.loadRequest(Uri.parse(url));
    } catch (e) {
      debugPrint('VrmView: Error loading WebGL runner: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load WebView assets: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    LocalAssetsServer.decrementUsage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.transparent ? Colors.transparent : widget.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _webViewController),
          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error loading VRM Engine:\n$_errorMessage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
              ),
            )
          else if (!_isWebViewReady)
            Container(
              color: widget.transparent
                  ? Colors.transparent
                  : widget.backgroundColor,
            ),
        ],
      ),
    );
  }
}
