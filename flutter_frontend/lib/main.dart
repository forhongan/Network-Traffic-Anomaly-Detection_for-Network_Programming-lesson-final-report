import 'package:flutter/material.dart';
import 'pages/generate_page.dart';
import 'pages/capture_page.dart';
import 'pages/upload_page.dart';
import 'pages/results_page.dart';
import 'widgets/sidebar.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Backend base URL, can be edited here or exposed in UI later
  String baseUrl = 'http://localhost:5000';

  int _selectedIndex = 0;
  String? lastTimestamp;
  Map<String, dynamic>? lastResult;

  void navigateTo(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void updateLastResult(String timestamp, Map<String, dynamic> result) {
    setState(() {
      lastTimestamp = timestamp;
      lastResult = result;
      _selectedIndex = 3; // switch to results page
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      GeneratePage(baseUrl: baseUrl, onComplete: updateLastResult),
      CapturePage(baseUrl: baseUrl, onComplete: updateLastResult),
      UploadPage(baseUrl: baseUrl, onComplete: updateLastResult),
      ResultsPage(baseUrl: baseUrl, timestamp: lastTimestamp, result: lastResult),
    ];

    return MaterialApp(
      title: 'Network Traffic Anomaly - Frontend',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Row(
          children: [
            // Sidebar
            NavigationRailSidebar(
              selectedIndex: _selectedIndex,
              onSelected: navigateTo,
            ),
            const VerticalDivider(thickness: 1, width: 1),
            // Content
            Expanded(
              child: SafeArea(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: pages[_selectedIndex],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
