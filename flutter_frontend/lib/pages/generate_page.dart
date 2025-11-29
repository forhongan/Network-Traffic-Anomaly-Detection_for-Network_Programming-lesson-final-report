import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GeneratePage extends StatefulWidget {
  final String baseUrl;
  final void Function(String, Map<String, dynamic>)? onComplete;

  const GeneratePage({Key? key, required this.baseUrl, this.onComplete}) : super(key: key);

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  DateTime? _startDate;
  int _duration = 24;
  bool _loading = false;
  String? _status;

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (time != null) {
        setState(() {
          _startDate = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
        });
      }
    }
  }

  Future<void> _generate() async {
    if (_startDate == null) return _pickStartDate();
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/generate_data');
      final body = jsonEncode({
        'start_date': _startDate!.toIso8601String(),
        'duration': _duration,
      });
      final res = await http.post(uri, body: body, headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 15));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['success'] == true) {
        setState(() {
          _status = '生成完成: ${json['filename']} (${json['records']} 条)';
        });
        widget.onComplete?.call(json['filename'], json);
      } else {
        setState(() {
          _status = '失败: ${json['error'] ?? 'unknown'}';
        });
      }
    } catch (e) {
      setState(() {
        _status = '请求失败: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
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
          Text('Generate Sample Data', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                style: nice,
                onPressed: _pickStartDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(_startDate == null ? 'Pick Start' : _startDate!.toString()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    const Text('Duration (hours): '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _duration.toDouble(),
                        min: 1,
                        max: 168,
                        divisions: 167,
                        label: '$_duration',
                        onChanged: (v) => setState(() => _duration = v.toInt()),
                      ),
                    ),
                    SizedBox(width: 48, child: Text('$_duration'))
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: nice,
            onPressed: _loading ? null : _generate,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
            label: Text(_loading ? 'Generating...' : 'Generate Sample Data'),
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
