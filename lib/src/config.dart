/// Static configuration for the EBB (TELUS Health Connect) backend.
///
/// All values were established by reverse-engineering the Lien Santé NB
/// Health link (TELUS Health Connect) web app.
class EbbConfig {
  EbbConfig._();

  /// Single GraphQL endpoint that drives the whole product.
  static const String graphqlEndpoint =
      'https://backend.thconnect.telushealth.com/graphql/external-api/graphql';

  /// Backend base (REST auth + GraphQL share this host).
  static const String backendBase = 'https://backend.thconnect.telushealth.com';

  /// REST token-refresh endpoint (camelCase JSON, tokens rotate).
  static const String refreshEndpoint = '$backendBase/auth/refresh';

  /// Native email/password sign-in. Body `{username, password}`.
  static const String signInEndpoint = '$backendBase/auth/sign-in';

  /// Two-factor challenge endpoints (used when sign-in returns a `ref`).
  static const String twoFactorRequestEndpoint = '$backendBase/auth/services/two-factor/request';
  static const String twoFactorConfirmEndpoint = '$backendBase/auth/services/two-factor/confirm';

  /// Constant client identifier the backend requires on auth calls
  /// (`Dk(){return "d0Vi"}` in the app bundle).
  static const String clientId = 'd0Vi';

  /// Auth endpoint version header the app sends.
  static const String endpointVersion = '2024-02-07';

  /// Web origin used to build the "open booking" hand-off URL.
  static const String appOrigin = 'https://thconnect.telushealth.com';

  /// The TELUS Health Connect booking hand-off URL for an account. Opening it
  /// with an external-application launch lets the installed TH Connect app take
  /// over (via Android App Links) when present, otherwise the browser.
  static Uri bookingUrl(String accountId) => Uri.parse(appOrigin).replace(
        pathSegments: [accountId, 'booking', 'new-appointment'],
      );

  /// Default UI language sent as the `x-language` header.
  static const String defaultLanguage = 'en';

  /// Refresh the access token this far before its JWT `exp` to avoid races.
  static const Duration refreshSkew = Duration(seconds: 45);
}
