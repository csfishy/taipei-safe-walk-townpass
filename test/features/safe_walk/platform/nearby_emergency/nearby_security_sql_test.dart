import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source containment guard only: this does not execute SQL or prove remote ACLs.
void main() {
  final source = File('supabase/nearby_emergency.sql').readAsStringSync();
  final sql = source.replaceAll(RegExp(r'--[^\r\n]*'), '').toLowerCase();

  test('nearby containment cannot provision RPCs or mutate stored data', () {
    expect(
      RegExp(r'\b(create|alter|drop|truncate|insert|update|delete|grant)\b')
          .hasMatch(sql),
      isFalse,
      reason: 'Retiring anonymous RPCs must only remove access.',
    );
    expect(sql, isNot(contains('crime_reference')));
    expect(sql, isNot(contains('safe_walk_demo')));
  });

  test('containment scope is the three exact legacy RPC signatures', () {
    final signatures = RegExp(r"'public\.[^']+'")
        .allMatches(sql)
        .map((match) => match.group(0))
        .toSet();
    expect(signatures, {
      "'public.set_helper_opt_in(uuid,boolean,double precision,double precision)'",
      "'public.send_emergency_alert(uuid,double precision,double precision,integer)'",
      "'public.fetch_pending_alerts(uuid)'",
    });
    expect(sql, contains('to_regprocedure(legacy_signature)'));
    expect(sql, contains('if legacy_function is null then'));
  });

  test('all legacy API roles lose access and inherited access is rejected', () {
    expect(sql, contains('revoke all privileges on function %s from public'));
    expect(sql, contains('revoke all privileges on function %s from %i'));
    expect(sql, contains("array['anon', 'authenticated', 'service_role']"));
    expect(
      sql,
      contains("has_function_privilege(api_role, legacy_function, 'execute')"),
    );
    expect(sql, contains('raise exception'));
    expect(sql.trim(), startsWith('begin;'));
    expect(sql.trim(), endsWith('commit;'));
  });
}
