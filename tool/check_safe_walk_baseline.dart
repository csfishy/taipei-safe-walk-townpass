import 'dart:convert';
import 'dart:io';

/// Checks this initialization, not a permanent UI blueprint for M3.
void main(List<String> args) {
  final metadata = jsonDecode(
    File('docs/SAFE_WALK_UPSTREAM.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final base = metadata['commit'] as String;
  final shallow = Process.runSync('git', [
    'rev-parse',
    '--is-shallow-repository',
  ]);
  if (shallow.exitCode != 0 || shallow.stdout.toString().trim() != 'false') {
    stderr.writeln(
      'Full upstream history is required; use checkout fetch-depth: 0.',
    );
    exitCode = 1;
    return;
  }
  final ancestor = Process.runSync('git', [
    'merge-base',
    '--is-ancestor',
    base,
    'HEAD',
  ]);
  if (ancestor.exitCode != 0) {
    stderr.writeln('Official TownPass base is not an ancestor of HEAD.');
    exitCode = 1;
    return;
  }
  final changed = Process.runSync('git', ['diff', '--name-only', base, '--']);
  final untracked = Process.runSync('git', [
    'ls-files',
    '--others',
    '--exclude-standard',
  ]);
  if (changed.exitCode != 0 || untracked.exitCode != 0) {
    stderr.writeln('Cannot inspect current tree.');
    exitCode = 1;
    return;
  }
  final paths = '${changed.stdout}\n${untracked.stdout}'
      .split('\n')
      .where((p) => p.isNotEmpty)
      .toSet();
  final initializing = args.contains('--initialization');
  final failures = <String>[];
  if (initializing) {
    const protected = [
      'LICENSE',
      '.fvmrc',
      'pubspec.yaml',
      'pubspec.lock',
      'analysis_options.yaml',
      'lib/main.dart',
      'lib/page/',
      'lib/util/',
      'lib/service/',
      'assets/',
      'fonts/',
      'ios/',
      'android/',
    ];
    for (final path in paths) {
      if (protected.any(
        (p) => p.endsWith('/') ? path.startsWith(p) : path == p,
      )) {
        failures.add(
          'Initialization changed upstream UI/platform/license/config: $path',
        );
      }
    }
  }
  const featureRoot = 'lib/features/safe_walk/';
  final source = Directory(featureRoot);
  if (!source.existsSync()) {
    failures.add('Safe Walk module root is missing.');
  } else {
    for (final file
        in source
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      final text = file.readAsStringSync();
      final module = path.substring(featureRoot.length).split('/').first;
      for (final match in RegExp(
        r'''(?:import|export)\s+['"]([^'"]+)['"]''',
      ).allMatches(text)) {
        final target = match.group(1)!;
        const prefix = 'package:town_pass/features/safe_walk/';
        if (target.startsWith(prefix)) {
          final other = target.substring(prefix.length).split('/').first;
          if (module != other && other != 'shared') {
            failures.add(
              '$path imports another module implementation: $target',
            );
          }
        } else if (target.startsWith('.')) {
          final resolved = file.absolute.uri.resolve(target).toString();
          final featureUri = source.absolute.uri.toString();
          if (resolved.startsWith(featureUri)) {
            final other = resolved
                .substring(featureUri.length)
                .split('/')
                .first;
            if (module != other && other != 'shared') {
              failures.add(
                '$path imports another module implementation: $target',
              );
            }
          }
        }
      }
      if (initializing &&
          RegExp(
            r'\bextends\s+(?:StatelessWidget|StatefulWidget|Widget)\b|package:flutter/(?:material|widgets|cupertino)\.dart',
          ).hasMatch(text)) {
        failures.add('This initialization must not add new UI: $path');
      }
    }
  }
  if (initializing &&
      Directory('${featureRoot}presentation').existsSync() &&
      Directory('${featureRoot}presentation')
          .listSync(recursive: true)
          .whereType<File>()
          .any((f) => f.path.endsWith('.dart'))) {
    failures.add(
      'Presentation must contain documentation only in this initialization.',
    );
  }
  for (final problem in failures) {
    stderr.writeln(problem);
  }
  if (failures.isNotEmpty) {
    exitCode = 1;
  } else {
    stdout.writeln(
      'TownPass history and Safe Walk module boundaries passed${initializing ? '; official UI/config/license preserved; no new UI' : ''}.',
    );
  }
}
