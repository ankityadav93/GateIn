class AppConstants {
  // Storage Keys
  static const String usernameKey = 'nkn_username';
  static const String passwordKey = 'nkn_password';
  static const String accountsKey = 'saved_accounts';

  // Network
  static const List<String> commonPortalIPs = [
    "http://172.16.222.1:1000/login?",
    "http://24.24.0.1:1000/login?",
    "http://20.20.0.1:1000/login?",
  ];

  static const Duration connectionTimeout = Duration(milliseconds: 700);
  static const Duration portalDetectionTimeout = Duration(seconds: 2);
  static const Duration pageLoadDelay = Duration(milliseconds: 300);
}