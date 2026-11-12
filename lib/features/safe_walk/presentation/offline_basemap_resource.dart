import 'package:flutter/widgets.dart';

class OfflineBasemap {
  OfflineBasemap({required this.layer, required this.close});
  final Widget layer;
  final Future<void> Function() close;
}
