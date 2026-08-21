part of '../push_ohos.dart';

var _log = Logger();

/// HarmonyOS NEXT Push Service implementation (HarmonyOS Push Kit).
class OhosPushServiceImpl extends PushService {
  final _lock = Lock();
  static const MethodChannel _channel = MethodChannel('com.kadmiv.alias/ohos_push');

  NotificationsListener? _listener;
  String? _token;

  @override
  String? get token => _token;

  @override
  Future<void> init({NotificationsListener? listener}) async {
    _listener = listener;
    return _lock.synchronized(() async {
      _log.i('OhosPushServiceImpl: initializing HarmonyOS Push Kit');
      try {
        _token = await _channel.invokeMethod<String>('getPushToken') ?? 'ohos_mock_token_dev';
      } on MissingPluginException {
        _token = 'ohos_mock_token_dev';
      } catch (e) {
        _log.w('OhosPushServiceImpl: getPushToken failed: $e');
        _token = 'ohos_mock_token_dev';
      }
      _log.i('OhosPushServiceImpl: push token registered: $_token');
    });
  }

  @override
  Future<void> requestNotificationsPermission() async {
    _log.i('OhosPushServiceImpl: requestNotificationsPermission');
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  @override
  Future<void> invalidateDeviceToken() async {
    _token = null;
    _log.i('OhosPushServiceImpl: invalidateDeviceToken');
  }

  @override
  Future<void> dispatchInitialNotification() async {
    _log.i('OhosPushServiceImpl: dispatchInitialNotification');
  }

  @override
  void disableMessagesHandle() {
    _log.i('OhosPushServiceImpl: disableMessagesHandle');
  }
}
