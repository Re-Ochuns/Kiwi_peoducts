import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

abstract class TodoNotificationRepository {
  Future<bool> canNotify();
  Future<String> notify(String requestId);
}

class SupabaseTodoNotificationRepository implements TodoNotificationRepository {
  SupabaseTodoNotificationRepository(this.client);
  final SupabaseClient client;
  @override
  Future<bool> canNotify() async {
    final id = client.auth.currentUser?.id;
    if (id == null) return false;
    final rows = await client
        .from('user_roles')
        .select('role')
        .eq('user_id', id)
        .eq('role', 'administrator')
        .timeout(const Duration(seconds: 10));
    return rows.isNotEmpty;
  }

  @override
  Future<String> notify(String requestId) async {
    try {
      final response = await client.functions
          .invoke(
            'todo-notify',
            body: {'mode': 'manual', 'request_id': requestId},
          )
          .timeout(const Duration(seconds: 25));
      final data = Map<String, dynamic>.from(response.data as Map);
      return data['status'] as String? ?? 'unknown';
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] == 'CONFIG_MISSING') {
        return 'not_configured';
      }
      if (e.status == 403 || e.status == 401) return 'forbidden';
      if (e.status == 429) return 'rate_limited';
      if (details is Map && details['status'] == 'failed') return 'failed';
      return 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }
}
