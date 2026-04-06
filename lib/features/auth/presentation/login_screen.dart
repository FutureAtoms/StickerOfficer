import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../data/providers.dart';

/// Web client ID for Google Sign-In — used to obtain an ID token for
/// server-side verification. Replace with your actual Web OAuth client ID
/// from Google Cloud Console.
const _googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '',
);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;

  bool _googleInitialized = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final gsi = GoogleSignIn.instance;
      if (!_googleInitialized) {
        await gsi.initialize(
          serverClientId:
              _googleServerClientId.isNotEmpty ? _googleServerClientId : null,
        );
        _googleInitialized = true;
      }

      final account = await gsi.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('Failed to obtain Google ID token');
      }

      await ref.read(authStateProvider.notifier).signInWithGoogle(idToken);

      if (mounted) {
        setState(() => _isLoading = false);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: ${e.toString().split('\n').first}'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      // Generate a nonce for replay protection
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.fullName,
          AppleIDAuthorizationScopes.email,
        ],
        nonce: hashedNonce,
      );

      final identityToken = credential.identityToken;
      if (identityToken == null) {
        throw Exception('Failed to obtain Apple identity token');
      }

      // Build full name from Apple's response (only available on first auth)
      String? fullName;
      if (credential.givenName != null || credential.familyName != null) {
        fullName =
            [credential.givenName, credential.familyName]
                .where((s) => s != null && s.isNotEmpty)
                .join(' ');
      }

      await ref
          .read(authStateProvider.notifier)
          .signInWithApple(identityToken, fullName: fullName, rawNonce: rawNonce);

      if (mounted) {
        setState(() => _isLoading = false);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Apple sign-in failed: ${e.toString().split('\n').first}'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // App icon
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 48, color: Colors.white),
              )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1, 1),
                    duration: 600.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: 32),
              Text(
                'Link your account',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 500.ms, delay: 200.ms),
              const SizedBox(height: 8),
              Text(
                'Sign in to sync across devices',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 500.ms, delay: 300.ms),
              const Spacer(),
              // Google Sign-In
              BubblyButton(
                label: 'Sign in with Google',
                icon: Icons.g_mobiledata_rounded,
                color: Colors.white,
                textColor: Colors.black87,
                isLoading: _isLoading,
                onPressed: _signInWithGoogle,
              ).animate().fadeIn(duration: 500.ms, delay: 400.ms),
              const SizedBox(height: 16),
              // Apple Sign-In (iOS only)
              if (Platform.isIOS) ...[
                BubblyButton(
                  label: 'Sign in with Apple',
                  icon: Icons.apple_rounded,
                  color: Colors.black,
                  textColor: Colors.white,
                  isLoading: _isLoading,
                  onPressed: _signInWithApple,
                ).animate().fadeIn(duration: 500.ms, delay: 500.ms),
                const SizedBox(height: 16),
              ],
              // Skip
              TextButton(
                onPressed: _isLoading ? null : () => context.pop(),
                child: const Text('Continue without signing in'),
              ).animate().fadeIn(duration: 500.ms, delay: 600.ms),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
