import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class OfflineBasemap {
  factory OfflineBasemap({
    required Widget layer,
    required Future<void> Function() close,
    ValueListenable<bool>? unavailable,
  }) => OfflineBasemap._(layer, close, unavailable);
  OfflineBasemap._(this.layer, this._close, this.unavailable);
  final Widget layer;
  final ValueListenable<bool>? unavailable;
  final Future<void> Function() _close;
  Future<void>? _closing;
  Future<void> close() => _closing ??= Future.sync(_close);
}
