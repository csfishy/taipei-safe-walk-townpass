// Zero-dependency generator for this contract bundle, not a general schema SDK.
import 'dart:convert';
import 'dart:io';

const _schemaPath = 'schemas/safe_walk/v1/contracts.schema.json';
const _schemaTarget =
    'lib/features/safe_walk/shared/contracts/schema_generated.dart';
const _modelsTarget =
    'lib/features/safe_walk/shared/models/safe_walk_models_generated.dart';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent;
  final source = await File('${root.path}/$_schemaPath').readAsString();
  if (source.contains("'''")) {
    throw StateError('Schema raw-string delimiter needs an explicit update.');
  }
  final schema = (jsonDecode(source) as Map).cast<String, Object?>();
  final generated = _ModelGenerator(schema).generate();
  final outputs = {
    _schemaTarget:
        '// GENERATED from $_schemaPath. DO NOT EDIT.\n'
        "const String safeWalkSchemaJson = r'''$source''';\n",
    _modelsTarget: generated,
  };
  // Formatting is deterministic with the project's Dart SDK. No packages needed.
  var different = false;
  for (final entry in outputs.entries) {
    final formatProcess = await Process.start(Platform.resolvedExecutable, [
      'format',
      '--output=show',
      '--summary=none',
    ]);
    final stdoutFuture = formatProcess.stdout.transform(utf8.decoder).join();
    final stderrFuture = formatProcess.stderr.transform(utf8.decoder).join();
    formatProcess.stdin.write(entry.value);
    await formatProcess.stdin.close();
    final code = await formatProcess.exitCode;
    final formatted = await stdoutFuture;
    final errors = await stderrFuture;
    if (code != 0) throw StateError('Generated Dart is invalid: $errors');
    final file = File('${root.path}/${entry.key}');
    if (arguments.contains('--check')) {
      if (!await file.exists() || await file.readAsString() != formatted) {
        stderr.writeln('Out of sync: ${entry.key}');
        different = true;
      }
    } else {
      await file.parent.create(recursive: true);
      await file.writeAsString(formatted);
      stdout.writeln('Generated ${entry.key}');
    }
  }
  if (different) exitCode = 1;
  if (arguments.contains('--check') && !different) {
    stdout.writeln('Safe Walk schema and Dart models are in sync.');
  }
}

typedef _Schema = Map<String, Object?>;

final class _ModelGenerator {
  _ModelGenerator(this.bundle);

  final _Schema bundle;
  final _enums = <String, List<String>>{};
  final _nested = <String, ({_Schema schema, String pointer})>{};
  final _classes = StringBuffer();

  static const _variants = {
    'LocationResult': ['LocationSuccess', 'LocationFailure'],
    'Recognition': ['ConfirmedRecognition', 'UnconfirmedRecognition'],
    'RouteResult': ['RouteSuccess', 'RouteFailure'],
    'AppEvent': [
      'LocationUpdatedEvent',
      'RouteCompletedEvent',
      'EmergencyOpenedEvent',
      'CompanionChangedEvent',
    ],
  };

