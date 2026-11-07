// M3 設計預覽入口：只在本機看畫面用，不接官方路由、不取 GPS、不撥號。
// 執行：flutter run -d web-server -t lib/features/safe_walk/presentation/preview/safe_walk_preview_main.dart
import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/util/tp_colors.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '臺北安心行 M3 預覽',
    theme: ThemeData(fontFamily: 'PingFangTC', colorSchemeSeed: TPColors.primary500, scaffoldBackgroundColor: TPColors.grayscale50),
    home: SafeWalkFlow(speaker: PreviewSpeaker()),
  ),
);
