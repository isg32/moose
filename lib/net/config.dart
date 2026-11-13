/// Where Moose's backend lives, from `--dart-define-from-file=env.json`
/// (git-ignored; see `env.example.json`). With no API URL the app runs on
/// the mock partner, as tests and previews do.
class NeonConfig {
  const NeonConfig({required this.api, required this.auth});

  /// The `api` Neon Function, no trailing slash.
  final String api;

  /// Managed Auth's base URL (`NEON_AUTH_BASE_URL`).
  final String auth;

  static const _api = String.fromEnvironment('MOOSE_API_URL');
  static const _auth = String.fromEnvironment('MOOSE_AUTH_URL');

  /// The build's backend, or null to use the mocks.
  static NeonConfig? get fromEnvironment => _api.isEmpty || _auth.isEmpty
      ? null
      : NeonConfig(api: _strip(_api), auth: _strip(_auth));

  static String _strip(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
