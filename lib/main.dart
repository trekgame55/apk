import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'windows_webview_screen.dart';

const String _baseUrl = 'https://service.agrotehcomert.com';
const String _githubRepo = 'trekgame55/apk';

// ─── Native notifications ───────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

String? _pendingNotifUrl;

Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _localNotifications.initialize(
    const InitializationSettings(android: android),
    onDidReceiveNotificationResponse: (details) {
      _pendingNotifUrl = details.payload;
    },
  );
  final androidImpl = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();
}

Future<void> _showNativeNotification(
    String title, String body, String urlPath) async {
  static int _id = 0;
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'alphatrack_main',
      'AlphaTrack',
      channelDescription: 'Уведомления AlphaTrack',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    ),
  );
  await _localNotifications.show(_id++ % 9999, title, body, details,
      payload: urlPath);
}

// ─── App entry ───────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A12),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  if (!kIsWeb && !Platform.isWindows) {
    await _initNotifications();
  }

  runApp(const AlphaTrackApp());
}

class AlphaTrackApp extends StatelessWidget {
  const AlphaTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroTehComert',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          surface: const Color(0xFF111118),
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

// ─── Android WebView screen ──────────────────────────────────────────────────
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _webViewReady = false;
  bool _hasError = false;
  String _loadUrl = _baseUrl;
  StreamSubscription<Uri>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks().then((_) => _initWebView());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      if (_pendingNotifUrl != null) {
        _controller.loadRequest(
            Uri.parse('$_baseUrl$_pendingNotifUrl'));
        _pendingNotifUrl = null;
      }
    });
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  // ── Deep links ─────────────────────────────────────────────────────────────
  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null && initial.host == 'service.agrotehcomert.com') {
        final q = initial.query.isNotEmpty ? '?${initial.query}' : '';
        _loadUrl = '$_baseUrl${initial.path}$q';
      }
    } catch (e) {
      debugPrint('Deep link init error: $e');
    }
    _deepLinkSub = appLinks.uriLinkStream.listen((uri) {
      if (uri.host == 'service.agrotehcomert.com') {
        final q = uri.query.isNotEmpty ? '?${uri.query}' : '';
        _controller.loadRequest(Uri.parse('$_baseUrl${uri.path}$q'));
      }
    });
  }

  // ── WebView init ───────────────────────────────────────────────────────────
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'AlphaTrackBridge',
        onMessageReceived: (msg) => _handleBridgeMessage(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) async {
            final url = req.url;
            if (url.startsWith('tel:') ||
                url.startsWith('mailto:') ||
                url.startsWith('sms:')) {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) await launchUrl(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            setState(() => _hasError = false);
            _injectBridge();
          },
          onPageFinished: (_) {
            setState(() => _webViewReady = true);
            _injectBridge();
          },
          onWebResourceError: (err) {
            debugPrint('WebView error: ${err.description}');
            if (err.isForMainFrame ?? true) {
              setState(() => _hasError = true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_loadUrl));
  }

  // ── JS Bridge injection ────────────────────────────────────────────────────
  void _injectBridge() {
    _controller.runJavaScript(r'''
(function() {
  if (window.__atBridge) return;
  window.__atBridge = true;

  function _send(payload) {
    try { AlphaTrackBridge.postMessage(JSON.stringify(payload)); } catch(e) {}
  }

  /* Override Notification → forward to Flutter */
  var _Orig = window.Notification;
  function AlphaNtf(title, opts) {
    _send({ type:'push', title: title||'AlphaTrack',
            body: (opts&&opts.body)||'',
            url:  (opts&&opts.data&&opts.data.url)||'/tasks' });
    try { if (_Orig) return new _Orig(title, opts); } catch(e) {}
  }
  AlphaNtf.permission = 'granted';
  AlphaNtf.requestPermission = function() { return Promise.resolve('granted'); };
  try { Object.defineProperty(window,'Notification',{value:AlphaNtf,configurable:true}); }
  catch(e) { try { window.Notification = AlphaNtf; } catch(e2) {} }

  /* Listen for service-worker push messages */
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', function(e) {
      if (e.data && e.data.type === 'push') _send(e.data);
    });
  }

  /* Mock serviceWorker if missing */
  if (!('serviceWorker' in navigator) || !navigator.serviceWorker) {
    try {
      Object.defineProperty(navigator, 'serviceWorker', { configurable:true, value: {
        ready: Promise.resolve({ pushManager: {
          subscribe: function() { return Promise.resolve({endpoint:'flutter-native',toJSON:function(){return{};}}); },
          getSubscription: function() { return Promise.resolve(null); },
          permissionState: function() { return Promise.resolve('granted'); }
        }, showNotification: function(t,o) {
          _send({type:'push',title:t||'AlphaTrack',body:(o&&o.body)||'',url:(o&&o.data&&o.data.url)||'/tasks'});
        }}),
        register: function() { return Promise.resolve({}); },
        getRegistrations: function() { return Promise.resolve([]); }
      }});
    } catch(e) {}
  }

  /* Send session token to Flutter */
  (function trySession() {
    var m = document.cookie.match(/alphatrack_session=([^;]+)/);
    if (m) { _send({type:'session', token: m[1]}); }
    else { setTimeout(trySession, 3000); }
  })();
})();
    ''');
  }

  // ── Bridge message handler ─────────────────────────────────────────────────
  void _handleBridgeMessage(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == 'push') {
        _showNativeNotification(
          data['title'] as String? ?? 'AlphaTrack',
          data['body'] as String? ?? '',
          data['url'] as String? ?? '/tasks',
        );
      } else if (type == 'session') {
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          SharedPreferences.getInstance()
              .then((p) => p.setString('at_session', token));
        }
      }
    } catch (e) {
      debugPrint('Bridge error: $e');
    }
  }

  // ── Updates ────────────────────────────────────────────────────────────────
  Future<void> _checkForUpdates() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final cur = info.version;
      final res = await http.get(
        Uri.parse(
            'https://api.github.com/repos/$_githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final latest =
            (d['tag_name'] as String? ?? '').replaceFirst('v', '');
        final url = d['html_url'] as String? ??
            'https://github.com/$_githubRepo/releases/latest';
        if (latest.isNotEmpty && _isNewerVersion(latest, cur)) {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getString('dismissed_update') != latest && mounted) {
            _showUpdateDialog(latest, url);
          }
        }
      }
    } catch (e) {
      debugPrint('Update check: $e');
    }
  }

  bool _isNewerVersion(String latest, String current) {
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final n = l.length > c.length ? l.length : c.length;
    while (l.length < n) l.add(0);
    while (c.length < n) c.add(0);
    for (var i = 0; i < n; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  void _showUpdateDialog(String version, String downloadUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111118),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0x296366F1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.system_update_rounded,
                  color: Color(0xFF6366F1), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Обновление',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          'Версия $version готова к установке.',
          style: const TextStyle(
              color: Color(0xFFB0B0C0), height: 1.5, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.setString('dismissed_update', version);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Позже',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Обновить',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  Widget _buildSplash() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D0D16), Color(0xFF0A0A12)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x666366F1),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Text('α',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        height: 1.1)),
              ),
            ),
            const SizedBox(height: 28),
            const Text('AgroTehComert',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3)),
            const SizedBox(height: 6),
            const Text('Сервис управления',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
            const SizedBox(height: 44),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  backgroundColor: Color(0xFF1F1F30),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Container(
      color: const Color(0xFF0A0A12),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0x19EF4444),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  color: Color(0xFFEF4444), size: 36),
            ),
            const SizedBox(height: 20),
            const Text('Нет подключения',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Проверьте интернет-соединение',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _webViewReady = false;
                });
                _controller.loadRequest(Uri.parse(_loadUrl));
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
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
            : Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (!_webViewReady)
                    AnimatedOpacity(
                      opacity: _webViewReady ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 400),
                      child: _buildSplash(),
                    ),
                ],
              ),
      ),
    );
  }
}
