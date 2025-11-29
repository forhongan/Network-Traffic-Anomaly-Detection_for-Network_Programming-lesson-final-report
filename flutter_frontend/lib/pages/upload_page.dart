import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

class UploadPage extends StatefulWidget {
  final String baseUrl;
  final void Function(String, Map<String, dynamic>)? onComplete;

  const UploadPage({Key? key, required this.baseUrl, this.onComplete}) : super(key: key);

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  bool _loading = false;
  String? _status;

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;

    setState(() {
      _loading = true;
      _status = null;
    });

    try {
      final uri = Uri.parse('${widget.baseUrl}/analyze');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', path));
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      final jsonResp = jsonDecode(resp.body) as Map<String, dynamic>;
      if (jsonResp['success'] == true) {
        setState(() => _status = '分析成功');
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 4,
    );

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Upload Network Traffic CSV', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: nice,
            onPressed: _loading ? null : _pickAndUpload,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.attach_file),
            label: Text(_loading ? 'Uploading...' : 'Pick & Analyze CSV'),
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
