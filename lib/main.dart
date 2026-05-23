import 'dart:convert';
import 'dart:io' show Platform, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _baseUrl = 'https://service.agrotehcomert.com';
const String _apiBase = 'https://service.agrotehcomert.com/api';

// Обработчик фоновых уведомлений
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint("Firebase init error: $e");
    }
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF1B5E20),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const WebViewScreen(),
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
  String? _sessionToken;

  static const String _currentVersion = '1.0.0';
  static const String _githubRepo = 'trekgame55/apk';

  @override
  void initState() {
    super.initState();
    _initWebView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        _setupFCM();
      }
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
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (msg) {
          _sessionToken = msg.message;
          debugPrint("Session token received from site");
          _registerFcmToken();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _hasError = false);
            _injectPushSupport();
          },
          onPageFinished: (url) {
            setState(() => _webViewReady = true);
            _requestSessionFromSite();
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
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestTag = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
        final downloadUrl = data['html_url'] as String? ?? 'https://github.com/$_githubRepo/releases/latest';
        if (latestTag.isNotEmpty && latestTag != _currentVersion) {
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

  void _showUpdateDialog(String version, String downloadUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Color(0xFF4CAF50), size: 28),
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
              if (!kIsWeb && Platform.isWindows) {
                await Process.run('cmd', ['/c', 'start', '', downloadUrl], runInShell: false);
              } else {
                _controller.loadRequest(Uri.parse(downloadUrl));
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('Скачать'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _requestSessionFromSite() {
    _controller.runJavaScript('''
      (function() {
        var token = null;
        // Пробуем localStorage
        try { token = localStorage.getItem("session_token") || localStorage.getItem("token"); } catch(e) {}
        // Пробуем cookies
        if (!token) {
          var cookies = document.cookie.split(";");
          for (var i = 0; i < cookies.length; i++) {
            var pair = cookies[i].trim().split("=");
            if (pair[0] === "session_token" || pair[0] === "token") {
              token = pair[1];
              break;
            }
          }
        }
        if (token && typeof FlutterBridge !== "undefined") {
          FlutterBridge.postMessage(token);
        }
      })();
    ''');
  }

  Future<void> _setupFCM() async {
    try {
      if (!mounted) return;

      final shouldRequest = await _showNotificationPermissionDialog();
      if (!shouldRequest || !mounted) return;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint("Notification auth: ${settings.authorizationStatus}");

      messaging.onTokenRefresh.listen((newToken) {
        _registerFcmToken(token: newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null && mounted) {
          _showInAppNotification(message);
        }
      });

      await _registerFcmToken();
    } catch (e) {
      debugPrint("FCM setup error: $e");
    }
  }

  Future<bool> _showNotificationPermissionDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Color(0xFF4CAF50), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Уведомления',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Разрешите уведомления, чтобы получать важные сообщения о заказах, новых предложениях и обновлениях.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Позже', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Разрешить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showInAppNotification(RemoteMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.notification!.title ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (message.notification!.body != null)
              Text(
                message.notification!.body!,
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2E7D32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _registerFcmToken({String? token}) async {
    if (kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final fcmToken = token ?? await messaging.getToken();
      if (fcmToken == null) return;

      debugPrint("FCM Token: $fcmToken");

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', fcmToken);

      final sessionToken = _sessionToken ?? prefs.getString('session_token');
      if (sessionToken == null || sessionToken.isEmpty) {
        debugPrint("No session token — FCM will be registered after login");
        return;
      }

      final response = await http.post(
        Uri.parse('$_apiBase/fcm/register'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'token=$sessionToken',
        },
        body: jsonEncode({'token': fcmToken}),
      );

      if (response.statusCode == 200) {
        debugPrint("FCM token registered on server");
      } else {
        debugPrint("FCM registration error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("FCM registration error: $e");
    }
  }

  Widget _buildSplash() {
    return Container(
      color: const Color(0xFF0D1A0D),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF4CAF50), strokeWidth: 3),
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
      color: const Color(0xFF0D0D0D),
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
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
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
      backgroundColor: const Color(0xFF0D1A0D),
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
