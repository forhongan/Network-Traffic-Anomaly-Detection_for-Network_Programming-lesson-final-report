import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CapturePage extends StatefulWidget {
  final String baseUrl;
  final void Function(String, Map<String, dynamic>)? onComplete;

  const CapturePage({Key? key, required this.baseUrl, this.onComplete}) : super(key: key);

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final _interfaceController = TextEditingController();
  final _bpfController = TextEditingController(text: 'tcp or udp');
  int _duration = 30;
  bool _loading = false;
  String? _status;

  Future<void> _capture() async {
    if (_interfaceController.text.isEmpty) {
      setState(() => _status = 'Interface required');
      return;
    }
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/capture_and_analyze');
      final body = jsonEncode({
        'interface': _interfaceController.text,
        'duration': _duration,
        'bpf': _bpfController.text,
      });
      final res = await http.post(uri, body: body, headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 60));
      final jsonResp = jsonDecode(res.body) as Map<String, dynamic>;
      if (jsonResp['success'] == true) {
        setState(() => _status = 'Capture success');
        widget.onComplete?.call(jsonResp['timestamp'] ?? '', jsonResp);
      } else {
        setState(() => _status = 'Failed: ${jsonResp['error'] ?? 'unknown'}');
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle nice = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 4,
    );

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Capture Real Network Traffic', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          TextField(controller: _interfaceController, decoration: const InputDecoration(labelText: 'Interface')),
          const SizedBox(height: 8),
          TextField(controller: _bpfController, decoration: const InputDecoration(labelText: 'BPF Filter')),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Duration (s): '),
            Expanded(
              child: Slider(value: _duration.toDouble(), min: 5, max: 600, divisions: 59, label: '$_duration', onChanged: (v) => setState(() => _duration = v.toInt())),
            ),
            SizedBox(width: 48, child: Text('$_duration'))
          ]),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: nice,
            onPressed: _loading ? null : _capture,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
            label: Text(_loading ? 'Capturing...' : 'Capture & Analyze'),
          ),
          const SizedBox(height: 12),
          if (_status != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(8)),
              child: Text(_status!),
            ),
        ],
      ),
    );
  }
}
