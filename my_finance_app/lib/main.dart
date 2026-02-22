import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/utils/firebase_options.dart';
import 'features/auth/domain/entities/user_entity.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/transactions/presentation/screens/transactions_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ProviderScope wraps the entire tree so Riverpod providers are available
  // from the very first frame — including inside FirebaseInitializer.
  runApp(const ProviderScope(child: FirebaseInitializer()));
}

// ─────────────────────────────────────────────────────────────────────────────
// Firebase initializer
// Runs Firebase.initializeApp() once and shows the appropriate child:
//   • loading  → _SplashScreen
//   • error    → _FirebaseErrorScreen  (bad config / missing google-services)
//   • success  → MyFinanceApp
// ─────────────────────────────────────────────────────────────────────────────

class FirebaseInitializer extends StatefulWidget {
  const FirebaseInitializer({super.key});

  @override
  State<FirebaseInitializer> createState() => _FirebaseInitializerState();
}

class _FirebaseInitializerState extends State<FirebaseInitializer> {
  // Store the future so it isn't re-created on every rebuild.
  late final Future<FirebaseApp> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Firebase is ready — hand off to the main app.
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return const MyFinanceApp();
        }

        // Wrap error/loading screens in a minimal MaterialApp so they can
        // use Scaffold, Theme, etc. before the main app is mounted.
        if (snapshot.hasError) {
          return _AppShell(
            child: _FirebaseErrorScreen(error: snapshot.error.toString()),
          );
        }

        return const _AppShell(child: _SplashScreen());
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main app — only mounted after Firebase.initializeApp() succeeds.
// ─────────────────────────────────────────────────────────────────────────────

class MyFinanceApp extends StatelessWidget {
  const MyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Finance App',
      debugShowCheckedModeBanner: false,
      theme: _appTheme,
      // AppRouter is the single source of truth for navigation.
      // Individual screens do NOT push/pop based on auth state.
      home: const AppRouter(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppRouter
// Watches the Firebase auth stream via authStateProvider and rebuilds
// the root widget whenever the auth state changes.
//
//   authStateProvider value │ Screen rendered
//   ─────────────────────────┼───────────────────
//   loading                  │ _SplashScreen
//   data(null)               │ LoginScreen
//   data(UserEntity)         │ TransactionsScreen
//   error                    │ _FirebaseErrorScreen
// ─────────────────────────────────────────────────────────────────────────────

class AppRouter extends ConsumerWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);

    return authAsync.when(
      data: (UserEntity? user) =>
          user != null ? const TransactionsScreen() : const LoginScreen(),
      loading: () => const _SplashScreen(),
      error: (error, _) => _FirebaseErrorScreen(error: error.toString()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared theme — used by both _AppShell and MyFinanceApp.
// ─────────────────────────────────────────────────────────────────────────────

final _appTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
  useMaterial3: true,
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Minimal MaterialApp wrapper for screens shown before Firebase is ready.
// ─────────────────────────────────────────────────────────────────────────────

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _appTheme,
      home: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash screen — shown while Firebase initialises or auth stream loads.
// ─────────────────────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 80,
              color: Color(0xFF1E88E5),
            ),
            const SizedBox(height: 24),
            Text(
              'My Finance App',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Firebase error screen — shown when Firebase.initializeApp() fails.
// Most common causes:
//   • firebase_options.dart still contains placeholder values
//   • google-services.json / GoogleService-Info.plist missing
//   • No internet connection on first launch (web)
// ─────────────────────────────────────────────────────────────────────────────

class _FirebaseErrorScreen extends StatelessWidget {
  final String error;
  const _FirebaseErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_rounded,
                    size: 72, color: Colors.red.shade400),
                const SizedBox(height: 20),
                Text(
                  'Falha ao inicializar o Firebase',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Verifique se as credenciais em firebase_options.dart\n'
                  'foram preenchidas, ou execute:\n\n'
                  'flutterfire configure',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: SelectableText(
                    error,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
