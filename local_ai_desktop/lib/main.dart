import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const LocalAiDesktopApp());
}

const _accent = Color(0xFF0F766E);
const _bg = Color(0xFFF5F7F8);
const _panel = Color(0xFFFFFFFF);
const _line = Color(0xFFD8E0E4);
const _text = Color(0xFF172026);
const _muted = Color(0xFF5C6A72);
const _soft = Color(0xFFEAF4F1);

class LocalAiDesktopApp extends StatelessWidget {
  const LocalAiDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Local Coding AI',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: _text, height: 1.35),
          bodyLarge: TextStyle(color: _text, height: 1.35),
        ),
      ),
      home: const LocalAiHome(),
    );
  }
}

class ChatMessage {
  const ChatMessage(this.role, this.content);

  final String role;
  final String content;
}

class LocalAiHome extends StatefulWidget {
  const LocalAiHome({super.key});

  @override
  State<LocalAiHome> createState() => _LocalAiHomeState();
}

class _LocalAiHomeState extends State<LocalAiHome> {
  final _workspaceController = TextEditingController(text: _guessWorkspace());
  final _activeModelController = TextEditingController(
    text: '${_guessWorkspace()}/models/Qwen2.5-Coder-7B-Instruct-4bit',
  );
  final _downloadRepoController = TextEditingController(
    text: 'mlx-community/Qwen2.5-Coder-7B-Instruct-4bit',
  );
  final _downloadFolderController = TextEditingController(
    text: 'models/Qwen2.5-Coder-7B-Instruct-4bit',
  );
  final _promptController = TextEditingController();
  final _commitController = TextEditingController();
  final _answerScroll = ScrollController();
  final _logScroll = ScrollController();

  final List<ChatMessage> _messages = const [
    ChatMessage(
      'assistant',
      'Pilih working folder, pastikan server lokal berjalan, lalu tulis pertanyaan coding di bawah.',
    ),
  ].toList();
  final List<String> _logs = <String>[];

  Process? _serverProcess;
  Process? _downloadProcess;
  var _selectedPage = 0;
  var _serverRunning = false;
  var _startingServer = false;
  var _downloading = false;
  var _sending = false;
  var _gitBusy = false;
  var _gitOutput = 'Git output akan muncul di sini.';
  var _maxNewTokens = 700.0;
  var _maxLength = 2048.0;
  final _port = 7860;

  String get _workspace => _workspaceController.text.trim();

  String get _pythonPath {
    final localPython = File('$_workspace/.venv/bin/python');
    return localPython.existsSync() ? localPython.path : 'python3';
  }

