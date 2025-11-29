import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ResultsPage extends StatelessWidget {
  final String baseUrl;
  final String? timestamp;
  final Map<String, dynamic>? result;

  const ResultsPage({Key? key, required this.baseUrl, this.timestamp, this.result}) : super(key: key);

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      // On web, open in new tab
      if (kIsWeb) {
        await launchUrl(uri, webOnlyWindowName: '_blank');
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      // ignore errors here; caller can handle if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = result?['statistics'] ?? {};
    final recommendations = (result?['recommendations'] as List<dynamic>?) ?? [];

    final ButtonStyle niceStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 4,
    );

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analysis Results', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(child: Text('Total Records: ${stats['total_records'] ?? '-'}')),
                  Expanded(child: Text('Anomalies: ${stats['anomaly_count'] ?? '-'}')),
                  Expanded(child: Text('Percentage: ${stats['anomaly_percentage'] ?? '-'}%')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Mitigation Recommendations', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var r in recommendations)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Text(r.toString()),
              ),
            ),
          const SizedBox(height: 12),
          if (timestamp != null)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  style: niceStyle,
                  onPressed: () {
                    final url = '${baseUrl}/download/$timestamp';
                    _openUrl(url);
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download Anomaly CSV'),
                ),
                ElevatedButton.icon(
                  style: niceStyle,
                  onPressed: () async {
                    // Open both visualizations in new tabs/windows if available
                    final scatter = '${baseUrl}/visualization/$timestamp/scatter';
                    final dist = '${baseUrl}/visualization/$timestamp/dist';
                    await _openUrl(scatter);
                    // small delay to ensure separate tabs open on web
                    await Future.delayed(const Duration(milliseconds: 120));
                    await _openUrl(dist);
                  },
                  icon: const Icon(Icons.show_chart_rounded),
                  label: const Text('Open Visualizations'),
                ),
                if (result?['capture_filename'] != null)
                  Chip(label: Text('Source: ${result?['capture_filename']}'))
              ],
            )
        ],
      ),
    );
  }
}
