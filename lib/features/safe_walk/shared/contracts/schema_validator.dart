import 'dart:convert';

import 'schema_generated.dart';

/// This validator implements only the keywords present in the frozen bundle.
/// It rejects unsupported schema keywords rather than silently ignoring them.
/// It does not verify data provenance, freshness, or whether a road is safe.
final class ContractViolation {
  const ContractViolation(this.path, this.message);
  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Contains field paths and rule descriptions, never the rejected payload.
final class ContractFormatException implements FormatException {
  ContractFormatException(List<ContractViolation> violations)
    : violations = List.unmodifiable(violations);

  final List<ContractViolation> violations;

  @override
  String get message => violations.join('; ');
  @override
  Object? get source => null;
  @override
  int? get offset => null;
  @override
  String toString() => 'Invalid Safe Walk contract: $message';
}

final Map<String, Object?> _bundle = (jsonDecode(safeWalkSchemaJson) as Map)
    .cast<String, Object?>();

List<String> get safeWalkContractNames =>
    List.unmodifiable((_bundle[r'$defs'] as Map).keys.cast<String>());

List<ContractViolation> validateContract(String name, Object? value) {
  if (!safeWalkContractNames.contains(name)) {
    throw ArgumentError.value(name, 'name', 'Unknown Safe Walk contract');
  }
  return List.unmodifiable(_validate(_resolve('#/\$defs/$name'), value, r'$'));
}

Map<String, Object?> validatedContractObject(String name, Object? value) {
  final errors = validateContract(name, value);
  if (errors.isNotEmpty) throw ContractFormatException(errors);
  return _freeze(value) as Map<String, Object?>;
}

/// Generated inline models/union variants point to the same canonical schema.
Map<String, Object?> validatedContractObjectAt(String pointer, Object? value) {
  final errors = _validate(_resolve(pointer), value, r'$');
  if (errors.isNotEmpty) throw ContractFormatException(errors);
  return _freeze(value) as Map<String, Object?>;
}

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, child) => MapEntry(key as String, _freeze(child))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

/// Detached mutable wire data, so callers cannot mutate a parsed model.
Map<String, Object?> copyJsonObject(Map<String, Object?> value) =>
    _copy(value) as Map<String, Object?>;

Object? _copy(Object? value) {
  if (value is Map) {
    return value.map<String, Object?>(
      (key, child) => MapEntry(key as String, _copy(child)),
    );
  }
  if (value is List) return value.map(_copy).toList();
  return value;
}

Map<String, Object?> _resolve(String reference) {
  final prefix = _bundle[r'$id'] as String;
  final pointer = reference.startsWith(prefix)
      ? reference.substring(prefix.length)
      : reference;
  if (!pointer.startsWith('#/')) {
    throw StateError('External schema references are unsupported.');
  }
  Object? current = _bundle;
  for (final encoded in pointer.substring(2).split('/')) {
    final segment = encoded.replaceAll('~1', '/').replaceAll('~0', '~');
    current = current is List
        ? current[int.parse(segment)]
        : (current as Map)[segment];
  }
  if (current is! Map) throw StateError('Invalid schema reference.');
  return current.cast<String, Object?>();
}

const _knownKeywords = {
  r'$schema',
  r'$id',
  r'$comment',
  r'$defs',
  'title',
  'description',
  r'$ref',
  'type',
  'const',
  'enum',
  'oneOf',
  'anyOf',
  'properties',
  'required',
  'additionalProperties',
  'minimum',
  'maximum',
  'minLength',
  'maxLength',
  'format',
  'pattern',
  'items',
  'prefixItems',
  'minItems',
  'maxItems',
  'uniqueItems',
};

