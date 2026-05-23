import 'dart:convert';
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
    statusBarColor: Colors.transparent,
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
  bool _isLoading = true;
  String? _sessionToken;

  @override
  void initState() {
    super.initState();
    _initWebView();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setupFCM());
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
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
          onPageStarted: (url) => setState(() => _isLoading = true),
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            _requestSessionFromSite();
            _requestWebNotificationPermission();
          },
          onWebResourceError: (error) =>
              debugPrint('WebView error: ${error.description}'),
        ),
      )
      ..loadRequest(Uri.parse(_baseUrl));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
              ),
          ],
        ),
      ),
    );
  }
}
