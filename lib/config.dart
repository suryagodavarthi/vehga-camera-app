/// Default backend API base URL (no trailing slash): production, in the company
/// Azure account. Can be overridden at runtime from the login screen (long-press
/// the logo).
const String kDefaultApiBaseUrl =
    'https://vehgaprd-ech3ewccc8dxcgcz.centralindia-01.azurewebsites.net/api';

/// Addresses earlier builds shipped as their default. "Reset to default" saved the
/// default as an override, so a phone can hold one of these without anyone choosing
/// it; [Session.apiBaseUrl] drops such a leftover once, on the first run of this build.
const List<String> kRetiredApiBaseUrls = [
  'https://prontobackend-bhdnbec2fvd3ecfk.eastus2-01.azurewebsites.net/api',
];
