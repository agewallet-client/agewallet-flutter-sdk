import 'dart:convert';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'types.dart';
import 'security.dart';
import 'storage.dart';

/// Core OIDC/PKCE implementation for AgeWallet age verification.
class AgeWalletCore {
  /// Maximum byte length for the metadata string (matches server-side limit).
  static const int metadataMaxBytes = 4096;

  AgeWalletConfig config;
  final Storage storage;

  /// Runtime metadata default; mutable via setMetadata(). Initialised from config.metadata.
  String? _currentMetadata;

  AgeWalletCore({
    required this.config,
    Storage? storage,
  }) : storage = storage ?? Storage() {
    if (config.clientId.isEmpty) {
      throw ArgumentError('[AgeWallet] Missing clientId');
    }
    if (config.redirectUri.isEmpty) {
      throw ArgumentError('[AgeWallet] Missing redirectUri');
    }
    _validateMetadata(config.metadata);
    _currentMetadata = config.metadata;
  }

  /// Check if the user is currently verified (and not expired).
  Future<bool> isVerified() async {
    final state = await storage.getVerification();
    return state?.isVerified ?? false;
  }

  /// Update the metadata default attached to subsequent verifications.
  /// Pass null to clear. Validates length; throws ArgumentError if > 4096 bytes.
  void setMetadata(String? value) {
    _validateMetadata(value);
    _currentMetadata = value;
  }

  /// Return the metadata that round-tripped with the current persisted verification, or null.
  Future<String?> getMetadata() async {
    final state = await storage.getVerification();
    return state?.metadata;
  }

  void _validateMetadata(String? value) {
    if (value == null) return;
    if (value.codeUnits.length > metadataMaxBytes) {
      throw ArgumentError(
          '[AgeWallet] metadata exceeds $metadataMaxBytes-byte limit');
    }
  }

  /// Build the authorization URL for the verification flow.
  /// Generates PKCE parameters, stores OIDC state, and returns the URL to open.
  /// Use this on iOS with url_launcher; use startVerification() on Android.
  ///
  /// [metadata] - Optional per-call override; does NOT change the instance default.
  Future<Uri> buildVerificationURL({String? metadata}) async {
    final effectiveMetadata = metadata ?? _currentMetadata;
    _validateMetadata(effectiveMetadata);

    final verifier = Security.generateVerifier();
    final challenge = Security.generateChallenge(verifier);
    // Prefix matches the netlify autoMap so the callback page can auto-fire the
    // intent for this demo's package. Without a recognized prefix the netlify
    // page falls through to a manual button view, requiring user interaction
    // to complete the OIDC chain.
    final state = 'flutter:${Security.generateState()}';
    final nonce = Security.generateNonce();

    await storage.setOidcState(OidcState(
      state: state,
      verifier: verifier,
      nonce: nonce,
    ));

    final params = <String, String>{
      'response_type': 'code',
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
      'scope': 'openid age',
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'nonce': nonce,
    };

    if (effectiveMetadata != null && effectiveMetadata.isNotEmpty) {
      params['metadata'] = effectiveMetadata;
    }

    return Uri.parse(config.authEndpoint).replace(queryParameters: params);
  }

  /// Start the verification flow.
  /// Opens the system browser to AgeWallet authorization page.
  /// Uses FlutterWebAuth2 — suitable for Android. On iOS use buildVerificationURL() instead.
  ///
  /// [metadata] - Optional per-call override; does NOT change the instance default.
  Future<AgeWalletResult> startVerification({String? metadata}) async {
    final authUrl = await buildVerificationURL(metadata: metadata);

    try {
      // Open browser and wait for callback
      final callbackUrlStr = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: Uri.parse(config.redirectUri).scheme,
      );

      // Handle the callback
      return await handleCallback(callbackUrlStr);
    } catch (e) {
      // User cancelled or error occurred
      await storage.clearOidcState();
      return AgeWalletResult.failed;
    }
  }

  /// Handle callback URL from authorization.
  /// Returns an [AgeWalletResult] indicating the outcome.
  Future<AgeWalletResult> handleCallback(String url) async {
    final uri = Uri.parse(url);
    final params = uri.queryParameters;

    final code = params['code'];
    final state = params['state'];
    final error = params['error'];
    final errorDescription = params['error_description'];

    // Handle error response
    if (error != null) {
      print('[AgeWallet] Authorization error: $error - $errorDescription');
      await storage.clearOidcState();
      return errorDescription == 'The user denied the request'
          ? AgeWalletResult.denied
          : AgeWalletResult.failed;
    }

    // Validate required parameters
    if (code == null || state == null) {
      print('[AgeWallet] Missing code or state in callback');
      await storage.clearOidcState();
      return AgeWalletResult.failed;
    }

    // Validate state matches stored state
    final storedOidc = await storage.getOidcState();
    if (storedOidc == null || storedOidc.state != state) {
      print('[AgeWallet] Invalid state or session expired');
      await storage.clearOidcState();
      return AgeWalletResult.failed;
    }

    try {
      // Exchange code for tokens
      final tokenResponse = await _exchangeCode(code, storedOidc.verifier);
      if (tokenResponse == null) {
        await storage.clearOidcState();
        return AgeWalletResult.failed;
      }

      // Fetch user info to verify age claim
      final userInfo = await _fetchUserInfo(tokenResponse['access_token']);
      if (userInfo == null) {
        await storage.clearOidcState();
        return AgeWalletResult.failed;
      }

      // Check age_verified claim
      final ageVerified = userInfo['age_verified'] as bool? ?? false;
      if (!ageVerified) {
        print('[AgeWallet] Age verification failed');
        await storage.clearOidcState();
        return AgeWalletResult.failed;
      }

      // Calculate expiry (use expires_in from token or default to 1 hour)
      final expiresIn = tokenResponse['expires_in'] as int? ?? 3600;
      final expiresAt =
          DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);

      // Store verification state (including any metadata round-tripped via /userinfo)
      final returnedMetadata = userInfo['metadata'] as String?;
      await storage.setVerification(VerificationState(
        accessToken: tokenResponse['access_token'],
        expiresAt: expiresAt,
        isVerified: true,
        metadata: returnedMetadata,
      ));

      await storage.clearOidcState();
      return AgeWalletResult.success;
    } catch (e) {
      print('[AgeWallet] Error during token exchange: $e');
      await storage.clearOidcState();
      return AgeWalletResult.failed;
    }
  }

  /// Exchange authorization code for tokens.
  Future<Map<String, dynamic>?> _exchangeCode(
      String code, String verifier) async {
    try {
      final response = await http.post(
        Uri.parse(config.tokenEndpoint),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'authorization_code',
          'client_id': config.clientId,
          'redirect_uri': config.redirectUri,
          'code': code,
          'code_verifier': verifier,
        },
      );

      if (response.statusCode != 200) {
        print('[AgeWallet] Token exchange failed: ${response.statusCode}');
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('[AgeWallet] Token exchange error: $e');
      return null;
    }
  }

  /// Fetch user info from the userinfo endpoint.
  Future<Map<String, dynamic>?> _fetchUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse(config.userinfoEndpoint),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode != 200) {
        print('[AgeWallet] UserInfo fetch failed: ${response.statusCode}');
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('[AgeWallet] UserInfo fetch error: $e');
      return null;
    }
  }

  /// Clear all verification state (logout).
  Future<void> clearVerification() async {
    await storage.clearVerification();
    await storage.clearOidcState();
  }
}
