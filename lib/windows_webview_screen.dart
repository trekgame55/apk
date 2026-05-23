import 'dart:convert';
import 'dart:io' show Platform, Process;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  static const String _currentVersion = '1.0.0';
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
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestTag = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
        final downloadUrl = data['html_url'] as String? ??
            'https://github.com/$_githubRepo/releases/latest';
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
              if (Platform.isWindows) {
                await Process.run('cmd', ['/c', 'start', '', downloadUrl],
                    runInShell: false);
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
          _controller.executeScript(
            'window.scrollBy({top: $dy, left: 0, behavior: "auto"});',
          );
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
