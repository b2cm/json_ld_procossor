import 'dart:math';

import 'package:json_ld_processor/src/context_processing.dart';

void addValue(
    {required Map<dynamic, dynamic> object,
    required String key,
    required dynamic value,
    bool asArray = false}) {
  //3
  if (!object.containsKey(key)) {
    object[key] = value;
  } else {
    var entry = object[key];
    if (entry is! List) {
      entry = [entry];
    }
    //2
    if (value is List) {
      entry += value;
    } else {
      entry.add(value);
    }
    object[key] = entry;
  }

  //1)
  if (asArray) {
    var orgValue = object[key];
    if (orgValue is! List) {
      object[key] = [orgValue];
    }
  }
}

bool isValueObject(Map<dynamic, dynamic> object) {
  if (!object.containsKey('@value')) return false;
  var allowed = ['@type', '@language', '@direction', '@index', '@context'];
  if (!object.keys.every((element) => allowed.contains(element))) return false;
  if (object.containsKey('@type')) {
    if (object.containsKey('@direction') || object.containsKey('@language')) {
      return false;
    }
  }
  return true;
}

bool isUri(String? value) {
  if (value == null) return false;
  if (value.contains(' ')) return false;
  try {
    Uri.parse(value);
    return true;
  } catch (e) {
    return false;
  }
}

bool isAbsoluteUri(String? value) {
  if (isUri(value)) {
    var uri = Uri.parse(value!);
    return uri.hasScheme;
  } else {
    return false;
  }
}

bool isListObject(dynamic object) {
  if (object is! Map) {
    return false;
  } else {
    return object.containsKey('@list') &&
        (object.length == 1 ||
            (object.length == 2 && object.containsKey('@index')));
  }
}

bool isNodeObject(dynamic object) {
  if (object is! Map) {
    return false;
  } else {
    return (!object.containsKey('@set') &&
            !object.containsKey('@value') &&
            !object.containsKey('@list')) ||
        <String>{'@context', '@graph'}.containsAll(object.keys);
  }
}

bool nonMatchWordFromList(String word, List<String> list) {
  for (var w in list) {
    if (w == word) {
      return false;
    }
  }
  return true;
}

bool validateContainer(dynamic container, Context activeContext) {
  const List<String> allowed = [
    '@graph',
    '@id',
    '@index',
    '@language',
    '@list',
    '@set',
    '@type'
  ];
  if (container == null) {
    return false;
  }
  if (activeContext.options.processingMode == 'json-ld-1.0') {
    return container is String &&
        nonMatchWordFromList(container, ['@graph', '@id', '@list']);
  }

  if (container is List && container.length == 1) {
    container = container.first;
  }

  if (container is String) {
    return allowed.contains(container);
  }

  if (container is! List) {
    return false;
  } else {
    if (container.length > 3) return false;
    if (container.contains('@graph') &&
        (container.contains('@id') || container.contains('@index'))) {
      return container.length == 2 || container.contains('@set');
    }
    return container.length == 2 &&
        container.contains('@set') &&
        (container.contains('@graph') ||
            container.contains('@id') ||
            container.contains('@index') ||
            container.contains('@language') ||
            container.contains('@type'));
  }
}

