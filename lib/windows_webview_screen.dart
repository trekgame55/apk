import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_windows/webview_windows.dart';

const String _baseUrl = 'https://service.agrotehcomert.com';

class WindowsWebViewScreen extends StatefulWidget {
  const WindowsWebViewScreen({super.key});

  @override
  State<WindowsWebViewScreen> createState() => _WindowsWebViewScreenState();
}

class _WindowsWebViewScreenState extends State<WindowsWebViewScreen> {
  final WebviewController _controller = WebviewController();
  bool _initialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  static const String _githubRepo = 'trekgame55/apk';

  @override
  void initState() {
    super.initState();
    _initWebView();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);

      // Инжектим notification mock при каждой загрузке страницы
      _controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) {
          _injectNotificationMock();
        }
      });

      await _controller.loadUrl(_baseUrl);

      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (e) {
      debugPrint('WebView2 init error: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
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
        final downloadUrl = data['html_url'] as String? ??
            'https://github.com/$_githubRepo/releases/latest';
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

  Future<void> _downloadAndRunInstaller() async {
    BuildContext? dialogContext;
    try {
      // 1. Получаем инфо о последнем релизе
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (response.statusCode != 200) {
        throw Exception('GitHub API вернул ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final assets = (data['assets'] as List<dynamic>?) ?? const [];

      // 2. Ищем .exe установщик
      String? installerUrl;
      String? installerName;
      int? totalSize;
      for (final a in assets) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.exe') && name.contains('setup')) {
          installerUrl = a['browser_download_url'] as String?;
          installerName = a['name'] as String?;
          totalSize = a['size'] as int?;
          break;
        }
      }
      if (installerUrl == null || installerName == null) {
        throw Exception('Установщик не найден в релизе');
      }

      // 3. Показываем прогресс
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogContext = ctx;
          return const AlertDialog(
            backgroundColor: Color(0xFF1A1A22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            content: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF7C5CFC)),
                  SizedBox(width: 20),
                  Flexible(
                    child: Text(
                      'Скачивание обновления...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      // 4. Скачиваем установщик в временную папку
      final tempDir = Directory.systemTemp;
      final installerPath = '${tempDir.path}\\$installerName';
      final installerFile = File(installerPath);

      final dl = await http.get(Uri.parse(installerUrl));
      if (dl.statusCode != 200) {
        throw Exception('Ошибка загрузки (Код ${dl.statusCode})');
      }
      if (totalSize != null && dl.bodyBytes.length < totalSize ~/ 2) {
        throw Exception('Скачан неполный файл');
      }
      await installerFile.writeAsBytes(dl.bodyBytes, flush: true);

      // 5. Запускаем установщик в фоновом режиме
      await Process.start(
        installerPath,
        const [
          '/SILENT',
          '/CLOSEAPPLICATIONS',
          '/RESTARTAPPLICATIONS',
          '/NORESTART',
        ],
        mode: ProcessStartMode.detached,
      );

      // 6. Закрываем приложение — установщик сам его перезапустит
      await Future.delayed(const Duration(seconds: 1));
      exit(0);
    } catch (e) {
      debugPrint('Installer error: $e');
      if (dialogContext != null && mounted) {
        Navigator.of(dialogContext!, rootNavigator: true).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF7C5CFC),
          content: Text('Ошибка обновления: $e'),
        ),
      );
    }
  }

  void _injectNotificationMock() {
    _controller.executeScript('''
      (function() {
        if (window._flutterPushInjected) return;
        window._flutterPushInjected = true;
        try {
          if (typeof Notification === "undefined") {
            window.Notification = function Notification() {};
            Object.defineProperty(window.Notification, "permission", { get: function() { return "granted"; }});
            window.Notification.requestPermission = function() { return Promise.resolve("granted"); };
          } else {
            Object.defineProperty(Notification, "permission", { get: function() { return "granted"; }, configurable: true });
            Notification.requestPermission = function() { return Promise.resolve("granted"); };
          }
        } catch(e) {}
        try {
          if (!("serviceWorker" in navigator) || navigator.serviceWorker === undefined) {
            Object.defineProperty(navigator, "serviceWorker", {
              value: {
                ready: Promise.resolve({
                  pushManager: {
                    subscribe: function() { return Promise.resolve({endpoint: "flutter-fcm", toJSON: function() { return {}; }}); },
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
          }
        } catch(e) {}
      })();
    ''');
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
              await _downloadAndRunInstaller();
            },
            icon: const Icon(Icons.download),
            label: const Text('Обновить'),
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    final isWebView2Missing = _errorMessage.toLowerCase().contains('webview2') ||
        _errorMessage.contains('runtime');
    return Container(
      color: const Color(0xFF0A0A12),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              isWebView2Missing
                  ? 'Требуется WebView2 Runtime'
                  : 'Ошибка загрузки',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              isWebView2Missing
                  ? 'Установите Microsoft Edge WebView2 Runtime для работы приложения'
                  : _errorMessage,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (isWebView2Missing)
              ElevatedButton.icon(
                onPressed: () async {
                  await Process.run(
                    'cmd',
                    ['/c', 'start', '', 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'],
                    runInShell: false,
                  );
                },
                icon: const Icon(Icons.download),
                label: const Text('Скачать WebView2'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C5CFC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _errorMessage = '';
                  });
                  _initWebView();
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

  Widget _buildWebViewWithScroll() {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final dy = event.scrollDelta.dy;
          final dx = event.scrollDelta.dx;
          _controller.executeScript('''
            (function() {
              var dy = $dy;
              var dx = $dx;
              var el = document.activeElement;
              while (el && el !== document.body) {
                var style = window.getComputedStyle(el);
                var oy = style.overflowY;
                if ((oy === "auto" || oy === "scroll") && el.scrollHeight > el.clientHeight) {
                  el.scrollTop += dy;
                  return;
                }
                el = el.parentElement;
              }
              var target = document.scrollingElement || document.documentElement || document.body;
              target.scrollBy({ top: dy, left: dx, behavior: "auto" });
            })();
          ''');
        }
      },
      child: Webview(
        _controller,
        permissionRequested: (url, kind, isUserInitiated) async {
          return WebviewPermissionDecision.allow;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: _hasError
          ? _buildErrorScreen()
          : _initialized
              ? _buildWebViewWithScroll()
              : _buildSplash(),
    );
  }
}