  String generate() {
    final definitions = (bundle[r'$defs'] as Map).cast<String, Object?>();
    for (final entry in definitions.entries) {
      final schema = _map(entry.value);
      if (schema.containsKey('oneOf')) {
        _union(entry.key, schema);
      } else {
        _object(entry.key, schema, '#/\$defs/${entry.key}');
      }
    }
    // Inline objects are also generated from their original schema pointers.
    var index = 0;
    while (index < _nested.length) {
      final name = _nested.keys.elementAt(index++);
      final nested = _nested[name]!;
      _object(name, nested.schema, nested.pointer);
    }
    final result = StringBuffer('''
// GENERATED from $_schemaPath. DO NOT EDIT.
// Runtime validation is mandatory; constructors and fromJson both validate.
import '../contracts/schema_validator.dart';

/// GeoJSON wire order is [longitude, latitude], unlike named lat/lng objects.
typedef GeoJsonCoordinate = ({double longitude, double latitude});

abstract class SafeWalkModel {
  const SafeWalkModel._(this._json);
  final Map<String, Object?> _json;
  Map<String, Object?> toJson() => copyJsonObject(_json);
}

GeoJsonCoordinate _geoJsonCoordinate(Object? value) {
  final tuple = value as List<Object?>;
  return (longitude: (tuple[0] as num).toDouble(), latitude: (tuple[1] as num).toDouble());
}
''');
    for (final entry in _enums.entries) {
      result.writeln(_enum(entry.key, entry.value));
    }
    final stopReasons = ['user', 'emergency', 'unmount', 'visibility_hidden'];
    if (!stopReasons.every(_enums['CompanionReason']!.contains)) {
      throw StateError('Companion stop reasons need a schema migration.');
    }
    result.writeln(_enum('CompanionStopReason', stopReasons));
    result.write(_classes);
    return result.toString();
  }

  void _union(String name, _Schema schema) {
    final cases = (schema['oneOf'] as List).map(_map).toList();
    final names = _variants[name];
    if (names == null || names.length != cases.length) {
      throw StateError('Union $name needs explicit public variant names.');
    }
    final discriminator = name == 'AppEvent' ? 'type' : 'status';
    final common = <String, Object?>{};
    final firstProperties = _map(cases.first['properties']);
    for (final property in firstProperties.entries) {
      if (cases.every(
        (c) =>
            jsonEncode(_map(c['properties'])[property.key]) ==
            jsonEncode(property.value),
      )) {
        common[property.key] = property.value;
      }
    }
    _classes.writeln('sealed class $name extends SafeWalkModel {');
    _classes.writeln('$name._(super.json) : super._();');
    _classes.writeln('factory $name.fromJson(Object? value) {');
    _classes.writeln("final json = validatedContractObject('$name', value);");
    _classes.writeln("return switch (json['$discriminator']) {");
    for (var i = 0; i < cases.length; i++) {
      final tag = _map(_map(cases[i]['properties'])[discriminator]);
      final values = tag.containsKey('const')
          ? [tag['const']]
          : tag['enum'] as List;
      final patterns = values.map(_literal).join(' || ');
      _classes.writeln('$patterns => ${names[i]}._(json),');
    }
    _classes.writeln(
      "_ => throw StateError('Validated $name has no variant'),\n};\n}",
    );
    for (final property in common.entries) {
      _getter(property.key, _map(property.value), name);
    }
    _classes.writeln('}');
    for (var i = 0; i < cases.length; i++) {
      _object(
        names[i],
        cases[i],
        '#/\$defs/$name/oneOf/$i',
        base: name,
        inherited: common.keys.toSet(),
      );
    }
  }

  void _object(
    String name,
    _Schema schema,
    String pointer, {
    String base = 'SafeWalkModel',
    Set<String> inherited = const {},
  }) {
    final properties = _map(schema['properties']);
    final required = (schema['required'] as List).cast<String>().toSet();
    if (schema['additionalProperties'] != false ||
        !required.containsAll(properties.keys) ||
        required.length != properties.length) {
      throw StateError(
        '$name: optional/additional fields require an explicit migration.',
      );
    }
    // Discover nested/enum types before writing declarations.
    for (final property in properties.entries) {
      _type(
        _map(property.value),
        '$name.${property.key}',
        '$pointer/properties/${property.key}',
      );
    }
    _classes.writeln('final class $name extends $base {');
    _classes.writeln('$name._(super.json) : super._();');
    _classes.writeln('factory $name.fromJson(Object? value) => $name._(');
    _classes.writeln(
      'validatedContractObjectAt(${_literal(pointer)}, value));',
    );
    _classes.writeln('factory $name({');
    for (final property in properties.entries) {
      final s = _map(property.value);
      if (_fixed(s)) continue;
      _classes.writeln(
        'required ${_type(s, '$name.${property.key}', '$pointer/properties/${property.key}')} ${property.key},',
      );
    }
    _classes.writeln('}) => $name.fromJson({');
    for (final property in properties.entries) {
      final s = _map(property.value);
      _classes.writeln(
        "'${property.key}': ${_encode(s, property.key, '$name.${property.key}')},",
      );
    }
    _classes.writeln('});');
    for (final property in properties.entries) {
      if (!inherited.contains(property.key)) {
        _getter(property.key, _map(property.value), name);
      }
    }
    _classes.writeln('}');
  }

