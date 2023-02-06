import 'dart:convert';
import 'dart:io';

import 'package:json_ld_processor/json_ld_processor.dart';
import 'package:test/test.dart';

void main() {
  group('expand', () {
    var manifestFile = File('../json-ld-api/tests/expand-manifest.jsonld');
    var manifest = jsonDecode(manifestFile.readAsStringSync());
    var sequence = manifest['sequence'] as List;
    for (var testData in sequence) {
      var name = testData['name'];
      var id = testData['@id'];
      var input = testData['input']!;
      var options = testData['option'];
      var base = options?['base'];
      var expandContextPath = options?['expandContext'];
      var processingMode = options?['processingMode'];
      var specVersion = options?['specVersion'];
      if (specVersion != null && specVersion == 'json-ld-1.0') continue;
      List<String> type = testData['@type']!.cast<String>();
      bool negative = false;
      if (type.first.contains('Negative')) {
        negative = true;
      }

      test('${type.first}: $name, id: $id', () async {
        var inputFile = File('../json-ld-api/tests/$input');
        var jsonIn = jsonDecode(inputFile.readAsStringSync());
        if (negative) {
          var errorCode = testData['expectErrorCode'];
          expect(
              () => JsonLdProcessor.expand(jsonIn,
                  options: JsonLdOptions(
                      processingMode:
                          processingMode ?? specVersion ?? 'json-ld-1.1',
                      base: Uri.parse(base ??
                          'https://w3c.github.io/json-ld-api/tests/$input'))),
              throwsA(predicate(
                  (e) => e is JsonLdError && e.message == errorCode)));
        } else {
          var output = testData['expect'];
          dynamic expandContext;
          if (expandContextPath != null) {
            var expCFile = File('../json-ld-api/tests/$expandContextPath');
            expandContext = jsonDecode(expCFile.readAsStringSync());
          }
          var expanded = await JsonLdProcessor.expand(jsonIn,
              options: JsonLdOptions(
                  processingMode:
                      processingMode ?? specVersion ?? 'json-ld-1.1',
                  expandContext: expandContext,
                  base: Uri.parse(base ??
                      'https://w3c.github.io/json-ld-api/tests/$input')));
          var expandedJson = jsonDecode(expanded);
          print('expanded');
          print(expandedJson);
          var expected = File('../json-ld-api/tests/$output');
          var expectedJson = jsonDecode(expected.readAsStringSync());
          print('\nexpected:');
          print(expectedJson);
          expect(compareJsonLd(expectedJson, expandedJson), true);
        }
      });
    }
  });

  group('compact', () {
    var manifestFile = File('../json-ld-api/tests/compact-manifest.jsonld');
    var manifest = jsonDecode(manifestFile.readAsStringSync());
    var sequence = manifest['sequence'] as List;
    for (var testData in sequence) {
      var name = testData['name'];
      var context = testData['context'];
      var id = testData['@id'];
      var input = testData['input']!;
      var options = testData['option'];
      var base = options?['base'];
      var expandContextPath = options?['expandContext'];
      var processingMode = options?['processingMode'];
      var specVersion = options?['specVersion'];
      if (specVersion != null && specVersion == 'json-ld-1.0') continue;
      List<String> type = testData['@type']!.cast<String>();
      bool negative = false;
      if (type.first.contains('Negative')) {
        negative = true;
      }

      test('${type.first}: $name, id: $id', () async {
        var inputFile = File('../json-ld-api/tests/$input');
        var jsonIn = jsonDecode(inputFile.readAsStringSync());
        var contextFile = File('../json-ld-api/tests/$context');
        var contextJson = jsonDecode(contextFile.readAsStringSync());
        if (negative) {
          var errorCode = testData['expectErrorCode'];
          expect(
              () => JsonLdProcessor.compact(jsonIn, contextJson,
                  options: JsonLdOptions(
                      processingMode:
                          processingMode ?? specVersion ?? 'json-ld-1.1',
                      base: Uri.parse(base ??
                          'https://w3c.github.io/json-ld-api/tests/$input'))),
              throwsA(predicate(
                  (e) => e is JsonLdError && e.message == errorCode)));
        } else {
          var output = testData['expect'];
          dynamic expandContext;
          if (expandContextPath != null) {
            var expCFile = File('../json-ld-api/tests/$expandContextPath');
            expandContext = jsonDecode(expCFile.readAsStringSync());
          }
          var expanded = await JsonLdProcessor.compact(jsonIn, contextJson,
              options: JsonLdOptions(
                  processingMode:
                      processingMode ?? specVersion ?? 'json-ld-1.1',
                  expandContext: expandContext,
                  base: Uri.parse(base ??
                      'https://w3c.github.io/json-ld-api/tests/$input')));
          var expandedJson = jsonDecode(expanded);
          print('expanded');
          print(expandedJson);
          var expected = File('../json-ld-api/tests/$output');
          var expectedJson = jsonDecode(expected.readAsStringSync());
          print('\nexpected:');
          print(expectedJson);
          expect(compareJsonLd(expectedJson, expandedJson), true);
        }
      });
    }
  });

  group('flatten', () {
    var manifestFile = File('../json-ld-api/tests/flatten-manifest.jsonld');
    var manifest = jsonDecode(manifestFile.readAsStringSync());
    var sequence = manifest['sequence'] as List;
    for (var testData in sequence) {
      var name = testData['name'];
      var id = testData['@id'];
      var input = testData['input']!;
      var options = testData['option'];
      print(options);
      var processingMode = options?['processingMode'];
      var specVersion = options?['specVersion'];
      if (specVersion != null && specVersion == 'json-ld-1.0') continue;
      List<String> type = testData['@type']!.cast<String>();
      bool negative = false;
      if (type.first.contains('Negative')) {
        negative = true;
      }

      test('${type.first}: $name, id: $id', () async {
        var inputFile = File('../json-ld-api/tests/$input');
        var jsonIn = jsonDecode(inputFile.readAsStringSync());
        if (negative) {
          var errorCode = testData['expectErrorCode'];
          expect(
              () => JsonLdProcessor.flatten(jsonIn,
                  options: JsonLdOptions(
                      processingMode:
                          processingMode ?? specVersion ?? 'json-ld-1.1',
                      base: Uri.parse(
                          'https://w3c.github.io/json-ld-api/tests/$input'))),
              throwsA(predicate(
                  (e) => e is JsonLdError && e.message == errorCode)));
        } else {
          var output = testData['expect'];

          var expanded = await JsonLdProcessor.flatten(jsonIn,
              options: JsonLdOptions(
                  processingMode:
                      processingMode ?? specVersion ?? 'json-ld-1.1',
                  base: Uri.parse(
                      'https://w3c.github.io/json-ld-api/tests/$input')));
          var expandedJson = jsonDecode(expanded);
          print('expanded');
          print(jsonEncode(expandedJson));
          var expected = File('../json-ld-api/tests/$output');
          var expectedJson = jsonDecode(expected.readAsStringSync());
          print('\nexpected:');
          print(jsonEncode(expectedJson));
          expect(compareJsonLd(expectedJson, expandedJson), true);
        }
      });
    }
  });

  group('toRdf', () {
    var manifestFile = File('../json-ld-api/tests/toRdf-manifest.jsonld');
    var manifest = jsonDecode(manifestFile.readAsStringSync());
    var sequence = manifest['sequence'] as List;
    for (var testData in sequence) {
      var name = testData['name'];
      var id = testData['@id'];
      var input = testData['input']!;
      var options = testData['option'];
      var processingMode = options?['processingMode'];
      var specVersion = options?['specVersion'];
      var base = options?['base'];
      var expandContextPath = options?['expandContext'];
      if (specVersion != null && specVersion == 'json-ld-1.0') continue;
      List<String> type = testData['@type']!.cast<String>();
      bool negative = false;
      if (type.first.contains('Negative')) {
        negative = true;
      }
      var output = testData['expect'];
      if (output == null && !negative) continue;
      test('${type.first}: $name, id: $id', () async {
        var inputFile = File('../json-ld-api/tests/$input');
        var jsonIn = jsonDecode(inputFile.readAsStringSync());
        if (negative) {
          var errorCode = testData['expectErrorCode'];
          expect(
              () => JsonLdProcessor.toRdf(jsonIn,
                  options: JsonLdOptions(
                      processingMode:
                          processingMode ?? specVersion ?? 'json-ld-1.1',
                      base: Uri.parse(base ??
                          'https://w3c.github.io/json-ld-api/tests/$input'))),
              throwsA(predicate(
                  (e) => e is JsonLdError && e.message == errorCode)));
        } else {
          dynamic expandContext;
          if (expandContextPath != null) {
            var expCFile = File('../json-ld-api/tests/$expandContextPath');
            expandContext = jsonDecode(expCFile.readAsStringSync());
          }
          var expanded = await JsonLdProcessor.toRdf(jsonIn,
              options: JsonLdOptions(
                  processingMode:
                      processingMode ?? specVersion ?? 'json-ld-1.1',
                  expandContext: expandContext,
                  base: Uri.parse(base ??
                      'https://w3c.github.io/json-ld-api/tests/$input')));
          print('expanded');

          var expandedNormal = await JsonLdProcessor.normalize(expanded);
          print(expandedNormal);
          var expected = File('../json-ld-api/tests/$output');
          var expectedJson = expected.readAsStringSync();
          var expectedNormal = await JsonLdProcessor.normalize(
              RdfDataset.fromNQuad(expectedJson));
          print('\nexpected:');
          print(expectedNormal);
          expect(
              compareRdfString(
                  expectedNormal.split('\n'), expandedNormal.split('\n')),
              true);
        }
      });
    }
  });

  group('normalize', () {
    var manifestFile =
        File('../rdf-dataset-canonicalization/tests/manifest-urdna2015.jsonld');
    var manifestJson = jsonDecode(manifestFile.readAsStringSync());
    var entries = manifestJson['entries'] as List;
    for (var entry in entries) {
      var id = entry['id'];
      var name = entry['name'];
      var inName = entry['action'];
      var outName = entry['result'];

      test('$name, id: $id', () async {
        var inFile = File('../rdf-dataset-canonicalization/tests/$inName');
        var inSet = RdfDataset.fromNQuad(inFile.readAsStringSync());
        var normalized = await JsonLdProcessor.normalize(inSet);
        print('normalized:\n$normalized');
        var outFile = File('../rdf-dataset-canonicalization/tests/$outName');
        var expected = outFile.readAsStringSync();
        print('expected:\n$expected');

        expect(normalized, expected);
      });
    }
  });
}

