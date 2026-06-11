import 'types.dart';
import 'agewallet_core.dart';

export 'types.dart';

/// AgeWallet SDK for Flutter applications.
///
/// Provides age verification via OIDC/PKCE flow.
///
/// Example:
/// ```dart
/// final ageWallet = AgeWallet(
///   clientId: 'your-client-id',
///   redirectUri: 'https://yourapp.com/callback',
/// );
///
/// if (!await ageWallet.isVerified()) {
///   await ageWallet.startVerification();
/// }
/// ```
class AgeWallet {
  final AgeWalletCore _core;

  /// Create a new AgeWallet instance.
  ///
  /// [clientId] - Your client ID from the AgeWallet dashboard.
  /// [redirectUri] - Your app's universal link callback URL.
  /// [endpoints] - Optional custom endpoint configuration.
  /// [metadata] - Optional opaque per-verification string (max 4096 bytes).
  AgeWallet({
    required String clientId,
    required String redirectUri,
    AgeWalletEndpoints? endpoints,
    String? metadata,
  }) : _core = AgeWalletCore(
          config: AgeWalletConfig(
            clientId: clientId,
            redirectUri: redirectUri,
            endpoints: endpoints,
            metadata: metadata,
          ),
        );

  /// Check if the user is currently verified.
  ///
  /// Returns `true` if verified and not expired, `false` otherwise.
  Future<bool> isVerified() => _core.isVerified();

  /// Update the metadata default attached to subsequent verifications.
  /// Pass null to clear. Throws ArgumentError if value exceeds 4096 bytes.
  void setMetadata(String? value) => _core.setMetadata(value);

  /// Return the metadata that round-tripped with the current persisted verification, or null.
  Future<String?> getMetadata() => _core.getMetadata();

  /// Build the authorization URL for the verification flow.
  ///
  /// Use this on iOS with url_launcher to open Safari, then handle the
  /// Universal Link callback via app_links. On Android, use [startVerification].
  ///
  /// [metadata] - Optional per-call override; does NOT change the instance default.
  Future<Uri> buildVerificationURL({String? metadata}) =>
      _core.buildVerificationURL(metadata: metadata);

  /// Start the verification flow.
  ///
  /// Opens the system browser to the AgeWallet authorization page.
  /// The callback is handled automatically when control returns to your app.
  /// On Android only. On iOS use [buildVerificationURL] instead.
  ///
  /// [metadata] - Optional per-call override; does NOT change the instance default.
  Future<AgeWalletResult> startVerification({String? metadata}) =>
      _core.startVerification(metadata: metadata);

  /// Manually handle a callback URL.
  ///
  /// Usually not needed as [startVerification] handles callbacks automatically.
  /// Use this if you're handling deep links manually.
  ///
  /// Returns an [AgeWalletResult] indicating the outcome.
  Future<AgeWalletResult> handleCallback(String url) => _core.handleCallback(url);

  /// Clear the stored verification state (logout).
  Future<void> clearVerification() => _core.clearVerification();
}
