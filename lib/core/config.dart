class AppConfig {
  // Define the license expiration date. Set to null if there is no expiration.
  // Format: YYYY-MM-DD
  static const String? licenseExpiryDate = "2026-07-17";

  /// Returns true if the current time has passed the configured expiry date.
  static bool isLicenseExpired() {
    if (licenseExpiryDate == null) return false;
    final expiry = DateTime.tryParse(licenseExpiryDate!);
    if (expiry == null) return false;

    // Set expiration to the very end of the specified day (23:59:59)
    final expiryEndOfDay = DateTime(
      expiry.year,
      expiry.month,
      expiry.day,
      23,
      59,
      59,
    );
    return DateTime.now().isAfter(expiryEndOfDay);
  }
}
