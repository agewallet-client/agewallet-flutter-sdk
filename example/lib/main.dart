import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:agewallet_flutter_sdk/agewallet_flutter_sdk.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgeWallet SDK Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

const _clientId = 'your-client-id';
const _authUrl = 'https://app.agewallet.io/user/authorize';
const _tokenUrl = 'https://app.agewallet.io/user/token';
const _userinfoUrl = 'https://app.agewallet.io/user/userinfo';

class _HomePageState extends State<HomePage> {
  // Auto-detected default metadata: identifies the demo build to the dev/QA team
  // when verifications land on the server.
  String get _autoDefault => Platform.isIOS ? 'Flutter iOS' : 'Flutter Android';

  late final AgeWallet _ageWallet;
  bool _isVerified = false;
  bool _isLoading = true;
  String? _lastMetadata;

  final TextEditingController _customController = TextEditingController();

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _ageWallet = AgeWallet(
      clientId: _clientId,
      redirectUri: 'https://agewallet-sdk-demo.netlify.app/callback',
      endpoints: AgeWalletEndpoints(
        auth: _authUrl,
        token: _tokenUrl,
        userinfo: _userinfoUrl,
      ),
      metadata: _autoDefault,
    );
    _checkVerification();

    if (Platform.isIOS) {
      _appLinks = AppLinks();
      _linkSub = _appLinks!.uriLinkStream.listen((uri) {
        if (uri.host == 'agewallet-sdk-demo.netlify.app' &&
            uri.path.startsWith('/callback')) {
          _handleCallback(uri.toString());
        }
      });
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _customController.dispose();
    super.dispose();
  }

  Future<void> _checkVerification() async {
    try {
      final isVerified = await _ageWallet.isVerified();
      final metadata = isVerified ? await _ageWallet.getMetadata() : null;
      setState(() {
        _isVerified = isVerified;
        _lastMetadata = metadata;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startVerification() async {
    setState(() => _isLoading = true);
    // If the "Custom metadata" field has text, append it to the auto-default for
    // this verification only. Otherwise the instance default kicks in (set in initState).
    final custom = _customController.text.trim();
    final override = custom.isNotEmpty ? '$_autoDefault | $custom' : null;
    try {
      if (Platform.isIOS) {
        final url = await _ageWallet.buildVerificationURL(metadata: override);
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        final result = await _ageWallet.startVerification(metadata: override);
        if (result == AgeWalletResult.denied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Age verification was cancelled.')),
          );
        } else if (result == AgeWalletResult.failed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification could not be completed. Please try again.')),
          );
        }
        await _checkVerification();
      }
    } on ArgumentError catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Metadata too long')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!Platform.isIOS && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification failed: $e')),
        );
      }
    }
  }

  Future<void> _handleCallback(String url) async {
    setState(() => _isLoading = true);
    final result = await _ageWallet.handleCallback(url);
    await _checkVerification();
    if (!_isVerified && mounted) {
      if (result == AgeWalletResult.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Age verification was cancelled.')),
        );
      } else if (result == AgeWalletResult.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification could not be completed. Please try again.')),
        );
      }
    }
  }

  Future<void> _clearVerification() async {
    await _ageWallet.clearVerification();
    setState(() {
      _isVerified = false;
      _lastMetadata = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _isLoading
                ? const CircularProgressIndicator()
                : _isVerified
                    ? _buildVerifiedView()
                    : _buildUnverifiedView(),
          ),
        ),
      ),
    );
  }

  Widget _buildUnverifiedView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(Icons.lock_outline, size: 40, color: Color(0xFF6366F1)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Age Verification Required',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
          ),
          const SizedBox(height: 8),
          const Text(
            'You must verify your age to access this content.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 28),

          // Auto-detected default metadata — informational, baked in at build time.
          _sectionLabel('Default metadata (auto)'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _autoDefault,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937), fontFamily: 'monospace'),
            ),
          ),

          const SizedBox(height: 20),

          // Optional per-call append — concatenated to the default for this verification only.
          _sectionLabel('Custom metadata (optional, appended for this call only)'),
          TextField(
            controller: _customController,
            decoration: const InputDecoration(
              hintText: 'e.g. order-1234',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'If populated, sent as "$_autoDefault | <your text>" for this verification only.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Verify with AgeWallet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
        ),
      ),
    );
  }

  Widget _buildVerifiedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Icon(Icons.check_circle_outline, size: 50, color: Color(0xFF10B981)),
        ),
        const SizedBox(height: 32),
        const Text(
          'Age Verified',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
        ),
        const SizedBox(height: 12),
        const Text(
          'You have successfully verified your age.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Metadata attached to current verification:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 4),
              Text(
                _lastMetadata ?? '(none)',
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _clearVerification,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: const Text('Clear Verification', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
