import 'package:flutter/services.dart';

/// Abstraction adapter wrapping HarmonyOS NEXT / OpenHarmony push platform channels.
abstract class OhosPushAdapter {
  Future<String?> getPushToken();

  Future<void> deleteToken();

  Future<void> requestNotificationPermission();

  Future<bool> getNotificationPermissionStatus();

  Future<Map<String, dynamic>?> getInitialNotification();

  Future<void> subscribeToTopic(String topic);

  Future<void> unsubscribeFromTopic(String topic);

  void setMethodCallHandler(Future<dynamic> Function(MethodCall call)? handler);
}

/// Default implementation delegating to the native HarmonyOS MethodChannel.
class DefaultOhosPushAdapter implements OhosPushAdapter {
  DefaultOhosPushAdapter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.kadmiv.alias/ohos_push');

  final MethodChannel _channel;

  @override
  Future<String?> getPushToken() async {
    try {
      return await _channel.invokeMethod<String>('getPushToken');
    } on MissingPluginException {
      return 'ohos_mock_token_dev';
    }
  }

  @override
  Future<void> deleteToken() async {
    try {
      await _channel.invokeMethod<void>('deleteToken');
    } on MissingPluginException {
      // Missing plugin fallback
    }
  }

  @override
  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on MissingPluginException {
      // Missing plugin fallback
    }
  }

  @override
  Future<bool> getNotificationPermissionStatus() async {
    try {
      return await _channel.invokeMethod<bool>('getNotificationPermissionStatus') ?? true;
    } on MissingPluginException {
      return true;
    }
  }

  @override
  Future<Map<String, dynamic>?> getInitialNotification() async {
    try {
      final dynamic res = await _channel.invokeMethod<dynamic>('getInitialNotification');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _channel.invokeMethod<void>('subscribeToTopic', {'topic': topic});
    } on MissingPluginException {
      // Missing plugin fallback
    }
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _channel.invokeMethod<void>('unsubscribeFromTopic', {'topic': topic});
    } on MissingPluginException {
      // Missing plugin fallback
    }
  }

  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall call)? handler) {
    _channel.setMethodCallHandler(handler);
  }
}
