import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:push_ohos/push_ohos.dart';

class MockOhosPushAdapter implements OhosPushAdapter {
  Future<dynamic> Function(MethodCall call)? methodCallHandler;

  String? mockToken = 'ohos_token_xyz_123';
  Map<String, dynamic>? mockInitialNotification;
  bool isPermissionGranted = true;
  int deleteTokenCalls = 0;
  int requestPermissionCalls = 0;
  final List<String> subscribedTopics = [];
  final List<String> unsubscribedTopics = [];

  bool shouldThrowOnGetToken = false;
  bool shouldThrowOnGetInitial = false;

  @override
  Future<String?> getPushToken() async {
    if (shouldThrowOnGetToken) {
      throw Exception('Channel unavailable');
    }
    return mockToken;
  }

  @override
  Future<void> deleteToken() async {
    deleteTokenCalls++;
    mockToken = null;
  }

  @override
  Future<void> requestNotificationPermission() async {
    requestPermissionCalls++;
  }

  @override
  Future<bool> getNotificationPermissionStatus() async {
    return isPermissionGranted;
  }

  @override
  Future<Map<String, dynamic>?> getInitialNotification() async {
    if (shouldThrowOnGetInitial) {
      throw Exception('Initial notification failed');
    }
    return mockInitialNotification;
  }

  @override
  Future<void> subscribeToTopic(String topic) async {
    subscribedTopics.add(topic);
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    unsubscribedTopics.add(topic);
  }

  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall call)? handler) {
    methodCallHandler = handler;
  }

  Future<dynamic> simulateNativeMethodCall(String method, [dynamic arguments]) async {
    if (methodCallHandler != null) {
      return methodCallHandler!(MethodCall(method, arguments));
    }
    return null;
  }
}

class TestOhosListener extends NotificationsListener {
  final List<PushNotification> received = [];
  final List<PushNotification> openedApp = [];
  final List<String> tokenRefreshes = [];

  @override
  void onNotificationReceived(PushNotification message) {
    received.add(message);
  }

  @override
  void onNotificationOpenedApp(PushNotification message) {
    openedApp.add(message);
  }

  @override
  void onTokenRefresh(String token) {
    tokenRefreshes.add(token);
  }
}

