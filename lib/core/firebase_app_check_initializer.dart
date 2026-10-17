import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Activates App Check only when this build has the required public attestation
/// configuration. A reCAPTCHA site key is not a provider secret, but it is kept
/// out of source so each deployed web environment can supply its own key.
abstract final class FirebaseAppCheckInitializer {
  static const String _webRecaptchaSiteKey = String.fromEnvironment(
    'FIREBASE_APP_CHECK_RECAPTCHA_SITE_KEY',
  );
  static const bool _enableWebDebugProvider = bool.fromEnvironment(
    'FIREBASE_APP_CHECK_DEBUG',
  );
  static const String _webDebugToken = String.fromEnvironment(
    'FIREBASE_APP_CHECK_DEBUG_TOKEN',
  );

  static String? statusMessage;

  static Future<void> activateIfConfigured() async {
    if (kIsWeb &&
        !_usesWebDebugProvider &&
        _webRecaptchaSiteKey.trim().isEmpty) {
      statusMessage = 'Firebase App Check is not configured for this web build. Set FIREBASE_APP_CHECK_RECAPTCHA_SITE_KEY after registering the app in Firebase Console, or use FIREBASE_APP_CHECK_DEBUG=true only for localhost development.';
      return;
    }
    try {
      await FirebaseAppCheck.instance.activate(
        providerWeb: kIsWeb
            ? _usesWebDebugProvider
                  ? WebDebugProvider(
                      debugToken: _webDebugToken.trim().isEmpty
                          ? null
                          : _webDebugToken,
                    )
                  : ReCaptchaV3Provider(_webRecaptchaSiteKey)
            : null,
      );
      statusMessage = null;
    } catch (_) {
      statusMessage = 'Firebase App Check could not be activated. The Copilot will show a setup error if Firebase AI requires an App Check token.';
    }
  }

  static bool get isConfiguredForWeb =>
      !kIsWeb ||
      _usesWebDebugProvider ||
      _webRecaptchaSiteKey.trim().isNotEmpty;

  /// The debug provider is intentionally limited to `flutter run` debug
  /// sessions. It must never become a production release escape hatch.
  static bool get _usesWebDebugProvider =>
      kIsWeb && kDebugMode && _enableWebDebugProvider;
}
