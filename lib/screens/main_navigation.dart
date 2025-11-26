// lib/screens/main_navigation.dart
// (Note: The file path in your comment was lib/main_navigation.dart, but typically it's lib/screens/main_navigation.dart)

import 'package:flutter/material.dart';
import 'package:smart_resilience_app/screens/home_screen.dart';
import 'package:smart_resilience_app/screens/alert_screen.dart';
import 'package:smart_resilience_app/screens/location_history_screen.dart'; // Corrected import
import 'package:smart_resilience_app/screens/settings_screen.dart';

class MainNavigation extends StatefulWidget {
  // Add a GlobalKey for easy access from anywhere in the app
  static final GlobalKey<_MainNavigationState> navigatorKey =
      GlobalKey<_MainNavigationState>();

  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  // IMPORTANT: The _screens list needs to be built inside the build method
  // or initialized in initState if it depends on `this` (the state object).
  // Otherwise, the `onTabSelected` callback won't correctly reference `setSelectedIndex`.
  late List<Widget> _screens; // Declared as late to be initialized in initState

  @override
  void initState() {
    super.initState();
    // Initialize _screens here to use `this.setSelectedIndex`
    _screens = [
      HomeScreen(onTabSelected: (index) => setSelectedIndex(index)),
      const AlertScreen(),
      const LocationHistoryScreen(), // Corrected screen name
      const SettingsScreen(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Method to programmatically change the selected tab
  void setSelectedIndex(int index) {
    // Ensure the index is within bounds of your screens list
    if (index >= 0 && index < _screens.length) {
      setState(() {
        _selectedIndex = index;
      });
    } else {
      print('Warning: Attempted to set selected index out of bounds: $index');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: MainNavigation.navigatorKey, // Assign the key to the Scaffold
      body: IndexedStack(
        // Use IndexedStack for preserving state when switching tabs
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.green.shade700,
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Live Map'),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ), // This corresponds to index 2
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
