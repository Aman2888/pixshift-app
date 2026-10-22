import 'package:flutter/material.dart';
import 'screens/about.dart';
import 'screens/categories.dart';
import 'screens/home.dart';
import 'screens/tools_hub.dart';
import 'theme.dart';

void main() => runApp(const PixShiftApp());

class PixShiftApp extends StatelessWidget {
  const PixShiftApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'PixShift', debugShowCheckedModeBanner: false, theme: buildTheme(), home: const Shell());
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [HomeScreen(onSeeAll: () => setState(() => tab = 2)), const CategoriesScreen(), const ToolsHub(), const AboutScreen()];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.category_outlined), selectedIcon: Icon(Icons.category), label: 'Categories'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'All tools'),
          NavigationDestination(icon: Icon(Icons.info_outline), selectedIcon: Icon(Icons.info), label: 'About'),
        ],
      ),
    );
  }
}