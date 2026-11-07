import 'dart:convert';

import 'package:town_pass/features/safe_walk/safety_data/crime_warning/verified_crime_geography.dart';

/// Offline, independently checkable official public-place outline.
/// No geocoding, user position, mock coordinates or inferred crime point.
/// See docs/SAFE_WALK_CRIME_WARNING_DATA.md for provenance and coverage limits.
VerifiedCrimeGeographicResolver createVerifiedTaipeiCrimeGeography() =>
    VerifiedCrimeGeographicResolver.fromGeoJsonManifest(
      jsonDecode(_reviewedCatalogue) as Map<String, Object?>,
    );

/// A fresh object for evidence tooling; mutations do not change the catalogue.
Map<String, Object?> reviewedTaipeiCrimeGeographyManifest() =>
    jsonDecode(_reviewedCatalogue) as Map<String, Object?>;

const _reviewedCatalogue = r'''{
  "version": "crime-warning-geography/1",
  "provenance": {
    "checkedAt": "2026-11-07T14:32:23Z",
    "geometryDatasetId": "5b277432-f534-4d09-a24c-d3f6b514e042",
    "geometryResourceId": "f3ce4bb6-712a-41ae-902b-f8a6099eac85",
    "geometryResourceSha256": "2d7ae1070eea77c0dd720554e953f6ccc48df0662b061faf71799425a9847431",
    "geometryDataUpdatedAt": null,
    "registryDatasetId": "ea732fb5-4bec-4be7-93f2-8ab91e74a6c6",
    "registryUrl": "https://parks.gov.taipei/parks/api/",
    "registrySha256": "866ed5f79853eb38e6ff0b9ffcdf0fc51d23763405a6086ef72cc7bcc6342cd9",
    "originalFeatureId": "L0101-5.123",
    "registryRecord": {
      "SeqNo": "374",
      "pm_name": "二二八和平公園",
      "pm_regions": "中正區",
      "pm_Longitude": "121.5142970000",
      "pm_Latitude": "25.0422860000",
      "pm_location": "凱達格蘭大道3號",
      "pm_area": null
    },
    "sourceCrs": "EPSG:3826",
    "outputCrs": "EPSG:4326 (GeoJSON longitude, latitude)",
    "conversion": "proj4dart 3.0.0, GRS80 tmerc lon_0=121 lat_0=0 k=0.9999 x_0=250000 y_0=0",
    "mapping": "Official named park registry anchor is inside exactly one official parks polygon; bounds and area checked against official park description. No nearest-neighbour match.",
    "registryAreaFromOverviewSquareMeters": 76180,
    "polygonAreaSquareMeters": 76674.08013916016
  },
  "matches": [
    {
      "sourceId": "985743f7-a33e-4ac1-ad2e-7ef5ffea02e2:11",
      "locationText": "中正區二二八和平公園",
      "geometry": {
        "type": "MultiPolygon",
        "coordinates": [
          [
            [
              [
                121.51402491172315,
                25.040986459432663
              ],
              [
                121.5140664403867,
                25.041869877612445
              ],
              [
                121.51409121309649,
                25.042446958120685
              ],
              [
                121.51410327852776,
                25.042721487860995
              ],
              [
                121.51412651847403,
                25.043308766316763
              ],
              [
                121.51415685583021,
                25.04333314552784
              ],
              [
                121.5141703632853,
                25.043333143923423
              ],
              [
                121.51441548346864,
                25.04332694176867
              ],
              [
                121.5149380074553,
                25.043313729195667
              ],
              [
                121.51512486920461,
                25.043305660343325
              ],
              [
                121.51649561427699,
                25.043275108190652
              ],
              [
                121.51652127863596,
                25.0432436914866
              ],
              [
                121.51633340791777,
                25.042601092830377
              ],
              [
                121.51592413227603,
                25.041182043093507
              ],
              [
                121.5155512437492,
                25.039895380020802
              ],
              [
                121.5155229794654,
                25.039797830176116
              ],
              [
                121.51547580196474,
                25.039770124110035
              ],
              [
                121.51448009594492,
                25.039899092686216
              ],
              [
                121.51396166596321,
                25.03996859757004
              ],
              [
                121.51393083928738,
                25.040002559568492
              ],
              [
                121.51402491172315,
                25.040986459432663
              ]
            ]
          ]
        ]
      },
      "spatialPrecision": "confirmedPublicPlace",
      "confidence": "verified",
      "geoSourceUrl": "https://data.taipei/api/dataset/5b277432-f534-4d09-a24c-d3f6b514e042/resource/f3ce4bb6-712a-41ae-902b-f8a6099eac85/download",
      "geoSourceLicense": "政府資料開放授權條款-第1版",
      "geoRetrievedAt": "2026-11-07T14:32:23Z",
      "verifiedAt": "2026-11-07T14:32:23Z",
      "validUntil": "2027-02-01T00:00:00+08:00",
      "accuracyMeters": null,
      "matchEvidence": "婦幼警示第11筆文字與公園基本資料SeqNo374之名稱/行政區一致；官方參考座標121.514297,25.042286落在官方公園圖層唯一多邊形L0101-5.123內。四周道路及面積76,674m²對照公園說明76,180m²，約0.65%差異；保留原始EPSG:3826形狀並轉成GeoJSON WGS84，未以中心點或人工方框代替。",
      "limitations": [
        "僅此已核對公共場所輪廓參與比對；不是犯罪發生點、警方勘測界線或即時危險範圍。",
        "原公園圖層名稱欄為「無」，名稱對應依另一官方公園資料的參考位置、行政區、面積與周邊道路交叉核對。",
        "來源未提供公尺定位精度及幾何更新日期，保留null；坐標小數位不是測量精度，輪廓與現地可能有誤差。",
        "原始與參考面積約有0.65%差異；只保證不與目前標示多邊形相交，不保證避開整個未知警示範圍或所有案件。",
        "僅1/22婦幼文字警示已核對範圍，其餘21筆與模糊化歷史案件不做精確避讓；有效期屆滿須重核。"
      ]
    }
  ]
}''';
