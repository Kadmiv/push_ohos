import 'dart:async';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:push_core/push_core.dart';
import 'package:push_ohos/services/ohos_push_adapter.dart';
import 'package:push_ohos/services/ohos_push_notification.dart';
import 'package:synchronized/synchronized.dart';

/// HarmonyOS NEXT / OpenHarmony Push Service implementation (HarmonyOS Push Kit).
class OhosPushServiceImpl extends PushService with StreamSubscriptionsManagementMixin {
  OhosPushServiceImpl({
    OhosPushAdapter? adapter,
    Logger? logger,
  })  : _adapter = adapter ?? DefaultOhosPushAdapter(),
        _log = logger ?? Logger();

  final OhosPushAdapter _adapter;
  final Logger _log;
  final Lock _lock = Lock();
  final CompositeNotificationsListener _listeners = CompositeNotificationsListener();

  final StreamController<String> _tokenRefreshController =
      StreamController<String>.broadcast();
  final StreamController<PushNotification> _receivedController =
      StreamController<PushNotification>.broadcast();
  final StreamController<PushNotification> _openedAppController =
      StreamController<PushNotification>.broadcast();

  String? _token;
  PushNotification? _initialNotification;
  bool _isInitialNotificationDispatched = false;
  bool _isMessagesHandleDisabled = false;

  @override
  String? get token => _token;

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Stream<PushNotification> get onNotificationReceived => _receivedController.stream;

  @override
  Stream<PushNotification> get onNotificationOpenedApp => _openedAppController.stream;

  @override
  Future<void> init({NotificationsListener? listener}) async {
    if (listener != null) {
      _listeners.add(listener);
    }
    _isMessagesHandleDisabled = false;

    return _lock.synchronized(() async {
      _log.i('OhosPushServiceImpl: initializing HarmonyOS Push Kit');

      _adapter.setMethodCallHandler(_handleNativeMethodCall);

      try {
        _token = await _adapter.getPushToken() ?? 'ohos_mock_token_dev';
      } catch (e, st) {
        _log.w('OhosPushServiceImpl: getPushToken failed: $e', error: e, stackTrace: st);
        _token = 'ohos_mock_token_dev';
      }
      _log.i('OhosPushServiceImpl: push token registered: $_token');

      try {
        final initialData = await _adapter.getInitialNotification();
        if (initialData != null) {
          _initialNotification = OhosPushNotification.fromPayload(initialData);
          _log.i('OhosPushServiceImpl: initial notification detected: $_initialNotification');
        }
      } catch (e, st) {
        _log.w('OhosPushServiceImpl: getInitialNotification failed: $e', error: e, stackTrace: st);
      }
    });
  }

  @override
  void setListener(NotificationsListener? listener) {
    _listeners.clear();
    if (listener != null) {
      _listeners.add(listener);
    }
  }

  @override
  void addListener(NotificationsListener listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(NotificationsListener listener) {
    _listeners.remove(listener);
  }

  @override
  Future<void> requestNotificationsPermission() async {
    _log.i('OhosPushServiceImpl: requestNotificationsPermission');
    try {
      await _adapter.requestNotificationPermission();
    } catch (e, st) {
      _log.w('OhosPushServiceImpl: requestNotificationPermission failed: $e', error: e, stackTrace: st);
    }
  }

  @override
  Future<PushNotificationPermissionStatus> getPermissionStatus() async {
    try {
      final isGranted = await _adapter.getNotificationPermissionStatus();
      return isGranted
          ? PushNotificationPermissionStatus.authorized
          : PushNotificationPermissionStatus.denied;
    } catch (e, st) {
      _log.w('OhosPushServiceImpl: getNotificationPermissionStatus failed: $e', error: e, stackTrace: st);
      return PushNotificationPermissionStatus.notDetermined;
    }
  }

  @override
  Future<void> invalidateDeviceToken() async {
    _log.i('OhosPushServiceImpl: invalidateDeviceToken');
    try {
      await _adapter.deleteToken();
    } catch (e, st) {
      _log.w('OhosPushServiceImpl: deleteToken failed: $e', error: e, stackTrace: st);
    }
    _token = null;
  }

  @override
  Future<PushNotification?> getInitialNotification() async {
    return _initialNotification;
  }

  @override
  Future<void> dispatchInitialNotification() async {
    _log.i('OhosPushServiceImpl: dispatchInitialNotification');
    final notification = _initialNotification;
    if (notification != null && !_isInitialNotificationDispatched) {
      _isInitialNotificationDispatched = true;
      if (!_isMessagesHandleDisabled) {
        _listeners.onNotificationOpenedApp(notification);
        _openedAppController.add(notification);
      }
    }
  }

  @override
  Future<void> subscribeToTopic(String topic) async {
    _log.i('OhosPushServiceImpl: subscribeToTopic: $topic');
    try {
      await _adapter.subscribeToTopic(topic);
    } catch (e, st) {
      _log.w('OhosPushServiceImpl: subscribeToTopic failed: $e', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    _log.i('OhosPushServiceImpl: unsubscribeFromTopic: $topic');
    try {
      await _adapter.unsubscribeFromTopic(topic);
    } catch (e, st) {
      _log.w('OhosPushServiceImpl: unsubscribeFromTopic failed: $e', error: e, stackTrace: st);
    }
  }

  @override
  void disableMessagesHandle() {
    _log.i('OhosPushServiceImpl: disableMessagesHandle');
    _isMessagesHandleDisabled = true;
    _adapter.setMethodCallHandler(null);
    closeSubscriptions();
  }

  @override
  Future<void> dispose() async {
    disableMessagesHandle();
    _listeners.clear();
    await _tokenRefreshController.close();
    await _receivedController.close();
    await _openedAppController.close();
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (_isMessagesHandleDisabled) {
      return null;
    }

    _log.i('OhosPushServiceImpl: received native method call: ${call.method}');
    switch (call.method) {
      case 'onMessageReceived':
      case 'onMessage':
        final notification = OhosPushNotification.fromPayload(call.arguments);
        _listeners.onNotificationReceived(notification);
        _receivedController.add(notification);
        return true;

      case 'onMessageOpenedApp':
      case 'onNotificationOpened':
        final notification = OhosPushNotification.fromPayload(call.arguments);
        _listeners.onNotificationOpenedApp(notification);
        _openedAppController.add(notification);
        return true;

      case 'onTokenRefresh':
      case 'onNewToken':
        final newToken = call.arguments?.toString() ?? '';
        if (newToken.isNotEmpty) {
          _token = newToken;
          _listeners.onTokenRefresh(newToken);
          _tokenRefreshController.add(newToken);
        }
        return true;

      default:
        _log.w('OhosPushServiceImpl: unhandled native method call: ${call.method}');
        return null;
    }
  }
}
