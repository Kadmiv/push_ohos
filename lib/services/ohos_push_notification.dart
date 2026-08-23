import 'dart:convert';
import 'package:push_core/push_core.dart';

/// Concrete [PushNotification] representing an OpenHarmony / HarmonyOS NEXT payload.
class OhosPushNotification extends PushNotification {
  const OhosPushNotification({
    super.id,
    super.title,
    super.body,
    super.data,
    super.sentTime,
    super.category,
    super.imageUrl,
    this.rawPayload,
  });

  /// Creates an [OhosPushNotification] from a native Map payload.
  factory OhosPushNotification.fromPayload(dynamic raw) {
    if (raw == null) {
      return const OhosPushNotification();
    }

    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final id = map['id']?.toString() ??
          map['messageId']?.toString() ??
          map['msgId']?.toString() ??
          '';
      final title = map['title']?.toString() ?? '';
      final body = map['body']?.toString() ?? '';

      var data = <String, dynamic>{};
      if (map['data'] is Map) {
        data = Map<String, dynamic>.from(map['data'] as Map);
      } else if (map['data'] is String) {
        try {
          final decoded = jsonDecode(map['data'] as String);
          if (decoded is Map) {
            data = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      } else {
        data = map;
      }

      final sentTime = map['sentTime'] != null
          ? (map['sentTime'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['sentTime'] as int)
              : DateTime.tryParse(map['sentTime'].toString()))
          : null;

      return OhosPushNotification(
        id: id,
        title: title,
        body: body,
        data: data,
        sentTime: sentTime,
        category: map['category']?.toString(),
        imageUrl: map['imageUrl']?.toString(),
        rawPayload: raw,
      );
    }

    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return OhosPushNotification.fromPayload(decoded);
        }
      } catch (_) {}
      return OhosPushNotification(body: raw, rawPayload: raw);
    }

    return const OhosPushNotification();
  }

  /// Underlying raw payload from the platform channel.
  final dynamic rawPayload;
}