List<ContractViolation> _validate(
  Map<String, Object?> schema,
  Object? value,
  String path,
) {
  final unknown = schema.keys.where((key) => !_knownKeywords.contains(key));
  if (unknown.isNotEmpty) {
    throw StateError(
      'Unsupported Safe Walk schema keywords: ${unknown.join(', ')}',
    );
  }
  final errors = <ContractViolation>[];
  void reject(String message) => errors.add(ContractViolation(path, message));

  if (schema[r'$ref'] case final String reference) {
    errors.addAll(_validate(_resolve(reference), value, path));
  }
  if (schema.containsKey('const') && !_jsonEqual(value, schema['const'])) {
    reject('Value does not match the required constant.');
  }
  if (schema['enum'] case final List values) {
    if (!values.any((candidate) => _jsonEqual(candidate, value))) {
      reject('Unknown enumeration value.');
    }
  }
  for (final keyword in ['oneOf', 'anyOf']) {
    if (schema[keyword] case final List branches) {
      final results = branches
          .map(
            (branch) =>
                _validate((branch as Map).cast<String, Object?>(), value, path),
          )
          .toList();
      final passing = results.where((result) => result.isEmpty).length;
      if (keyword == 'oneOf' ? passing != 1 : passing == 0) {
        reject(
          keyword == 'oneOf'
              ? 'Must match exactly one contract variant.'
              : 'Must match one allowed shape or null.',
        );
        // Preserve useful nested paths without including rejected field values.
        if (passing == 0 && results.isNotEmpty) {
          final shortest = results.reduce(
            (a, b) => a.length <= b.length ? a : b,
          );
          errors.addAll(shortest);
        }
      }
    }
  }
  final type = schema['type'];
  final matches = switch (type) {
    null => true,
    'null' => value == null,
    'boolean' => value is bool,
    'string' => value is String,
    'number' => value is num && value.isFinite,
    'integer' =>
      value is num && value.isFinite && value == value.truncateToDouble(),
    'object' => value is Map && value.keys.every((key) => key is String),
    'array' => value is List,
    _ => throw StateError('Unsupported schema type.'),
  };
  if (!matches) {
    reject('Expected a finite JSON $type value.');
    return errors;
  }
  if (value is num) {
    if (!value.isFinite) reject('Numbers must be finite.');
    if (schema['minimum'] case final num limit) {
      if (value < limit) reject('Below the minimum.');
    }
    if (schema['maximum'] case final num limit) {
      if (value > limit) reject('Above the maximum.');
    }
  }
  if (value is String) {
    // JSON Schema lengths count Unicode code points, not UTF-16 code units.
    final length = value.runes.length;
    if (schema['minLength'] case final int limit) {
      if (length < limit) reject('String is too short.');
    }
    if (schema['maxLength'] case final int limit) {
      if (length > limit) reject('String is too long.');
    }
    if (schema['pattern'] case final String pattern) {
      if (!RegExp(pattern).hasMatch(value)) {
        reject('String has an unsupported format.');
      }
    }
    if (schema['format'] case final String format) {
      final valid = switch (format) {
        'date' => _validDate(value),
        'date-time' => _validDateTime(value),
        'uri' => _validUri(value),
        _ => throw StateError('Unsupported schema string format.'),
      };
      if (!valid) reject('Invalid $format.');
    }
  }
  if (value is Map) {
    final properties =
        (schema['properties'] as Map?)?.cast<String, Object?>() ?? {};
    for (final key in (schema['required'] as List?) ?? []) {
      if (!value.containsKey(key)) {
        errors.add(
          ContractViolation('$path.$key', 'Required field is missing.'),
        );
      }
    }
    if (schema['additionalProperties'] == false) {
      for (final key in value.keys.where(
        (key) => !properties.containsKey(key),
      )) {
        errors.add(ContractViolation('$path.$key', 'Unexpected field.'));
      }
    }
    for (final entry in properties.entries) {
      if (value.containsKey(entry.key)) {
        errors.addAll(
          _validate(
            (entry.value as Map).cast<String, Object?>(),
            value[entry.key],
            '$path.${entry.key}',
          ),
        );
      }
    }
  }
  if (value is List) {
    if (schema['minItems'] case final int limit) {
      if (value.length < limit) reject('Array has too few items.');
    }
    if (schema['maxItems'] case final int limit) {
      if (value.length > limit) reject('Array has too many items.');
    }
    if (schema['uniqueItems'] == true) {
      for (var i = 0; i < value.length; i++) {
        if (value.take(i).any((previous) => _jsonEqual(previous, value[i]))) {
          reject('Array items must be unique.');
          break;
        }
      }
    }
    final prefix = (schema['prefixItems'] as List?) ?? [];
    for (var i = 0; i < value.length; i++) {
      final itemSchema = i < prefix.length ? prefix[i] : schema['items'];
      if (itemSchema == false) {
        errors.add(
          ContractViolation(
            '$path[$i]',
            'Additional array items are forbidden.',
          ),
        );
      } else if (itemSchema is Map) {
        errors.addAll(
          _validate(itemSchema.cast<String, Object?>(), value[i], '$path[$i]'),
        );
      } else if (itemSchema != null && itemSchema != true) {
        throw StateError('Unsupported array item schema.');
      }
    }
  }
  return errors;
}

bool _jsonEqual(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _jsonEqual(a[i], b[i]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _jsonEqual(a[key], b[key]));
  }
  return a == b;
}

bool _validDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null || match.end != value.length) return false;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  if (month < 1 || month > 12 || day < 1) return false;
  final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  final days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= days[month - 1];
}

bool _validDateTime(String value) {
  // Format plus schema.pattern require an explicit timezone. Preserve wire text.
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})[Tt\s](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?([Zz]|([+-])(\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (match == null || match.end != value.length || !_validDate(match[1]!)) {
    return false;
  }
  final hour = int.parse(match[2]!);
  final minute = int.parse(match[3]!);
  final second = int.parse(match[4]!);
  final offsetHour = int.tryParse(match[7] ?? '0') ?? 0;
  final offsetMinute = int.tryParse(match[8] ?? '0') ?? 0;
  if (hour > 23 ||
      minute > 59 ||
      second > 60 ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    return false;
  }
  if (second < 60) return true;
  // Match RFC3339 leap-second placement after converting the offset to UTC.
  final direction = match[6] == '-' ? -1 : 1;
  final utcMinutes =
      (hour * 60 + minute - direction * (offsetHour * 60 + offsetMinute)) %
      1440;
  return utcMinutes == 1439;
}

bool _validUri(String value) {
  // The original AJV format is URI (RFC3986), not IRI; percent-encode Unicode.
  if (RegExp(r'[^\x21-\x7E]').hasMatch(value)) return false;
  if (RegExp(r'[\x00-\x20<>"{}|\\^`]').hasMatch(value)) return false;
  if (RegExp(r'%(?![0-9A-Fa-f]{2})').hasMatch(value)) return false;
  final uri = Uri.tryParse(value);
  return uri != null && uri.hasScheme;
}
