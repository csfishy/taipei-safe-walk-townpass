import 'offline_basemap_resource.dart';

Future<OfflineBasemap> loadOfflineBasemap() =>
    Future.error(UnsupportedError('Offline maps require a native platform'));