bool compareJsonLd(dynamic value1, dynamic value2) {
  if (value1 == null && value2 != null) {
    return false;
  }
  if (value1 != null && value2 == null) {
    return false;
  }
  if (value1 == null && value2 == null) {
    return true;
  }
  if (value1.length != value2.length) {
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
          return false;
        }
      }
      //array
      else if (v1 is List && v2 is List) {
        if (v1.length != v2.length) {
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
                return false;
              }
            } else if (!v2.contains(item)) {
              return false;
            }
          }
        }
      }
      //object
      else if (v1 is Map<String, dynamic> && v2 is Map<String, dynamic>) {
        if (!compareJsonLd(v1, v2)) {
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
            return false;
          }
        } else if (!value2.contains(item)) {
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

bool compareList(List<String>? v1, List<String>? v2) {
  if (v1 == null && v2 == null) {
    return true;
  }
  if (v1?.length != v2?.length) {
    return false;
  }
  for (var v in v1!) {
    if (!v2!.contains(v)) {
      return false;
    }
  }

  return true;
}

bool isGraphObject(dynamic object) {
  if (object is! Map || !object.containsKey('@graph')) {
    return false;
  }

  Set allowed = {'@graph', '@id', '@index', '@context'};
  return allowed.containsAll(object.keys);
}

bool isSimpleGraphObject(dynamic object) {
  return isGraphObject(object) && !object.containsKey('@id');
}

// Dart port of Java Titanium impl
String toRelativeUri(Uri base, String uri) {
  var asUri = Uri.parse(uri);
  if (base == Uri() || !base.isAbsolute || !asUri.isAbsolute) return uri;
  if (base.scheme != asUri.scheme) return uri;
  if (base.authority != asUri.authority) return uri;

  var uriPath = Path.from(asUri.path);
  var basePath = Path.from(base.path);

  var path = uriPath.relativize(basePath);

  if (path.isNotEmpty()) {
    return Uri(
            path: path.toString(), query: asUri.query, fragment: asUri.fragment)
        .toString();
  }

  if (base.query != asUri.query) {
    return Uri(query: asUri.query, fragment: asUri.fragment).toString();
  }

  if (base.fragment != asUri.fragment) {
    return Uri(fragment: asUri.fragment).toString();
  }

  return uriPath.getLeaf() ?? './';
}

// Dart port of Java Titanium impl
class Path {
  final List<String> segments;
  final String? last;
  final bool relative;

  Path(this.segments, this.last, this.relative);

  factory Path.from(String path) {
    bool relative = !path.startsWith('/');
    var segments = (relative ? path : path.substring(1)).split('/');
    var last = (path.length > 1 && path.endsWith('/'))
        ? null
        : segments.removeAt(segments.length - 1);
    return Path(segments, last, relative);
  }

  Path relativize(Path base) {
    if (segments.isEmpty && base.segments.isEmpty) {
      if (last == base.last) {
        return Path([], null, !base.relative);
      } else {
        return Path([], last, !base.relative && !relative);
      }
    }

    if (base.segments.isEmpty && base.last == null) {
      return Path(segments, last, !base.relative && !relative);
    }

    var leftIndex = 0;

    for (;
        leftIndex < min(segments.length, base.segments.length);
        leftIndex++) {
      if (segments[leftIndex] != base.segments[leftIndex]) {
        break;
      }
    }

    if (leftIndex == segments.length && leftIndex == base.segments.length) {
      if (last == base.last) {
        return Path([], null, true);
      } else {
        return Path([], last, segments.isNotEmpty);
      }
    }

    if (leftIndex <= base.segments.length) {
      if (segments.length - leftIndex == 1 &&
          segments[leftIndex] == base.last) {
        return Path(['.'], last, true);
      }
      return Path(segments.sublist(leftIndex), last, true);
    }

    var rightIndex = 0;
    var diff = <String>[];

    for (;
        rightIndex < min(segments.length, base.segments.length) - leftIndex;
        rightIndex++) {
      if (segments[segments.length - rightIndex - 1] !=
          (base.segments[base.segments.length - rightIndex - 1])) {
        break;
      }
      diff.add("..");
    }
    for (int i = 0; i < (base.segments.length - leftIndex - rightIndex); i++) {
      diff.add("..");
    }

    for (int i = 0; i < (segments.length - leftIndex - rightIndex); i++) {
      diff.add(segments[i + leftIndex]);
    }

    return Path(diff, last == base.last ? null : last, true);
  }

  bool isEmpty() {
    return segments.isEmpty && last == null && !relative;
  }

  bool isNotEmpty() {
    return segments.isNotEmpty || last != null || !relative;
  }

  String? getLeaf() {
    return last;
  }

  @override
  String toString() {
    return '${relative ? '' : '/'}${segments.join('/')}${segments.isEmpty ? '' : '/'}${last ?? ''}';
  }
}