void main() {
  group('OhosPushServiceImpl Comprehensive Test Suite', () {
    late MockOhosPushAdapter adapter;
    late OhosPushServiceImpl service;
    late TestOhosListener listener;

    setUp(() {
      adapter = MockOhosPushAdapter();
      listener = TestOhosListener();
      service = OhosPushServiceImpl(
        adapter: adapter,
        logger: Logger(level: Level.off),
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('init sets method handler, retrieves push token, and logs', () async {
      expect(service.token, isNull);

      await service.init(listener: listener);

      expect(service.token, 'ohos_token_xyz_123');
      expect(adapter.methodCallHandler, isNotNull);
    });

    test('init falls back to default mock token on failure', () async {
      adapter.shouldThrowOnGetToken = true;

      await service.init(listener: listener);

      expect(service.token, 'ohos_mock_token_dev');
    });

    test('native onMessageReceived method call dispatches to listener and stream', () async {
      await service.init(listener: listener);

      final receivedList = <PushNotification>[];
      final sub = service.onNotificationReceived.listen(receivedList.add);

      final payload = {
        'id': 'ohos_msg_10',
        'title': 'New Harmony Alert',
        'body': 'Push message body',
        'data': {'type': 'system'},
      };

      await adapter.simulateNativeMethodCall('onMessageReceived', payload);
      await pumpEventQueue();

      expect(listener.received.length, 1);
      expect(listener.received.first.id, 'ohos_msg_10');
      expect(listener.received.first.title, 'New Harmony Alert');
      expect(listener.received.first.body, 'Push message body');
      expect(listener.received.first.data, {'type': 'system'});

      expect(receivedList.length, 1);
      expect(receivedList.first.id, 'ohos_msg_10');

      await sub.cancel();
    });

    test('native onMessageOpenedApp method call dispatches to listener and stream', () async {
      await service.init(listener: listener);

      final openedList = <PushNotification>[];
      final sub = service.onNotificationOpenedApp.listen(openedList.add);

      final payload = {
        'id': 'ohos_opened_20',
        'title': 'Opened Harmony App',
        'body': 'User tapped notification',
        'data': {'deeplink': 'alias://room/123'},
      };

      await adapter.simulateNativeMethodCall('onMessageOpenedApp', payload);
      await pumpEventQueue();

      expect(listener.received, isEmpty);
      expect(listener.openedApp.length, 1);
      expect(listener.openedApp.first.id, 'ohos_opened_20');
      expect(listener.openedApp.first.data, {'deeplink': 'alias://room/123'});

      expect(openedList.length, 1);
      expect(openedList.first.id, 'ohos_opened_20');

      await sub.cancel();
    });

    test('native onTokenRefresh method call updates token and dispatches to listener and stream', () async {
      await service.init(listener: listener);

      final tokenEvents = <String>[];
      final sub = service.onTokenRefresh.listen(tokenEvents.add);

      await adapter.simulateNativeMethodCall('onTokenRefresh', 'new_ohos_token_777');
      await pumpEventQueue();

      expect(service.token, 'new_ohos_token_777');
      expect(listener.tokenRefreshes, contains('new_ohos_token_777'));
      expect(tokenEvents, contains('new_ohos_token_777'));

      await sub.cancel();
    });

    test('initial notification cold start retrieval and dispatchInitialNotification', () async {
      adapter.mockInitialNotification = {
        'id': 'ohos_init_99',
        'title': 'Initial Harmony Push',
        'body': 'Cold start payload',
      };

      await service.init(listener: listener);
      final initial = await service.getInitialNotification();
      expect(initial?.id, 'ohos_init_99');
      expect(initial?.title, 'Initial Harmony Push');

      await service.dispatchInitialNotification();
      await pumpEventQueue();

      expect(listener.openedApp.length, 1);
      expect(listener.openedApp.first.id, 'ohos_init_99');

      // Subsequent dispatch is a no-op
      await service.dispatchInitialNotification();
      await pumpEventQueue();
      expect(listener.openedApp.length, 1);
    });

    test('permission requests and status queries', () async {
      await service.requestNotificationsPermission();
      expect(adapter.requestPermissionCalls, 1);

      adapter.isPermissionGranted = true;
      expect(await service.getPermissionStatus(), PushNotificationPermissionStatus.authorized);

      adapter.isPermissionGranted = false;
      expect(await service.getPermissionStatus(), PushNotificationPermissionStatus.denied);
    });

    test('invalidateDeviceToken invokes deleteToken and clears local token', () async {
      await service.init();
      expect(service.token, isNotNull);

      await service.invalidateDeviceToken();
      expect(service.token, isNull);
      expect(adapter.deleteTokenCalls, 1);
    });

    test('topic subscriptions call adapter', () async {
      await service.subscribeToTopic('updates');
      await service.unsubscribeFromTopic('updates');

      expect(adapter.subscribedTopics, contains('updates'));
      expect(adapter.unsubscribedTopics, contains('updates'));
    });

    test('disableMessagesHandle stops processing native method calls', () async {
      await service.init(listener: listener);
      service.disableMessagesHandle();

      expect(adapter.methodCallHandler, isNull);

      final res = await adapter.simulateNativeMethodCall('onMessageReceived', {'id': 'blocked'});
      expect(res, isNull);
      expect(listener.received, isEmpty);
    });
  });

  group('OhosPushNotification Payload Parsing Tests', () {
    test('parses JSON string encoded data inside map', () {
      final payload = {
        'id': 'ohos_json_1',
        'title': 'Nested JSON',
        'data': '{"key":"value","number":123}',
      };

      final notification = OhosPushNotification.fromPayload(payload);
      expect(notification.id, 'ohos_json_1');
      expect(notification.title, 'Nested JSON');
      expect(notification.data, {'key': 'value', 'number': 123});
    });

    test('parses plain JSON string payload directly', () {
      const jsonStr = '{"id":"raw_str","title":"Raw Title","body":"Raw Body"}';
      final notification = OhosPushNotification.fromPayload(jsonStr);

      expect(notification.id, 'raw_str');
      expect(notification.title, 'Raw Title');
      expect(notification.body, 'Raw Body');
    });

    test('parses null payload safely', () {
      final notification = OhosPushNotification.fromPayload(null);
      expect(notification.id, isEmpty);
      expect(notification.title, isEmpty);
    });
  });
}
