import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'windows_webview_screen.dart';

const String _baseUrl = 'https://service.agrotehcomert.com';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0A0A12),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A12),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const AgroTehComertApp());
}

class AgroTehComertApp extends StatelessWidget {
  const AgroTehComertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroTehComert Service',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFC),
          brightness: Brightness.dark,
          surface: const Color(0xFF1A1A22),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A12),
      ),
      home: (!kIsWeb && Platform.isWindows)
          ? const WindowsWebViewScreen()
          : const WebViewScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _webViewReady = false;
  bool _hasError = false;

  static const String _githubRepo = 'trekgame55/apk';

  @override
  void initState() {
    super.initState();
    _initWebView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _hasError = false);
            _injectPushSupport();
          },
          onPageFinished: (url) {
            setState(() => _webViewReady = true);
            _requestWebNotificationPermission();
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
            if (error.isForMainFrame ?? true) {
              setState(() => _hasError = true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_baseUrl));
  }

  void _injectPushSupport() {
    _controller.runJavaScript('''
      (function() {
        if (!window._flutterPushInjected) {
          window._flutterPushInjected = true;
          if (typeof Notification === "undefined") {
            window.Notification = function Notification(title, options) {};
            window.Notification.permission = "granted";
            window.Notification.requestPermission = function() {
              return Promise.resolve("granted");
            };
          } else if (Notification.permission === "default" || Notification.permission === "denied") {
            try {
              Object.defineProperty(Notification, "permission", { get: function() { return "granted"; } });
            } catch(e) {}
          }
          if (!("serviceWorker" in navigator)) {
            try {
              Object.defineProperty(navigator, "serviceWorker", {
                value: {
                  ready: Promise.resolve({
                    pushManager: {
                      subscribe: function() { return Promise.resolve({ endpoint: "flutter-fcm", toJSON: function() { return {}; } }); },
                      getSubscription: function() { return Promise.resolve(null); },
                      permissionState: function() { return Promise.resolve("granted"); }
                    },
                    showNotification: function() {}
                  }),
                  register: function() { return Promise.resolve({}); },
                  getRegistrations: function() { return Promise.resolve([]); }
                },
                configurable: true
              });
            } catch(e) {}
          }
        }
      })();
    ''');
  }

  void _requestWebNotificationPermission() {
    _controller.runJavaScript('''
      (function() {
        if ("Notification" in window && Notification.permission === "default") {
          Notification.requestPermission();
        }
      })();
    ''');
  }

  Future<void> _checkForUpdates() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      debugPrint('Current app version: $currentVersion');

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestTag = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
        final downloadUrl = data['html_url'] as String? ?? 'https://github.com/$_githubRepo/releases/latest';
        if (latestTag.isNotEmpty && _isNewerVersion(latestTag, currentVersion)) {
          final prefs = await SharedPreferences.getInstance();
          final dismissed = prefs.getString('dismissed_update') ?? '';
          if (dismissed != latestTag && mounted) {
            _showUpdateDialog(latestTag, downloadUrl);
          }
        }
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
  }

  bool _isNewerVersion(String latest, String current) {
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final maxLen = l.length > c.length ? l.length : c.length;
    while (l.length < maxLen) l.add(0);
    while (c.length < maxLen) c.add(0);
    for (var i = 0; i < maxLen; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  void _showUpdateDialog(String version, String downloadUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Color(0xFF7C5CFC), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Доступно обновление',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Вышла новая версия $version. Хотите скачать обновление?',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('dismissed_update', version);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Позже', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('Скачать'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C5CFC),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplash() {
    return Container(
      color: const Color(0xFF0A0A12),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF7C5CFC), strokeWidth: 3),
            SizedBox(height: 20),
            Text(
              'AgroTehComert',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Загрузка...',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Container(
      color: const Color(0xFF0A0A12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Нет подключения',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Проверьте интернет-соединение',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _hasError = false);
                _controller.loadRequest(Uri.parse(_baseUrl));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CFC),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: SafeArea(
        child: _hasError
            ? _buildErrorScreen()
            : _webViewReady
                ? WebViewWidget(controller: _controller)
                : _buildSplash(),
      ),
    );
  }
}
