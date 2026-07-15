import 'package:flutter/material.dart';

import 'api/account_bootstrap.dart';
import 'api/api_client.dart';
import 'api/booking_repository.dart';
import 'auth/auth_controller.dart';
import 'scanner/scanner.dart';
import 'ui/login_screen.dart';
import 'ui/scan_screen.dart';

/// Wired dependencies available once the user is signed in.
class Services {
  Services(this.auth)
      : _api = EbbApi(DirectGraphQLTransport(), auth) {
    booking = BookingRepository(_api);
    scanner = AvailabilityScanner(booking);
    bootstrap = AccountBootstrap(_api);
  }

  final AuthController auth;
  final EbbApi _api;
  late final BookingRepository booking;
  late final AvailabilityScanner scanner;
  late final AccountBootstrap bootstrap;
}

class HealthLinkApp extends StatelessWidget {
  const HealthLinkApp({super.key, required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthLink Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4B286D), // TELUS purple
      ),
      home: AuthGate(auth: auth),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        if (!auth.isAuthenticated) {
          return LoginScreen(auth: auth);
        }
        return ScanScreen(services: Services(auth));
      },
    );
  }
}
