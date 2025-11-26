// main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Still needed for splash_screen to check auth
import 'firebase_options.dart';
import 'screens/splash_screen.dart'; // Your splash screen
import 'screens/main_navigation.dart'; // Your main app screen (home page)
import 'package:smart_resilience_app/services/notification_service.dart'; // Your notification service
import 'screens/guardian_login_page.dart'; // Your guardian login page
import 'screens/guardian_setup_screen.dart'; // Your guardian setup screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initializeNotifications();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Resilience',
      theme: ThemeData(primarySwatch: Colors.indigo),
      debugShowCheckedModeBanner: false,
      // Always start with SplashScreen as the initial route.
      // The SplashScreen itself will handle authentication check and navigation.
      home: const SplashScreen(),

      routes: {
        // Define your named routes here
        '/splash': (context) => const SplashScreen(),
        '/main': (context) => const MainNavigation(),
        '/guardian_login': (context) => const GuardianLoginPage(),
        '/guardian_setup': (context) => const GuardianSetupScreen(),
      },
    );
  }
}
