import 'package:flutter/material.dart';

class NavigationRailSidebar extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onSelected;

  const NavigationRailSidebar({Key? key, required this.selectedIndex, required this.onSelected}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Show NavigationRail on wide screens, Drawer on narrow screens
    final isWide = MediaQuery.of(context).size.width > 700;

    if (isWide) {
      return Container(
        width: 160,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          labelType: NavigationRailLabelType.selected,
          minWidth: 120,
          leading: Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Column(
              children: [
                CircleAvatar(radius: 28, backgroundColor: Theme.of(context).colorScheme.primary, child: const Icon(Icons.network_check, color: Colors.white)),
                const SizedBox(height: 8),
                Text('Net Anom', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.auto_graph), selectedIcon: Icon(Icons.auto_graph_outlined), label: Text('Generate')),
            NavigationRailDestination(icon: Icon(Icons.wifi_tethering), selectedIcon: Icon(Icons.wifi), label: Text('Capture')),
            NavigationRailDestination(icon: Icon(Icons.upload_file), selectedIcon: Icon(Icons.file_upload), label: Text('Upload')),
            NavigationRailDestination(icon: Icon(Icons.list), selectedIcon: Icon(Icons.list_alt), label: Text('Results')),
          ],
        ),
      );
    }

    // For narrow screens, return a compact column as a sidebar placeholder
    return Container(
      width: 80,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.auto_graph), onPressed: () => onSelected(0), color: selectedIndex==0?Theme.of(context).colorScheme.primary:null),
          IconButton(icon: const Icon(Icons.wifi_tethering), onPressed: () => onSelected(1), color: selectedIndex==1?Theme.of(context).colorScheme.primary:null),
          IconButton(icon: const Icon(Icons.upload_file), onPressed: () => onSelected(2), color: selectedIndex==2?Theme.of(context).colorScheme.primary:null),
          IconButton(icon: const Icon(Icons.list), onPressed: () => onSelected(3), color: selectedIndex==3?Theme.of(context).colorScheme.primary:null),
        ],
      ),
    );
  }
}
