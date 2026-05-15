/// Constants File
/// Contains all constant values used in the application
library;

class AppConstants {
  // API Configuration
  //  IMPORTANT: Change this IP to your Raspberry Pi IP address
  static const String baseUrl = "http://localhost:8000";
  static const String wsUrl = 'ws://localhost:8000/ws';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);

  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String usernameKey = 'username';
  static const String rememberMeKey = 'remember_me';

  // UI Constants
  static const double defaultPadding = 16.0;
  static const double defaultRadius = 12.0;
  static const double defaultElevation = 2.0;

  // Detection Settings
  static const int maxFlashBrightness = 16;
  static const double maxPosition = 42.0;
  static const int defaultStatsRange = 7; // days

  // Anomaly Thresholds
  static const double lowAnomalyThreshold = 0.3;
  static const double mediumAnomalyThreshold = 0.6;
  static const double highAnomalyThreshold = 0.8;
}

class AppStrings {
  // App Name
  static const String appName = 'Fabric AI';
  static const String appNameAr = 'Anomaly Detection System';

  // Auth Strings
  static const String login = 'Login';
  static const String register = 'Register';
  static const String username = 'Username';
  static const String email = 'Email';
  static const String password = 'Password';
  static const String rememberMe = 'Remember Me';
  static const String forgotPassword = 'Forgot Password?';

  // Dashboard
  static const String dashboard = 'Dashboard';
  static const String statistics = 'Statistics';
  static const String newInspection = 'New Inspection';
  static const String recentInspections = 'Recent Inspections';

  // Stats
  static const String totalInspections = 'Total Inspections';
  static const String totalAnomalies = 'Total Anomalies';
  static const String anomalyRate = 'Anomaly Rate';
  static const String avgInferenceTime = 'Average Inference Time';

  // Results
  static const String results = 'Results';
  static const String allResults = 'All Results';
  static const String anomaliesOnly = 'Anomalies Only';
  static const String normalOnly = 'Normal Only';

  // Control
  static const String control = 'Control';
  static const String systemControl = 'System Control';
  static const String flashBrightness = 'Flash Brightness';
  static const String position = 'Position';
  static const String systemStatus = 'System Status';

  // Alerts
  static const String alerts = 'Alerts';
  static const String unreadAlerts = 'Unread Alerts';
  static const String noAlerts = 'No Alerts Available';

  // Detection
  static const String detecting = 'Detecting...';
  static const String detectionComplete = 'Detection Complete';
  static const String anomalyDetected = 'Anomaly Detected!';
  static const String noAnomalyDetected = 'No Anomaly Detected';
  static const String anomalyCount = 'Anomaly Count';
  static const String anomalyScore = 'Anomaly Score';
  static const String inferenceTime = 'Inference Time';

  // Settings
  static const String settings = 'Settings';
  static const String account = 'Account';
  static const String notifications = 'Notifications';
  static const String about = 'About';
  static const String logout = 'Logout';

  // Common
  static const String loading = 'Loading...';
  static const String error = 'Error';
  static const String success = 'Success';
  static const String retry = 'Retry';
  static const String cancel = 'Cancel';
  static const String ok = 'OK';
  static const String save = 'Save';
  static const String delete = 'Delete';
  static const String refresh = 'Refresh';
}