  void _getter(String key, _Schema schema, String owner) {
    final context = '$owner.$key';
    final type = _type(schema, context, '');
    _classes.writeln(
      '$type get $key => ${_decode(schema, "_json['$key']", context)};',
    );
  }

  bool _fixed(_Schema s) =>
      s.containsKey('const') || s['type'] == 'null' || s['maxItems'] == 0;

  _Schema? _nullable(_Schema s) {
    if (s['anyOf'] case final List choices) {
      if (choices.length == 2 &&
          choices.any((x) => _map(x)['type'] == 'null')) {
        return _map(choices.firstWhere((x) => _map(x)['type'] != 'null'));
      }
      throw StateError('Only explicit nullable anyOf is used by this bundle.');
    }
    return null;
  }

  String _type(_Schema s, String context, String pointer) {
    final nullable = _nullable(s);
    if (nullable != null) return '${_type(nullable, context, pointer)}?';
    if (s[r'$ref'] case final String ref) return ref.split('/').last;
    if (s['enum'] case final List values) {
      final name = _enumName(context);
      final strings = values.cast<String>();
      if (_enums.containsKey(name) &&
          jsonEncode(_enums[name]) != jsonEncode(strings)) {
        throw StateError('Conflicting enum alias $name');
      }
      _enums[name] = strings;
      return name;
    }
    switch (s['type']) {
      case 'string':
        return 'String';
      case 'number':
        return 'double';
      case 'integer':
        return 'int';
      case 'boolean':
        return 'bool';
      case 'null':
        return 'Null';
      case 'object':
        final name = context == 'CompanionScenario.steps.item'
            ? 'CompanionStep'
            : context == 'EmergencyOpenedEvent.payload'
            ? 'EmergencyOpenedPayload'
            : context.replaceAll('.', '');
        _nested.putIfAbsent(name, () => (schema: s, pointer: pointer));
        return name;
      case 'array':
        if (s['maxItems'] == 0) return 'List<Never>';
        if (s.containsKey('prefixItems')) {
          final prefix = (s['prefixItems'] as List).map(_map).toList();
          if (prefix.length != 2 ||
              prefix[0]['minimum'] != -180 ||
              prefix[1]['minimum'] != -90 ||
              s['items'] != false) {
            throw StateError(
              'GeoJSON tuple schema changed; review coordinate mapping.',
            );
          }
          return 'GeoJsonCoordinate';
        }
        return 'List<${_type(_map(s['items']), '$context.item', '$pointer/items')}>';
      default:
        throw StateError('Unsupported generated type: $context $s');
    }
  }

  String _decode(_Schema s, String value, String context) {
    final nullable = _nullable(s);
    if (nullable != null) {
      return '$value == null ? null : ${_decode(nullable, value, context)}';
    }
    if (s[r'$ref'] case final String ref) {
      return '${ref.split('/').last}.fromJson($value)';
    }
    if (s.containsKey('enum')) {
      return '${_enumName(context)}.fromWire($value as String)';
    }
    switch (s['type']) {
      case 'number':
        return '($value as num).toDouble()';
      case 'integer':
        return '($value as num).toInt()';
      case 'string':
        return '$value as String';
      case 'boolean':
        return '$value as bool';
      case 'null':
        return 'null';
      case 'object':
        return '${_type(s, context, '')}.fromJson($value)';
      case 'array':
        if (s['maxItems'] == 0) return 'const <Never>[]';
        if (s.containsKey('prefixItems')) return '_geoJsonCoordinate($value)';
        final item = _map(s['items']);
        return 'List<${_type(item, '$context.item', '')}>.unmodifiable(($value as List<Object?>).map((item) => ${_decode(item, 'item', '$context.item')}))';
      default:
        throw StateError('Cannot decode $context');
    }
  }