  @override
  void dispose() {
    _serverProcess?.kill();
    _downloadProcess?.kill();
    _workspaceController.dispose();
    _activeModelController.dispose();
    _downloadRepoController.dispose();
    _downloadFolderController.dispose();
    _promptController.dispose();
    _commitController.dispose();
    _answerScroll.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  void _log(String line) {
    if (!mounted) return;
    setState(() {
      final stamp = DateTime.now().toIso8601String().substring(11, 19);
      _logs.add('[$stamp] $line');
      if (_logs.length > 1200) {
        _logs.removeRange(0, _logs.length - 1200);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startServer() async {
    if (_serverRunning || _startingServer) return;
    final script = File('$_workspace/airllm_ui.py');
    if (!script.existsSync()) {
      _log('airllm_ui.py tidak ditemukan di working folder.');
      return;
    }

    setState(() => _startingServer = true);
    _log('Menjalankan server lokal di http://127.0.0.1:$_port');
    try {
      final process = await Process.start(_pythonPath, [
        'airllm_ui.py',
        '127.0.0.1',
        '$_port',
      ], workingDirectory: _workspace);
      _serverProcess = process;
      _serverRunning = true;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_log);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _log('ERR $line'));
      unawaited(
        process.exitCode.then((code) {
          if (!mounted) return;
          setState(() {
            _serverRunning = false;
            _serverProcess = null;
          });
          _log('Server berhenti dengan kode $code.');
        }),
      );
    } catch (error) {
      _log('Gagal menjalankan server: $error');
    } finally {
      if (mounted) setState(() => _startingServer = false);
    }
  }

  void _stopServer() {
    _serverProcess?.kill();
    _serverProcess = null;
    setState(() => _serverRunning = false);
    _log('Perintah stop server dikirim.');
  }

  Future<bool> _waitForHealth() async {
    for (var i = 0; i < 25; i++) {
      try {
        final client = HttpClient();
        final request = await client
            .getUrl(Uri.parse('http://127.0.0.1:$_port/health'))
            .timeout(const Duration(seconds: 2));
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        client.close();
        if (response.statusCode == 200) return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _messages.add(ChatMessage('user', prompt));
      _promptController.clear();
    });
    _scrollAnswer();

    if (!_serverRunning) {
      await _startServer();
    }
    final healthy = await _waitForHealth();
    if (!healthy) {
      setState(() {
        _messages.add(
          const ChatMessage(
            'assistant',
            'Server lokal belum merespons. Cek log di Settings lalu jalankan ulang server.',
          ),
        );
        _sending = false;
      });
      _scrollAnswer();
      return;
    }

    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$_port/ask'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'prompt': prompt,
          'model_id': _activeModelController.text.trim(),
          'backend': 'mlx_lm',
          'max_new_tokens': _maxNewTokens.round(),
          'max_length': _maxLength.round(),
        }),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final answer = response.statusCode == 200
          ? (data['answer']?.toString() ?? '(Jawaban kosong)')
          : (data['error']?.toString() ?? body);
      setState(() {
        _messages.add(ChatMessage('assistant', answer));
      });
    } catch (error) {
      setState(() {
        _messages.add(
          ChatMessage('assistant', 'Gagal mengirim pertanyaan: $error'),
        );
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollAnswer();
    }
  }

  void _scrollAnswer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_answerScroll.hasClients) {
        _answerScroll.animateTo(
          _answerScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _downloadModel() async {
    if (_downloading) return;
    final oldModel = _activeModelController.text.trim();
    final repo = _downloadRepoController.text.trim();
    final folderInput = _downloadFolderController.text.trim();
    if (repo.isEmpty || folderInput.isEmpty) {
      _log('Repo model dan folder tujuan wajib diisi.');
      return;
    }

    final target = folderInput.startsWith('/')
        ? folderInput
        : '$_workspace/$folderInput';

    setState(() => _downloading = true);
    _log('Mulai download model $repo');
    _log('Target: $target');
    final script = '''
import sys
from huggingface_hub import snapshot_download
repo, target = sys.argv[1], sys.argv[2]
path = snapshot_download(repo_id=repo, local_dir=target)
print(path)
''';

    try {
      final process = await Process.start(_pythonPath, [
        '-c',
        script,
        repo,
        target,
      ], workingDirectory: _workspace);
      _downloadProcess = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_log);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _log('DL $line'));
      final code = await process.exitCode;
      if (!mounted) return;
      if (code == 0 && File('$target/model.safetensors').existsSync()) {
        setState(() {
          _activeModelController.text = target;
        });
        _log('Download selesai. Model aktif diganti ke $target');
      } else {
        setState(() {
          _activeModelController.text = oldModel;
        });
        _log(
          'Download gagal atau model tidak lengkap. Model aktif tetap: $oldModel',
        );
      }
    } catch (error) {
      setState(() {
        _activeModelController.text = oldModel;
      });
      _log('Download gagal: $error');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProcess = null;
        });
      }
    }
  }

  void _cancelDownload() {
    _downloadProcess?.kill();
    _downloadProcess = null;
    setState(() => _downloading = false);
    _log('Download dibatalkan. Model aktif tidak diubah.');
  }

  Future<void> _runGit(String label, List<String> args) async {
    if (_gitBusy) return;
    setState(() {
      _gitBusy = true;
      _gitOutput = 'Menjalankan $label...';
    });
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: _workspace,
      );
      final out = '${result.stdout}${result.stderr}'.trim();
      setState(() {
        _gitOutput = out.isEmpty ? '$label selesai.' : out;
      });
    } catch (error) {
      setState(() {
        _gitOutput = 'Gagal menjalankan $label: $error';
      });
    } finally {
      if (mounted) setState(() => _gitBusy = false);
    }
  }

  Future<void> _commit() async {
    final message = _commitController.text.trim();
    if (message.isEmpty) {
      setState(() => _gitOutput = 'Isi pesan commit dulu.');
      return;
    }
    await _runGit('commit', ['commit', '-m', message]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _NavRail(
            selected: _selectedPage,
            onSelected: (value) => setState(() => _selectedPage = value),
            serverRunning: _serverRunning,
          ),
          Expanded(
            child: _selectedPage == 0 ? _buildChatPage() : _buildSettingsPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        children: [
          _TopBar(
            title: 'Coding Assistant',
            subtitle: _activeModelController.text.trim(),
            status: _serverRunning ? 'Server aktif' : 'Server mati',
            statusColor: _serverRunning ? _accent : Colors.orange.shade700,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildConversation()),
                const SizedBox(width: 14),
                SizedBox(width: 310, child: _buildGitPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversation() {
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: _LabeledField(
                    label: 'Working folder',
                    child: TextField(
                      controller: _workspaceController,
                      decoration: _inputDecoration('Folder proyek'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Jalankan server',
                  onPressed: _serverRunning ? null : _startServer,
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Stop server',
                  onPressed: _serverRunning ? _stopServer : null,
                  icon: const Icon(Icons.stop_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          Expanded(
            child: ListView.separated(
              controller: _answerScroll,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) =>
                  _MessageView(message: _messages[index]),
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemCount: _messages.length,
            ),
          ),
          const Divider(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    minLines: 2,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: _inputDecoration(
                      'Tulis pertanyaan atau tugas coding...',
                    ),
                    onSubmitted: (_) => _sendPrompt(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _sendPrompt,
                    icon: Icon(
                      _sending
                          ? Icons.hourglass_top_rounded
                          : Icons.send_rounded,
                    ),
                    label: Text(_sending ? 'Kirim...' : 'Kirim'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGitPanel() {
    return Container(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Git Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionChipButton(
                  label: 'Status',
                  icon: Icons.fact_check_rounded,
                  onPressed: () => _runGit('status', ['status', '--short']),
                ),
                _ActionChipButton(
                  label: 'Diff',
                  icon: Icons.difference_rounded,
                  onPressed: () => _runGit('diff', ['diff', '--stat']),
                ),
                _ActionChipButton(
                  label: 'Branch',
                  icon: Icons.account_tree_rounded,
                  onPressed: () =>
                      _runGit('branch', ['branch', '--show-current']),
                ),
                _ActionChipButton(
                  label: 'Stage All',
                  icon: Icons.add_task_rounded,
                  onPressed: () => _runGit('stage all', ['add', '-A']),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _commitController,
              decoration: _inputDecoration('Pesan commit'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _gitBusy ? null : _commit,
              icon: const Icon(Icons.commit_rounded),
              label: const Text('Commit'),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _gitOutput,
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontFamily: 'Menlo',
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        children: [
          _TopBar(
            title: 'Settings',
            subtitle: 'Model, server, dan log proses lokal',
            status: _downloading
                ? 'Download berjalan'
                : (_serverRunning ? 'Server aktif' : 'Siap'),
            statusColor: _downloading
                ? Colors.blue.shade700
                : (_serverRunning ? _accent : _muted),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildModelSettings()),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: _buildLogs()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSettings() {
    return Container(
      decoration: _panelDecoration(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Model Settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _LabeledField(
            label: 'Working folder',
            child: TextField(
              controller: _workspaceController,
              decoration: _inputDecoration('/Users/duidev/htdocs/airllm'),
            ),
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: 'Model aktif',
            child: TextField(
              controller: _activeModelController,
              decoration: _inputDecoration('Path lokal model MLX'),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MetricBox(
                  label: 'Backend',
                  value: 'MLX-LM',
                  icon: Icons.memory_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricBox(
                  label: 'Port',
                  value: '$_port',
                  icon: Icons.settings_ethernet_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _serverRunning ? null : _startServer,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _startingServer
                        ? 'Menjalankan...'
                        : 'Jalankan airllm_ui.py',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _serverRunning ? _stopServer : null,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop Server'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: _line),
          const SizedBox(height: 16),
          const Text(
            'Download Model',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: 'Hugging Face repo',
            child: TextField(
              controller: _downloadRepoController,
              decoration: _inputDecoration(
                'mlx-community/Qwen2.5-Coder-7B-Instruct-4bit',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: 'Folder tujuan',
            child: TextField(
              controller: _downloadFolderController,
              decoration: _inputDecoration('models/Nama-Model'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _downloading ? null : _downloadModel,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download dan Switch'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? _cancelDownload : null,
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('Batalkan'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(color: _line),
          const SizedBox(height: 16),
          const Text(
            'Generation',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _SliderField(
            label: 'Token jawaban',
            value: _maxNewTokens,
            min: 64,
            max: 2048,
            divisions: 31,
            onChanged: (value) => setState(() => _maxNewTokens = value),
          ),
          _SliderField(
            label: 'Panjang input',
            value: _maxLength,
            min: 512,
            max: 8192,
            divisions: 30,
            onChanged: (value) => setState(() => _maxLength = value),
          ),
        ],
      ),
    );
  }

  Widget _buildLogs() {
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Process Log',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Bersihkan log',
                  onPressed: () => setState(_logs.clear),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              child: ListView.builder(
                controller: _logScroll,
                padding: const EdgeInsets.all(12),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return SelectableText(
                    _logs[index],
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontFamily: 'Menlo',
                      fontSize: 12,
                      height: 1.38,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.selected,
    required this.onSelected,
    required this.serverRunning,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final bool serverRunning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      color: const Color(0xFFE8EEF0),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.terminal_rounded, color: Colors.white),
            ),
            const SizedBox(height: 24),
            _NavButton(
              selected: selected == 0,
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Chat',
              onTap: () => onSelected(0),
            ),
            const SizedBox(height: 8),
            _NavButton(
              selected: selected == 1,
              icon: Icons.tune_rounded,
              label: 'Setting',
              onTap: () => onSelected(1),
            ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: serverRunning ? _accent : Colors.orange.shade700,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: selected ? _panel : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? _line : Colors.transparent),
          ),
          child: Icon(icon, color: selected ? _accent : _muted),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
  });

  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _panel,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(status, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFFE7EEF7) : _soft,
            border: Border.all(
              color: isUser ? const Color(0xFFC9D8EA) : const Color(0xFFCBE5DF),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            message.content,
            style: TextStyle(
              fontFamily: _looksLikeCode(message.content) ? 'Menlo' : null,
              fontSize: _looksLikeCode(message.content) ? 13 : 14,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _line),
      ),
      backgroundColor: _panel,
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _soft,
        border: Border.all(color: const Color(0xFFCBE5DF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              value.round().toString(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: _panel,
    border: Border.all(color: _line),
    borderRadius: BorderRadius.circular(8),
  );
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _accent, width: 1.4),
    ),
  );
}

bool _looksLikeCode(String value) {
  return value.contains('```') ||
      value.contains('class ') ||
      value.contains('function ') ||
      value.contains('import ') ||
      value.contains('=>') ||
      value.contains('{') && value.contains(';');
}

String _guessWorkspace() {
  const known = '/Users/duidev/htdocs/airllm';
  if (File('$known/airllm_ui.py').existsSync()) return known;
  var current = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (File('${current.path}/airllm_ui.py').existsSync()) return current.path;
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return known;
}
