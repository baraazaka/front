import 'package:dio/dio.dart';
import '../core/constants.dart';
import '../models/models.dart';

class ApiService {
  late final Dio _dio;
  String? _token;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: AppConstants.connectionTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Interceptor to handle token automatically
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          // Handle authentication errors
          if (error.response?.statusCode == 401) {
            // Token expired – clear token
            _token = null;
          }
          return handler.next(error);
        },
      ),
    );
  }

  void setToken(String token) {
    _token = token;
  }

  String? getToken() => _token;

  void clearToken() {
    _token = null;
  }

  /// Register new user
  Future<User> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/register',
        data: {'username': username, 'email': email, 'password': password},
      );
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Login user
  Future<AuthToken> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/login',
        data: {'username': username, 'password': password},
      );
      final token = AuthToken.fromJson(response.data);
      setToken(token.accessToken);
      return token;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Start new inspection
  Future<DetectionResult> inspect() async {
    try {
      final response = await _dio.post('/api/detection/inspect');
      return DetectionResult.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get detection results
  Future<List<DetectionResult>> getResults({
    int skip = 0,
    int limit = 50,
    bool? hasAnomaly,
  }) async {
    try {
      final queryParams = {
        'skip': skip,
        'limit': limit,
        'has_anomaly': ?hasAnomaly,
      };

      final response = await _dio.get(
        '/api/detection/results',
        queryParameters: queryParams,
      );

      return (response.data as List)
          .map((item) => DetectionResult.fromJson(item))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get detection statistics
  Future<DetectionStats> getStats({int days = 7}) async {
    try {
      final response = await _dio.get(
        '/api/detection/stats',
        queryParameters: {'days': days},
      );
      return DetectionStats.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get specific detection result
  Future<DetectionResult> getDetection(int id) async {
    try {
      final response = await _dio.get('/api/detection/$id');
      return DetectionResult.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ==================== System Control ====================

  /// Set flash brightness
  Future<void> setFlashBrightness(int brightness) async {
    try {
      await _dio.post(
        '/api/control/camera',
        data: {'action': 'set_brightness', 'brightness': brightness},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Move system to specific position
  Future<double> moveToPosition(double position) async {
    try {
      final response = await _dio.post(
        '/api/control/motion',
        data: {'action': 'move_to', 'position': position},
      );
      return (response.data['position'] as num).toDouble();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get system status
  Future<SystemStatus> getSystemStatus() async {
    try {
      final response = await _dio.get('/api/control/status');
      return SystemStatus.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get alerts
  Future<List<Alert>> getAlerts({
    bool unreadOnly = false,
    int skip = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '/api/alerts',
        queryParameters: {
          'unread_only': unreadOnly,
          'skip': skip,
          'limit': limit,
        },
      );

      return (response.data as List)
          .map((item) => Alert.fromJson(item))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Mark alert as read
  Future<void> markAlertRead(int alertId) async {
    try {
      await _dio.patch('/api/alerts/$alertId/read');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException error) {
    if (error.response != null) {
      final data = error.response!.data;
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
      return 'Server error: ${error.response!.statusCode}';
    } else if (error.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout. Please check your internet connection.';
    } else if (error.type == DioExceptionType.receiveTimeout) {
      return 'Receive timeout. Server took too long to respond.';
    } else if (error.type == DioExceptionType.connectionError) {
      return 'Connection error. Please check the Raspberry Pi IP address.';
    }
    return 'Unexpected error: ${error.message}';
  }
}
