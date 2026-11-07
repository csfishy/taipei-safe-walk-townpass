// GENERATED from schemas/safe_walk/v1/contracts.schema.json. DO NOT EDIT.
const String safeWalkSchemaJson = r'''{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "urn:taipei-safe-walk:contracts:1.0.0",
  "title": "Taipei Safe Walk inter-module contracts v1.0.0",
  "$comment": "Single source of truth. No real user locations or government integrations are included.",
  "$defs": {
    "Coordinates": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "lat": {
          "type": "number",
          "minimum": -90,
          "maximum": 90
        },
        "lng": {
          "type": "number",
          "minimum": -180,
          "maximum": 180
        }
      },
      "required": [
        "lat",
        "lng"
      ],
      "description": "WGS84/EPSG:4326; internal order is named lat/lng, GeoJSON uses [lng,lat]."
    },
    "Position": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "schemaVersion": {
          "const": "1.0.0",
          "type": "string"
        },
        "coordinates": {
          "$ref": "#/$defs/Coordinates"
        },
        "source": {
          "type": "string",
          "enum": [
            "gps",
            "manual",
            "mock"
          ]
        },
        "accuracyMeters": {
          "anyOf": [
            {
              "type": "number",
              "minimum": 0
            },
            {
              "type": "null"
            }
          ]
        },
        "observedAt": {
          "anyOf": [
            {
              "type": "string",
              "format": "date-time",
              "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
            },
            {
              "type": "null"
            }
          ]
        }
      },
      "required": [
        "schemaVersion",
        "coordinates",
        "source",
        "accuracyMeters",
        "observedAt"
      ],
      "description": "GPS requires accuracy and observation time; manual coordinates are not a fresh GPS fix."
    },
    "LocationResult": {
      "oneOf": [
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "status": {
              "const": "ok",
              "type": "string"
            },
            "position": {
              "$ref": "#/$defs/Position"
            }
          },
          "required": [
            "status",
            "position"
          ]
        },
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "status": {
              "type": "string",
              "enum": [
                "denied",
                "timeout",
                "unavailable",
                "unsupported"
              ]
            },
            "message": {
              "type": "string",
              "minLength": 1,
              "maxLength": 500
            }
          },
          "required": [
            "status",
            "message"
          ]
        }
      ]
    },
    "SourceMetadata": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "datasetId": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "title": {
          "type": "string",
          "minLength": 1,
          "maxLength": 250
        },
        "dataMode": {
          "type": "string",
          "enum": [
            "mock",
            "live"
          ]
        },
        "sourceUrl": {
          "anyOf": [
            {
              "type": "string",
              "format": "uri",
              "pattern": "^https://",
              "maxLength": 2048
            },
            {
              "type": "null"
            }
          ]
        },
        "retrievedAt": {
          "type": "string",
          "format": "date-time",
          "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
        },
        "dataUpdatedAt": {
          "anyOf": [
            {
              "type": "string",
              "format": "date-time",
              "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
            },
            {
              "type": "null"
            }
          ]
        },
        "license": {
          "anyOf": [
            {
              "type": "string",
              "minLength": 1,
              "maxLength": 300
            },
            {
              "type": "null"
            }
          ]
        },
        "coverage": {
          "type": "string",
          "minLength": 1,
          "maxLength": 500
        },
        "limitations": {
          "type": "array",
          "items": {
            "type": "string",
            "minLength": 1,
            "maxLength": 500
          },
          "minItems": 1,
          "maxItems": 30
        }
      },
      "required": [
        "datasetId",
        "title",
        "dataMode",
        "sourceUrl",
        "retrievedAt",
        "dataUpdatedAt",
        "license",
        "coverage",
        "limitations"
      ],
      "description": "live sources require a real URL; retrievedAt is not the source publication/update time."
    },
    "Recognition": {
      "oneOf": [
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "status": {
              "const": "confirmed",
              "type": "string"
            },
            "evidenceUrl": {
              "type": "string",
              "format": "uri",
              "pattern": "^https://",
              "maxLength": 2048
            },
            "checkedAt": {
              "type": "string",
              "format": "date-time",
              "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
            }
          },
          "required": [
            "status",
            "evidenceUrl",
            "checkedAt"
          ]
        },
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "status": {
              "type": "string",
              "enum": [
                "unconfirmed",
                "not_applicable"
              ]
            },
            "evidenceUrl": {
              "type": "null"
            },
            "checkedAt": {
              "anyOf": [
                {
                  "type": "string",
                  "format": "date-time",
                  "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
                },
                {
                  "type": "null"
                }
              ]
            }
          },
          "required": [
            "status",
            "evidenceUrl",
            "checkedAt"
          ]
        }
      ]
    },
    "AssistancePoint": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "schemaVersion": {
          "const": "1.0.0",
          "type": "string"
        },
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "name": {
          "type": "string",
          "minLength": 1,
          "maxLength": 200
        },
        "kind": {
          "type": "string",
          "enum": [
            "police",
            "partner_store",
            "convenience_store",
            "public_facility"
          ]
        },
        "coordinates": {
          "$ref": "#/$defs/Coordinates"
        },
        "address": {
          "anyOf": [
            {
              "type": "string",
              "minLength": 1,
              "maxLength": 400
            },
            {
              "type": "null"
            }
          ]
        },
        "publicPhone": {
          "anyOf": [
            {
              "type": "string",
              "minLength": 1,
              "maxLength": 50
            },
            {
              "type": "null"
            }
          ]
        },
        "recognition": {
          "$ref": "#/$defs/Recognition"
        },
        "availability": {
          "type": "string",
          "enum": [
            "open",
            "closed",
            "unknown"
          ]
        },
        "availabilityCheckedAt": {
          "anyOf": [
            {
              "type": "string",
              "format": "date-time",
              "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
            },
            {
              "type": "null"
            }
          ]
        },
        "capabilities": {
          "type": "array",
          "items": {
            "type": "string",
            "enum": [
              "contact_assistance",
              "indoor_waiting",
              "unknown"
            ]
          },
          "minItems": 1,
          "maxItems": 3
        },
        "source": {
          "$ref": "#/$defs/SourceMetadata"
        }
      },
      "required": [
        "schemaVersion",
        "id",
        "name",
        "kind",
        "coordinates",
        "address",
        "publicPhone",
        "recognition",
        "availability",
        "availabilityCheckedAt",
        "capabilities",
        "source"
      ],
      "description": "A location is not a guarantee of safety, staffing, current opening or acceptance of a request."
    },
    "AreaStatistics": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "schemaVersion": {
          "const": "1.0.0",
          "type": "string"
        },
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "city": {
          "const": "臺北市",
          "type": "string"
        },
        "district": {
          "type": "string",
          "minLength": 1,
          "maxLength": 80
        },
        "geographicLevel": {
          "const": "district",
          "type": "string"
        },
        "periodStart": {
          "type": "string",
          "format": "date"
        },
        "periodEnd": {
          "type": "string",
          "format": "date"
        },
        "aggregation": {
          "type": "string",
          "enum": [
            "month",
            "year"
          ]
        },
        "category": {
          "type": "string",
          "minLength": 1,
          "maxLength": 150
        },
        "caseCount": {
          "type": "integer",
          "minimum": 0
        },
        "populationDenominator": {
          "anyOf": [
            {
              "type": "integer",
              "minimum": 1
            },
            {
              "type": "null"
            }
          ]
        },
        "ratePer100k": {
          "anyOf": [
            {
              "type": "number",
              "minimum": 0
            },
            {
              "type": "null"
            }
          ]
        },
        "source": {
          "$ref": "#/$defs/SourceMetadata"
        }
      },
      "required": [
        "schemaVersion",
        "id",
        "city",
        "district",
        "geographicLevel",
        "periodStart",
        "periodEnd",
        "aggregation",
        "category",
        "caseCount",
        "populationDenominator",
        "ratePer100k",
        "source"
      ],
      "description": "District history only. Not a street-level, hourly, individual or real-time risk score."
    },
    "RouteRequest": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "schemaVersion": {
          "const": "1.0.0",
          "type": "string"
        },
        "requestId": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "mode": {
          "type": "string",
          "enum": [
            "mock",
            "live"
          ]
        },
        "origin": {
          "$ref": "#/$defs/Position"
        },
        "destination": {
          "$ref": "#/$defs/Coordinates"
        },
        "departAt": {
          "type": "string",
          "format": "date-time",
          "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
        },
        "preference": {
          "type": "string",
          "enum": [
            "direct",
            "via_assistance"
          ]
        },
        "maxExtraDistanceMeters": {
          "type": "integer",
          "minimum": 0,
          "maximum": 5000
        },
        "assistancePointIds": {
          "type": "array",
          "items": {
            "type": "string",
            "minLength": 1,
            "maxLength": 120
          },
          "minItems": 0,
          "maxItems": 5,
          "uniqueItems": true
        }
      },
      "required": [
        "schemaVersion",
        "requestId",
        "mode",
        "origin",
        "destination",
        "departAt",
        "preference",
        "maxExtraDistanceMeters",
        "assistancePointIds"
      ]
    },
    "LineString": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "type": {
          "const": "LineString",
          "type": "string"
        },
        "coordinates": {
          "type": "array",
          "minItems": 2,
          "maxItems": 20000,
          "items": {
            "type": "array",
            "prefixItems": [
              {
                "type": "number",
                "minimum": -180,
                "maximum": 180
              },
              {
                "type": "number",
                "minimum": -90,
                "maximum": 90
              }
            ],
            "items": false,
            "minItems": 2,
            "maxItems": 2
          }
        }
      },
      "required": [
        "type",
        "coordinates"
      ],
      "description": "GeoJSON [longitude, latitude]. A polyline is NOT evidence of a walkable path."
    },
    "RouteCandidate": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "kind": {
          "type": "string",
          "enum": [
            "direct",
            "via_assistance"
          ]
        },
        "geometry": {
          "$ref": "#/$defs/LineString"
        },
        "distanceMeters": {
          "type": "number",
          "minimum": 0
        },
        "durationSeconds": {
          "anyOf": [
            {
              "type": "number",
              "minimum": 0
            },
            {
              "type": "null"
            }
          ]
        },
        "viaPointIds": {
          "type": "array",
          "items": {
            "type": "string",
            "minLength": 1,
            "maxLength": 120
          },
          "minItems": 0,
          "maxItems": 5,
          "uniqueItems": true
        },
        "provider": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "walkingNetworkVerified": {
          "type": "boolean"
        },
        "explanations": {
          "type": "array",
          "items": {
            "type": "string",
            "minLength": 1,
            "maxLength": 500
          },
          "minItems": 1,
          "maxItems": 20
        },
        "warnings": {
          "type": "array",
          "items": {
            "type": "string",
            "minLength": 1,
            "maxLength": 500
          },
          "minItems": 1,
          "maxItems": 30
        }
      },
      "required": [
        "id",
        "kind",
        "geometry",
        "distanceMeters",
        "durationSeconds",
        "viaPointIds",
        "provider",
        "walkingNetworkVerified",
        "explanations",
        "warnings"
      ],
      "description": "live requires provider-confirmed walking network, never connect points with straight lines as a fallback."
    },
    "RouteResult": {
      "oneOf": [
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "schemaVersion": {
              "const": "1.0.0",
              "type": "string"
            },
            "requestId": {
              "type": "string",
              "minLength": 1,
              "maxLength": 120
            },
            "mode": {
              "type": "string",
              "enum": [
                "mock",
                "live"
              ]
            },
            "generatedAt": {
              "type": "string",
              "format": "date-time",
              "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
            },
            "status": {
              "const": "ok",
              "type": "string"
            },
            "routes": {
              "type": "array",
              "items": {
                "$ref": "#/$defs/RouteCandidate"
              },
              "minItems": 1,
              "maxItems": 3
            },
            "warnings": {
              "type": "array",
              "items": {
                "type": "string",
                "minLength": 1,
                "maxLength": 500
              },
              "minItems": 1,
              "maxItems": 30
            }
          },
          "required": [
            "schemaVersion",
            "requestId",
            "mode",
            "generatedAt",
            "status",
            "routes",
            "warnings"
          ]
        },
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "schemaVersion": {
              "const": "1.0.0",
              "type": "string"
            },
            "requestId": {
              "type": "string",
              "minLength": 1,
              "maxLength": 120
            },
            "mode": {
              "type": "string",
              "enum": [
                "mock",
                "live"
              ]
            },
            "generatedAt": {
              "type": "string",
              "format": "date-time",
              "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
            },
            "status": {
              "type": "string",
              "enum": [
                "no_route",
                "provider_unavailable",
                "invalid_input",
                "cancelled"
              ]
            },
            "routes": {
              "type": "array",
              "maxItems": 0,
              "items": false
            },
            "reason": {
              "type": "string",
              "minLength": 1,
              "maxLength": 500
            },
            "warnings": {
              "type": "array",
              "items": {
                "type": "string",
                "minLength": 1,
                "maxLength": 500
              },
              "minItems": 1,
              "maxItems": 30
            }
          },
          "required": [
            "schemaVersion",
            "requestId",
            "mode",
            "generatedAt",
            "status",
            "routes",
            "reason",
            "warnings"
          ]
        }
      ]
    },
    "IncidentSummary": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "schemaVersion": {
          "const": "1.0.0",
          "type": "string"
        },
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "mode": {
          "type": "string",
          "enum": [
            "mock",
            "live"
          ]
        },
        "category": {
          "type": "string",
          "enum": [
            "personal_threat",
            "medical",
            "fire",
            "other"
          ]
        },
        "createdAt": {
          "type": "string",
          "format": "date-time",
          "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
        },
        "location": {
          "anyOf": [
            {
              "$ref": "#/$defs/Position"
            },
            {
              "type": "null"
            }
          ]
        },
        "note": {
          "type": "string",
          "maxLength": 500
        },
        "consentToShareLocation": {
          "type": "boolean"
        },
        "transferState": {
          "type": "string",
          "enum": [
            "local_only",
            "handoff_requested"
          ]
        }
      },
      "required": [
        "schemaVersion",
        "id",
        "mode",
        "category",
        "createdAt",
        "location",
        "note",
        "consentToShareLocation",
        "transferState"
      ],
      "description": "A private in-memory draft, not an accepted police/fire incident. No home address/contact history in logs."
    },
    "EmergencyActionResult": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "schemaVersion": {
          "const": "1.0.0",
          "type": "string"
        },
        "channel": {
          "type": "string",
          "enum": [
            "110",
            "119",
            "trusted_contact"
          ]
        },
        "action": {
          "type": "string",
          "enum": [
            "dial_link_activated",
            "share_sheet_requested",
            "cancelled",
            "not_configured",
            "failed"
          ]
        },
        "officialReceipt": {
          "type": "null"
        },
        "message": {
          "type": "string",
          "minLength": 1,
          "maxLength": 500
        }
      },
      "required": [
        "schemaVersion",
        "channel",
        "action",
        "officialReceipt",
        "message"
      ],
      "description": "OS handoff only. Never infer a connected call, delivered message, police acceptance or dispatch."
    },
    "CompanionScenario": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "schemaVersion": {
          "const": "1.0.0",
          "type": "string"
        },
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "label": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "disclosure": {
          "const": "模擬通話，未聯絡任何人",
          "type": "string"
        },
        "steps": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "id": {
                "type": "string",
                "minLength": 1,
                "maxLength": 120
              },
              "text": {
                "type": "string",
                "minLength": 1,
                "maxLength": 300
              },
              "audioSrc": {
                "anyOf": [
                  {
                    "type": "string",
                    "pattern": "^/audio/[A-Za-z0-9_./-]+\\.(mp3|wav|ogg)$",
                    "maxLength": 300
                  },
                  {
                    "type": "null"
                  }
                ]
              },
              "pauseAfterMs": {
                "type": "integer",
                "minimum": 0,
                "maximum": 15000
              }
            },
            "required": [
              "id",
              "text",
              "audioSrc",
              "pauseAfterMs"
            ]
          },
          "minItems": 1,
          "maxItems": 12
        }
      },
      "required": [
        "schemaVersion",
        "id",
        "label",
        "disclosure",
        "steps"
      ],
      "description": "Owned/licensed recordings only. Null audio means text preview, not an active voice conversation."
    },
    "CompanionEvent": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "schemaVersion": {
          "const": "1.0.0",
          "type": "string"
        },
        "scenarioId": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "state": {
          "type": "string",
          "enum": [
            "idle",
            "playing",
            "paused",
            "ended",
            "error"
          ]
        },
        "reason": {
          "type": "string",
          "enum": [
            "user",
            "emergency",
            "unmount",
            "audio_error",
            "not_configured",
            "visibility_hidden"
          ]
        },
        "occurredAt": {
          "type": "string",
          "format": "date-time",
          "pattern": "(Z|[+-]\\d{2}:\\d{2})$"
        }
      },
      "required": [
        "schemaVersion",
        "scenarioId",
        "state",
        "reason",
        "occurredAt"
      ]
    },
    "AppEvent": {
      "oneOf": [
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "type": {
              "const": "location.updated",
              "type": "string"
            },
            "payload": {
              "$ref": "#/$defs/Position"
            }
          },
          "required": [
            "type",
            "payload"
          ]
        },
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "type": {
              "const": "route.completed",
              "type": "string"
            },
            "payload": {
              "$ref": "#/$defs/RouteResult"
            }
          },
          "required": [
            "type",
            "payload"
          ]
        },
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "type": {
              "const": "emergency.opened",
              "type": "string"
            },
            "payload": {
              "type": "object",
              "additionalProperties": false,
              "properties": {
                "reason": {
                  "type": "string",
                  "enum": [
                    "user",
                    "threat"
                  ]
                }
              },
              "required": [
                "reason"
              ]
            }
          },
          "required": [
            "type",
            "payload"
          ]
        },
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "type": {
              "const": "companion.changed",
              "type": "string"
            },
            "payload": {
              "$ref": "#/$defs/CompanionEvent"
            }
          },
          "required": [
            "type",
            "payload"
          ]
        }
      ]
    }
  }
}
''';
