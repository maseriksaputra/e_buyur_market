import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../ml/hybrid_ai_service.dart';

class MlDiagnosticsPage extends StatefulWidget {
  const MlDiagnosticsPage({super.key});
  @override
  State<MlDiagnosticsPage> createState() => _MlDiagnosticsPageState();
}

class _MlDiagnosticsPageState extends State<MlDiagnosticsPage> {
  String? _report;
  bool _busy = false;
  HybridAI? _ai;

  Future<void> _initAndRun() async {
    setState(() => _busy = true);
    try {
      _ai ??= await HybridAI.load();
      final res = await _ai!.runSelfTest();
      setState(() => _report = const JsonEncoder.withIndent('  ').convert(res));
      // juga ke logcat/console
      // ignore: avoid_print
      print('[ML-SELF-TEST] $res');
    } catch (e, st) {
      setState(() => _report = 'ERROR: $e\n$st');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void initState() { super.initState(); _initAndRun(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ML Diagnostics')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _busy ? null : _initAndRun,
                  icon: const Icon(Icons.replay),
                  label: const Text('Jalankan Ulang'),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Uji model dengan gambar statis di assets/test/')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(_report ?? 'Menjalankan self-test...'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
