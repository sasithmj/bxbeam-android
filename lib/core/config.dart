class AppConfig {
  // Define the license expiration date. Set to null if there is no expiration.
  // Format: YYYY-MM-DD
  static const String? licenseExpiryDate = null;

  /// Returns true if the current time has passed the configured expiry date.
  static bool isLicenseExpired() => false;
}