  String _encode(_Schema s, String value, String context) {
    if (s.containsKey('const')) return _literal(s['const']);
    if (s['type'] == 'null') return 'null';
    if (s['maxItems'] == 0) return '<Object?>[]';
    final nullable = _nullable(s);
    if (nullable != null) {
      if (nullable.containsKey(r'$ref') || nullable['type'] == 'object') {
        return '$value?.toJson()';
      }
      if (nullable.containsKey('enum')) return '$value?.wireValue';
      if (nullable['type'] != 'array') return value;
      return '$value == null ? null : ${_encode(nullable, value, context)}';
    }
    if (s.containsKey(r'$ref') || s['type'] == 'object') {
      return '$value.toJson()';
    }
    if (s.containsKey('enum')) return '$value.wireValue';
    if (s['type'] == 'array') {
      if (s.containsKey('prefixItems')) {
        return '[$value.longitude, $value.latitude]';
      }
      return '$value.map((item) => ${_encode(_map(s['items']), 'item', '$context.item')}).toList(growable: false)';
    }
    return value;
  }

  String _enumName(String context) => switch (context) {
    'Position.source' => 'PositionSource',
    'LocationFailure.status' => 'LocationFailureStatus',
    'SourceMetadata.dataMode' ||
    'RouteRequest.mode' ||
    'RouteResult.mode' ||
    'RouteSuccess.mode' ||
    'RouteFailure.mode' ||
    'IncidentSummary.mode' => 'DataMode',
    'UnconfirmedRecognition.status' => 'UnconfirmedRecognitionStatus',
    'AssistancePoint.kind' => 'AssistancePointKind',
    'AssistancePoint.availability' => 'OpeningStatus',
    'AssistancePoint.capabilities.item' => 'AssistanceCapability',
    'AreaStatistics.aggregation' => 'StatisticsAggregation',
    'RouteRequest.preference' || 'RouteCandidate.kind' => 'RouteKind',
    'RouteFailure.status' => 'RouteFailureStatus',
    'IncidentSummary.category' => 'IncidentCategory',
    'IncidentSummary.transferState' => 'IncidentTransferState',
    'EmergencyActionResult.channel' => 'EmergencyChannel',
    'EmergencyActionResult.action' => 'EmergencyAction',
    'CompanionEvent.state' => 'CompanionState',
    'CompanionEvent.reason' => 'CompanionReason',
    'EmergencyOpenedPayload.reason' => 'EmergencyOpenedReason',
    _ => throw StateError('Name the public enum explicitly: $context'),
  };

  String _enum(String name, List<String> values) {
    final out = StringBuffer('enum $name {\n');
    for (var i = 0; i < values.length; i++) {
      out.writeln(
        '${_identifier(values[i])}(${_literal(values[i])})${i == values.length - 1 ? ';' : ','}',
      );
    }
    out.writeln('const $name(this.wireValue);\nfinal String wireValue;');
    out.writeln(
      'static $name fromWire(String value) => values.firstWhere((item) => item.wireValue == value,',
    );
    out.writeln(
      "orElse: () => throw FormatException('Unknown $name wire value'));\n}",
    );
    return out.toString();
  }

  String _identifier(String value) {
    if (value == '110') return 'police';
    if (value == '119') return 'fire';
    final pieces = value.split('_');
    return pieces.first +
        pieces.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }

  _Schema _map(Object? value) => (value as Map).cast<String, Object?>();
  String _literal(Object? value) => jsonEncode(value).replaceAll(r'$', r'\$');
}
