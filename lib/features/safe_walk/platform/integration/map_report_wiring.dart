import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/web_rpc_post.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/map_reports/map_report_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Composes public-key RPC persistence with presentation at the module boundary.
/// Configuration never opens a connection or reads the device position.
final class MapReportWiring {
  const MapReportWiring(this.repository);

  factory MapReportWiring.fromEnvironment({
    Map<String, String>? environment,
    SupabaseRpcClient Function(SafeWalkSupabaseConfig)? createClient,
  }) {
    final SafeWalkSupabaseConfig config;
    try {
      config = SafeWalkSupabaseConfig.fromEnvironment(environment: environment);
    } on SupabaseConfigurationException {
      return const MapReportWiring(MapReportRepository(transport: null));
    }
    if (kIsWeb) {
      const webEnabled = bool.fromEnvironment('SAFE_WALK_WEB_ROUTES');
      if (!webEnabled) {
        return const MapReportWiring(MapReportRepository(transport: null));
      }
      return MapReportWiring(
        MapReportRepository(
          transport: (function, arguments, {cancellation}) async {
            final (status, body) = await webRpcPost(
              config.url.resolve('/rest/v1/rpc/$function'),
              {
                ...config.requestHeaders,
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              jsonEncode(arguments),
              cancellation: cancellation,
            );
            return MapReportHttpResponse(status, body);
          },
        ),
      );
    }
    final client =
        createClient?.call(config) ?? SupabaseRpcClient(config: config);
    return MapReportWiring(
      MapReportRepository(
        transport: (function, arguments, {cancellation}) async {
          final response = await client.call(
            function,
            arguments,
            cancellation: cancellation,
          );
          return MapReportHttpResponse(response.statusCode, response.body);
        },
      ),
    );
  }

  final MapReportRepository repository;

  Future<Anomaly> save(
    Anomaly draft, {
    SafeWalkCancellation? cancellation,
  }) async {
    final report = await repository.submit(
      mode: sw.DataMode.live,
      requestId: draft.id,
      category: draft.category.name,
      latitude: draft.at.lat,
      longitude: draft.at.lng,
      description: draft.updates.join('\n'),
      cancellation: cancellation,
    );
    return _anomaly(report);
  }

  /// Read every bounded page; never silently omit later reports from avoidance.
  Future<List<Anomaly>> load({SafeWalkCancellation? cancellation}) async {
    final reports = <String, Anomaly>{};
    var offset = 0;
    while (true) {
      cancellation?.throwIfCancelled();
      final page = await repository.query(
        mode: sw.DataMode.live,
        offset: offset,
        cancellation: cancellation,
      );
      for (final report in page.records) {
        reports[report.id] = _anomaly(report);
      }
      if (!page.hasMore) return reports.values.toList();
      offset += page.limit;
      if (offset > mapReportMaxOffset) {
        throw const MapReportException(MapReportFailure.serverUnavailable);
      }
    }
  }

  static Anomaly _anomaly(MapReportRecord report) => Anomaly(
    id: report.id,
    category: AnomalyCategory.values.byName(report.category),
    at: LatLng(report.latitude, report.longitude),
    firstReportedAt: report.reportedAt.toLocal(),
    reportCount: 1,
    status: AnomalyStatus.pending,
    updates: [if (report.description.isNotEmpty) report.description],
    mode: sw.DataMode.live,
  );
}
