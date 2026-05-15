/// Data Models
/// Represents the data received from the API
library;

import 'dart:convert';

/// User Model
class User {
  final int id;
  final String username;
  final String email;
  final bool isActive;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.isActive,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Authentication Token Model
class AuthToken {
  final String accessToken;
  final String tokenType;

  AuthToken({required this.accessToken, required this.tokenType});

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    return AuthToken(
      accessToken: json['access_token'],
      tokenType: json['token_type'],
    );
  }
}

/// Detection Result Model
class DetectionResult {
  final int id;
  final DateTime timestamp;
  final String imagePath;
  final bool hasAnomaly;
  final int anomalyCount;
  final double anomalyScore;
  final double inferenceTime;
  final String? gridData;
  final double fabricPosition;
  final int? userId;
  final String? notes;

  DetectionResult({
    required this.id,
    required this.timestamp,
    required this.imagePath,
    required this.hasAnomaly,
    required this.anomalyCount,
    required this.anomalyScore,
    required this.inferenceTime,
    this.gridData,
    required this.fabricPosition,
    this.userId,
    this.notes,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      imagePath: json['image_path'],
      hasAnomaly: json['has_anomaly'],
      anomalyCount: json['anomaly_count'],
      anomalyScore: (json['anomaly_score'] as num).toDouble(),
      inferenceTime: (json['inference_time'] as num).toDouble(),
      gridData: json['grid_data'],
      fabricPosition: (json['fabric_position'] as num).toDouble(),
      userId: json['user_id'],
      notes: json['notes'],
    );
  }

  /// Parse grid data into a list of AnomalyGrid objects
  List<AnomalyGrid> getGridCells() {
    if (gridData == null || gridData!.isEmpty) return [];
    try {
      final List<dynamic> data = json.decode(gridData!);
      return data.map((item) => AnomalyGrid.fromJson(item)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Returns full image URL
  String get fullImageUrl => imagePath.startsWith('http')
      ? imagePath
      : 'http://192.168.1.100:8000/$imagePath';
}

/// Anomaly Grid Cell Model
class AnomalyGrid {
  final int x;
  final int y;
  final int width;
  final int height;
  final double score;

  AnomalyGrid({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.score,
  });

  factory AnomalyGrid.fromJson(Map<String, dynamic> json) {
    return AnomalyGrid(
      x: json['x'],
      y: json['y'],
      width: json['width'],
      height: json['height'],
      score: (json['score'] as num).toDouble(),
    );
  }
}

/// Detection Statistics Model
class DetectionStats {
  final int totalInspections;
  final int totalAnomalies;
  final double anomalyRate;
  final double avgInferenceTime;
  final DateTime? lastInspection;

  DetectionStats({
    required this.totalInspections,
    required this.totalAnomalies,
    required this.anomalyRate,
    required this.avgInferenceTime,
    this.lastInspection,
  });

  factory DetectionStats.fromJson(Map<String, dynamic> json) {
    return DetectionStats(
      totalInspections: json['total_inspections'],
      totalAnomalies: json['total_anomalies'],
      anomalyRate: (json['anomaly_rate'] as num).toDouble(),
      avgInferenceTime: (json['avg_inference_time'] as num).toDouble(),
      lastInspection: json['last_inspection'] != null
          ? DateTime.parse(json['last_inspection'])
          : null,
    );
  }
}

/// System Status Model
class SystemStatus {
  final bool cameraActive;
  final bool motionActive;
  final double currentPosition;
  final int flashBrightness;
  final bool isInspecting;
  final DateTime? lastDetection;

  SystemStatus({
    required this.cameraActive,
    required this.motionActive,
    required this.currentPosition,
    required this.flashBrightness,
    required this.isInspecting,
    this.lastDetection,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      cameraActive: json['camera_active'],
      motionActive: json['motion_active'],
      currentPosition: (json['current_position'] as num).toDouble(),
      flashBrightness: json['flash_brightness'],
      isInspecting: json['is_inspecting'],
      lastDetection: json['last_detection'] != null
          ? DateTime.parse(json['last_detection'])
          : null,
    );
  }
}

/// Alert Model
class Alert {
  final int id;
  final DateTime timestamp;
  final String alertType;
  final String severity;
  final String message;
  final bool isRead;
  final int? detectionId;

  Alert({
    required this.id,
    required this.timestamp,
    required this.alertType,
    required this.severity,
    required this.message,
    required this.isRead,
    this.detectionId,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      alertType: json['alert_type'],
      severity: json['severity'],
      message: json['message'],
      isRead: json['is_read'],
      detectionId: json['detection_id'],
    );
  }

  /// Human-readable severity level
  String get severityText {
    switch (severity) {
      case 'high':
        return 'High';
      case 'medium':
        return 'Medium';
      case 'low':
        return 'Low';
      default:
        return severity;
    }
  }
}
