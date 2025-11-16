import 'package:firebase_messaging/firebase_messaging.dart';

abstract class NotificationService {
  Future<void> initialize();

  Future<NotificationSettings> requestPermissions();

  Future<String?> getDeviceToken();

  Future<void> subscribeToField(String fieldId);

  Future<void> unsubscribeFromField(String fieldId);
}

