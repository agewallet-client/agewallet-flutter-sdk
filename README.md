# AgeWallet Flutter SDK

Age verification SDK for Flutter applications using AgeWallet.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  agewallet_flutter_sdk:
    git:
      url: https://github.com/agewallet/agewallet-flutter-sdk.git
```

Then run:

```bash
flutter pub get
```

## Platform Setup

### Android

Add the following to your `AndroidManifest.xml` inside the `<activity>` tag:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="yourapp.com" android:pathPrefix="/callback" />
</intent-filter>
```

Host the `assetlinks.json` file at `https://yourapp.com/.well-known/assetlinks.json`:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.yourcompany.yourapp",
      "sha256_cert_fingerprints": ["YOUR_SHA256_FINGERPRINT"]
    }
  }
]
```

### iOS

Add associated domains to your `Runner.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:yourapp.com</string>
</array>
```

Host the `apple-app-site-association` file at `https://yourapp.com/.well-known/apple-app-site-association`:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.com.yourcompany.yourapp",
        "paths": ["/callback", "/callback/*"]
      }
    ]
  }
}
```

## Usage

```dart
import 'package:agewallet_flutter_sdk/agewallet_flutter_sdk.dart';

// Initialize the SDK
final ageWallet = AgeWallet(
  clientId: 'your-client-id',
  redirectUri: 'https://yourapp.com/callback',
);

// Check if user is verified
final isVerified = await ageWallet.isVerified();

if (!isVerified) {
  // Start verification flow
  await ageWallet.startVerification();
}
```

## Configuration

### AgeWallet Dashboard Setup

1. Register your app on the [AgeWallet Dashboard](https://app.agewallet.io)
2. Create a **public client** (no client secret)
3. Set your redirect URI to your app's universal link (e.g., `https://yourapp.com/callback`)

### Custom Endpoints

For development/staging environments:

```dart
final ageWallet = AgeWallet(
  clientId: 'your-client-id',
  redirectUri: 'https://yourapp.com/callback',
  endpoints: AgeWalletEndpoints(
    auth: 'https://dev.agewallet.io/user/authorize',
    token: 'https://dev.agewallet.io/user/token',
    userinfo: 'https://dev.agewallet.io/user/userinfo',
  ),
);
```

## API Reference

### `AgeWallet`

#### Constructor

```dart
AgeWallet({
  required String clientId,
  required String redirectUri,
  AgeWalletEndpoints? endpoints,
  String? metadata,
})
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `clientId` | String | Yes | Your client ID from AgeWallet dashboard |
| `redirectUri` | String | Yes | Your app's universal link callback URL |
| `endpoints` | AgeWalletEndpoints | No | Override default API endpoints |
| `metadata` | String? | No | Opaque per-verification string (max 4096 UTF-8 bytes) that round-trips through `/userinfo`. See [Metadata](#metadata) below. |

#### Methods

##### `isVerified()`

```dart
Future<bool> isVerified()
```

Checks if the user is currently verified. Returns `true` if verified and not expired, `false` otherwise.

##### `startVerification()`

```dart
Future<void> startVerification()
```

Starts the verification flow. Opens the system browser to the AgeWallet authorization page. The callback is handled automatically when control returns to your app.

##### `handleCallback(url)`

```dart
Future<bool> handleCallback(String url)
```

Manually handles a callback URL. Usually not needed as `startVerification()` handles callbacks automatically. Returns `true` if verification succeeded, `false` otherwise.

##### `clearVerification()`

```dart
Future<void> clearVerification()
```

Clears the stored verification state (logout).

##### `setMetadata(value)`

```dart
void setMetadata(String? value)
```

Updates the instance default metadata attached to subsequent verifications. Pass `null` to clear. Throws `ArgumentError` if the value exceeds `AgeWalletCore.metadataMaxBytes` (4096).

##### `getMetadata()`

```dart
Future<String?> getMetadata()
```

Returns the metadata that round-tripped with the currently-persisted verification, or `null` if none.

##### `startVerification({ String? metadata })`

The optional `metadata` parameter overrides the instance default for that one verification only — it does not mutate the default.

## Metadata

Attach an opaque per-verification string (max 4096 UTF-8 bytes) that round-trips through `/userinfo` and is visible to your backend and the AgeWallet dashboard. Useful for tagging build, environment, or user-flow context.

```dart
// Set as the instance default at construction
final ageWallet = AgeWallet(
  clientId: 'your-client-id',
  redirectUri: 'https://yourapp.com/callback',
  metadata: 'checkout-flow',
);

// Update the default at runtime
ageWallet.setMetadata('new-default');

// Override for a single verification only (does not change the default)
await ageWallet.startVerification(metadata: 'one-shot');

// Read the metadata that round-tripped with the current verification
final received = await ageWallet.getMetadata();
```

## Security

- This SDK is for **public clients only** (no client secret)
- Uses **PKCE (S256)** for secure authorization code exchange
- Tokens are stored securely using platform keychain/keystore
- State parameter provides CSRF protection
- Nonce parameter provides replay protection

## Regional Exemptions

Some regions don't require age verification. When a user is in an exempt region, the SDK automatically grants a 24-hour synthetic verification, so `isVerified()` returns `true`.

## License

MIT