bool compareRdfString(List<String> v1, List<String> v2) {
  v1.remove('\n');
  v2.remove('\n');
  if (v1.length != v2.length) {
    print('unequal length: ${v1.length} != ${v2.length}');
    return false;
  }
  for (var v in v1) {
    if (!v2.contains(v)) return false;
  }
  return true;
}

bool compareJsonLd(dynamic value1, dynamic value2) {
  if (value1.runtimeType != value2.runtimeType) {
    print('different runtime type');
    return false;
  }
  if (value1.length != value2.length) {
    print('unequal lenght of maps (${value1.length} != ${value2.length})');
    return false;
  }
  if (value2 is Map && value1 is Map) {
    var keyList = value1.keys.toList();
    for (var key in keyList) {
      var v1 = value1[key];
      var v2 = value2[key];

      //null
      if (v1 == null && v2 == null) {
      }
      //scalar
      else if (isScalar(v1) && isScalar(v2)) {
        if (v1 != v2) {
          print('scalar at $key do not match (v1: $v1, v2:$v2)');
          return false;
        }
      }
      //array
      else if (v1 is List && v2 is List) {
        if (v1.length != v2.length) {
          print('array length at $key do not match');
          return false;
        }
        if (key == '@list') {
          for (int i = 0; i < v1.length; i++) {
            if (v1[i] is Map && v2[i] is Map) {
              if (!compareJsonLd(v1[i], v2[i])) {
                return false;
              }
            } else if (v1[i] != v2[i]) {
              return false;
            }
          }
        } else {
          for (var item in v1) {
            if (item is Map) {
              bool match = true;
              for (var compareItem in v2) {
                match = compareJsonLd(item, compareItem);
                if (match) break;
              }
              if (!match) {
                print('could not find a matching item for $item at key $key');
                return false;
              }
            } else if (!v2.contains(item)) {
              print('other list do not contain item $item at $key');
              return false;
            }
          }
        }
      }
      //object
      else if (v1 is Map<String, dynamic> && v2 is Map<String, dynamic>) {
        if (!compareJsonLd(v1, v2)) {
          print('objects do not match at key $key');
          return false;
        }
      } else {
        return false;
      }
    }
  } else if (value1 is List && value2 is List) {
    if (value2.isEmpty && value1.isEmpty) {
      return true;
    } else if (value1.length != value2.length) {
      print('unequal length of Lists');
      return false;
    } else {
      for (var item in value1) {
        if (item is Map) {
          bool match = true;
          for (var compareItem in value2) {
            match = compareJsonLd(item, compareItem);
            if (match) break;
          }
          if (!match) {
            print('could not find a matching item for $item at key');
            return false;
          }
        } else if (!value2.contains(item)) {
          print('other list do not contain item $item');
          return false;
        }
      }
    }
  } else {
    return false;
  }

  return true;
}

bool isScalar(dynamic value) {
  if (value is String || value is num || value is bool) {
    return true;
  } else {
    return false;
  }
}
