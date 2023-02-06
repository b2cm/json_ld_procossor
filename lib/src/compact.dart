import 'package:json_ld_processor/json_ld_processor.dart';
import 'package:json_ld_processor/src/context_processing.dart';
import 'package:json_ld_processor/src/expansion.dart';
import 'package:json_ld_processor/src/utils.dart';

dynamic compactImpl(
    Context activeContext, dynamic activeProperty, dynamic element,
    {bool compactArrays = false, bool ordered = false}) async {
  //1
  var typeScopedContext = activeContext;

  //2
  if (isScalar(element)) {
    return element;
  }
  //3
  if (element is List) {
    //3.1
    var result = [];
    //3.2
    for (var item in element) {
      //3.2.1
      var compactedItem = await compactImpl(activeContext, activeProperty, item,
          compactArrays: compactArrays, ordered: ordered);
      //3.2.2
      if (compactedItem != null) {
        result.add(compactedItem);
      }
    }
    //3.3
    if (result.isEmpty ||
        result.length > 1 ||
        !compactArrays ||
        activeProperty == '@graph' ||
        activeProperty == '@set' ||
        (activeContext.terms[activeProperty]?.containerMapping
                ?.contains('@list') ??
            false) ||
        (activeContext.terms[activeProperty]?.containerMapping
                ?.contains('@set') ??
            false)) {
      return result;
    } else {
      //3.4
      return result.first;
    }
  }
  // 4
  element = element as Map;

  // 5
  if (activeContext.previousContext != null &&
      !element.containsKey('@value') &&
      !element.containsKey('@id') &&
      element.length == 1) {
    activeContext = activeContext.previousContext!;
  }

  //6
  if (activeContext.terms[activeProperty]?.context != null) {
    // 6.1
    activeContext = await processContext(
        activeContext: activeContext,
        localContext: activeContext.terms[activeProperty]!.context,
        baseUrl: activeContext.terms[activeProperty]!.baseUrl ?? Uri(),
        overwriteProtected: true);
  }

  // 7
  if (element.containsKey('@id') || element.containsKey('@value')) {
    var res = compactValue(activeContext, activeProperty, element);
    if (isScalar(res) ||
        (activeContext.terms[activeProperty]?.typeMapping == '@json')) {
      return res;
    }
  }

  // 8
  if (isListObject(element) &&
      (activeContext.terms[activeProperty]?.containerMapping
              ?.contains('@list') ??
          false)) {
    return await compactImpl(activeContext, activeProperty, element['@list'],
        compactArrays: compactArrays, ordered: ordered);
  }

  // 9
  var insideReverse = activeProperty == '@reverse';

  // 10
  var result = {};

  // 11
  if (element.containsKey('@type')) {
    var compactedTypes = <String>[];

    var type = element['@type'];
    if (type is! List) {
      type = [type];
    }

    type = type.cast<String>();

    for (var item in type) {
      var compactedType = compactIri(activeContext, item, vocab: true);
      compactedTypes.add(compactedType!);
    }

    compactedTypes.sort();

    for (var term in compactedTypes) {
      if (activeContext.terms[term]?.context != null) {
        activeContext = await processContext(
            activeContext: activeContext,
            localContext: activeContext.terms[term]!.context,
            baseUrl: activeContext.terms[term]!.baseUrl ?? Uri(),
            propagate: false);
      }
    }
  }

  // 12
  var keys = element.keys.toList();
  if (ordered) {
    keys.sort();
  }

  for (var expandedProperty in keys) {
    var expandedValue = element[expandedProperty]!;

    // 12.1
    if (expandedProperty == '@id') {
      // 12.1.1
      String? compactedValue;
      if (expandedValue is String) {
        compactedValue = compactIri(activeContext, expandedValue, vocab: false);
      }
      // 12.1.2
      var alias = compactIri(activeContext, expandedProperty, vocab: true);
      // 12.1.3
      result[alias] = compactedValue;
      continue;
    }

    // 12.2
    if (expandedProperty == '@type') {
      // 12.2.1
      dynamic compactedValue;
      if (expandedValue is String) {
        compactedValue =
            compactIri(typeScopedContext, expandedValue, vocab: true);
      } else if (expandedValue is List) {
        // 12.2.2.1
        compactedValue = [];
        // 12.2.2.2
        for (var expandedType in expandedValue) {
          // 12.2.2.2.1
          var term = compactIri(typeScopedContext, expandedType, vocab: true);
          //12.2.2.2.2
          compactedValue.add(term);
        }
        // I don't know why but it seems to work
        if (compactedValue.length == 1) {
          compactedValue = compactedValue.first;
        }
      } else {
        throw Exception(
            'Compaction: expanded value is neither array or String. This should never happen');
      }
      // 12.2.3
      var alias = compactIri(activeContext, expandedProperty, vocab: true);
      // 12.2.4
      var asArray = !compactArrays;

      if (activeContext.options.processingMode == 'json-ld-1.1' &&
          activeContext.terms[alias]?.containerMapping != null &&
          activeContext.terms[alias]!.containerMapping!.contains('@set')) {
        asArray = true;
      }
      // 12.2.5
      addValue(
          object: result, key: alias!, value: compactedValue, asArray: asArray);
      // 12.2.6
      continue;
    }

    // 12.3
    if (expandedProperty == '@reverse') {
      // 12.3.1
      var compactedValue = await compactImpl(
          activeContext, '@reverse', expandedValue,
          compactArrays: compactArrays, ordered: ordered);
      // 12.3.2
      if (compactedValue is Map) {
        for (var property in compactedValue.keys) {
          // 12.3.2.1.3
          var value = compactedValue.remove(property);
          //12.3.2.1
          bool asArray = (activeContext.terms[activeProperty]?.containerMapping
                      ?.contains('@set') ??
                  false)
              ? true
              : !compactArrays;
          // 12.3.2.1.2
          addValue(
              object: result, key: property, value: value, asArray: asArray);
        }
        // 12.3.3
        if (compactedValue.isNotEmpty) {
          // 12.3.3.1
          var alias = compactIri(activeContext, '@reverse', vocab: true);
          // 12.3.3.2
          result[alias] = compactedValue;
        }
        // 12.3.4
        continue;
      } else {
        continue;
      }
    }

    // 12.4
    if (expandedProperty == '@preserve') {
      // 12.4.1
      var compactedValue = await compactImpl(
          activeContext, activeProperty, expandedValue,
          compactArrays: compactArrays, ordered: ordered);
      // 12.4.2
      if (compactedValue is List && compactedValue.isEmpty) {
        continue;
      } else {
        result['@preserve'] = compactedValue;
        continue;
      }
    }

    // 12.5
    if (expandedProperty == '@index' &&
        (activeContext.terms[activeProperty]?.containerMapping
                ?.contains('@index') ??
            false)) {
      continue;
    }

    // 12.6
    else if (expandedProperty == '@index' ||
        expandedProperty == '@direction' ||
        expandedProperty == '@language' ||
        expandedProperty == '@value') {
      // 12.6.1
      var alias = compactIri(activeContext, expandedProperty, vocab: true);
      // 12.6.2
      result[alias] = expandedValue;
      continue;
    }

    // 12.7
    if (expandedValue is List && expandedValue.isEmpty) {
      // 12.7.1
      var item = compactIri(activeContext, expandedProperty,
          value: expandedValue, vocab: true, reverse: insideReverse);
      // 12.7.2
      dynamic nestResult;
      var nestTerm = activeContext.terms[item]?.nestValue;
      if (nestTerm != null) {
        // 12.7.2.1
        if (nestTerm != '@nest' &&
            (await expandIri(
                    activeContext: activeContext,
                    value: nestTerm,
                    vocab: true) !=
                '@nest')) {
          throw JsonLdError('invalid @nest value');
        }
        // 12.7.2.2
        if (!result.containsKey(nestTerm)) {
          result[nestTerm] = [];
        }
        // 12.7.2.3
        nestResult = result[nestTerm];
      }
      // 12.7.3
      else {
        nestResult = result;
      }
      // 12.7.4
      addValue(object: nestResult, key: item!, value: [], asArray: true);
    }

    // 12.8
    expandedValue as List;
    for (var expandedItem in expandedValue) {
      // 12.8.1
      var itemActiveProperty = compactIri(activeContext, expandedProperty,
          value: expandedItem, reverse: insideReverse, vocab: true);
      // 12.8.2
      dynamic nestResult;
      var nestTerm = activeContext.terms[itemActiveProperty]?.nestValue;
      if (nestTerm != null) {
        // 12.8.2.1
        if (nestTerm != '@nest' &&
            (await expandIri(
                    activeContext: activeContext,
                    value: nestTerm,
                    vocab: true) !=
                '@nest')) {
          throw JsonLdError('invalid @nest value');
        }
        // 12.8.2.2
        if (!result.containsKey(nestTerm)) {
          result[nestTerm] = [];
        }
        // 12.8.2.3
        nestResult = result[nestTerm];
      }
      // 12.8.3
      else {
        nestResult = result;
      }
      // 12.8.4
      var container =
          activeContext.terms[itemActiveProperty]?.containerMapping ?? [];
      //12.8.5
      bool asArray = (container.contains('@set') ||
              itemActiveProperty == '@graph' ||
              itemActiveProperty == '@list')
          ? true
          : !compactArrays;

      // 12.8.6
      var expandedItemValue = expandedItem;
      if (isListObject(expandedItem)) {
        expandedItemValue = expandedItem['@list'];
      } else if (isGraphObject(expandedItem)) {
        expandedItemValue = expandedItem['@graph'];
      }
      var compactedItem = await compactImpl(
          activeContext, itemActiveProperty, expandedItemValue,
          compactArrays: compactArrays, ordered: ordered);

      // 12.8.7
      if (isListObject(expandedItem)) {
        // 12.8.7.1
        compactedItem = compactedItem is List ? compactedItem : [compactedItem];
        // 12.8.7.2
        if (!container.contains('@list')) {
          // 12.8.7.2.1
          var key = compactIri(activeContext, '@list', vocab: true);
          compactedItem = <String, dynamic>{key!: compactedItem};
          // 12.8.7.2.2
          if (expandedItem is Map && expandedItem.containsKey('@index')) {
            var key = compactIri(activeContext, '@index', vocab: true);
            compactedItem[key] = expandedItem['@index'];
          }
          // 12.8.7.2.3
          addValue(
              object: nestResult,
              key: itemActiveProperty!,
              value: compactedItem,
              asArray: asArray);
        }
        // 12.8.7.3
        else {
          nestResult[itemActiveProperty] = compactedItem;
        }
      }

      // 12.8.8
      else if (isGraphObject(expandedItem)) {
        bool follow = false;
        // 12.8.8.1
        if (container.contains('@id') && container.contains('@graph')) {
          // 12.8.8.1.1
          var mapObject = nestResult[itemActiveProperty] ?? {};
          // 12.8.8.1.2
          var mapKey = '';
          if (expandedItem.containsKey('@id')) {
            mapKey = compactIri(activeContext, expandedItem['@id'])!;
          } else {
            mapKey = compactIri(activeContext, '@none', vocab: true)!;
          }
          // 12.8.8.1.3
          addValue(
              object: mapObject,
              key: mapKey,
              value: compactedItem,
              asArray: asArray);
        }
        // 12.8.8.2
        else if (container.contains('@index') &&
            container.contains('@graph') &&
            isSimpleGraphObject(expandedItem)) {
          // 12.8.8.2.1
          var mapObject = nestResult[itemActiveProperty] ?? {};
          // 12.8.8.2.2
          var mapKey = expandedItem['@index'] ?? '@none';
          // 12.8.8.2.3
          addValue(
              object: mapObject,
              key: mapKey,
              value: compactedItem,
              asArray: asArray);
        }
        // 12.8.8.3
        else if (container.contains('@graph') &&
            isSimpleGraphObject(expandedItem)) {
          // 12.8.8.3.1
          if (compactedItem is List && compactedItem.length > 1) {
            compactedItem = <String, dynamic>{
              compactIri(activeContext, '@included', vocab: true)!:
                  compactedItem
            };
          }
          // 12.8.8.3.2
          addValue(
              object: nestResult,
              key: itemActiveProperty!,
              value: compactedItem,
              asArray: asArray);
        } else {
          follow = true;
        }

        if (!container.contains('@graph') || follow) {
          // 12.8.8.4.1
          compactedItem = <String, dynamic>{
            compactIri(activeContext, '@graph', vocab: true)!: compactedItem
          };
          // 12.8.8.4.2
          if (expandedItem is Map && expandedItem.containsKey('@id')) {
            compactedItem[compactIri(activeContext, '@id', vocab: true)] =
                compactIri(activeContext, expandedItem['@id']);
          }
          // 12.8.8.4.3
          if (expandedItem is Map && expandedItem.containsKey('@index')) {
            compactedItem[compactIri(activeContext, '@index', vocab: true)] =
                expandedItem['@index'];
          }
          // 12.8.8.4.4
          addValue(
              object: nestResult,
              key: itemActiveProperty!,
              value: compactedItem);
        }
      }

      // 12.8.9
      else if (container.contains('@language') ||
          container.contains('@id') ||
          container.contains('@type') ||
          container.contains('@index') && !container.contains('@graph')) {
        //12.8.9.1
        var mapObject = nestResult[itemActiveProperty] ?? {};
        //12.8.9.2
        String? keyToCompact;
        if (container.contains('@language')) {
          keyToCompact = '@language';
        } else if (container.contains('@index')) {
          keyToCompact = '@index';
        } else if (container.contains('@id')) {
          keyToCompact = '@id';
        } else if (container.contains('@type')) {
          keyToCompact = '@type';
        }
        var containerKey = compactIri(activeContext, keyToCompact, vocab: true);

        // 12.8.9.3
        var indexKey =
            activeContext.terms[itemActiveProperty]?.indexMapping ?? '@index';

        String mapKey = '';
        // 12.8.9.4
        if (container.contains('@language') &&
            expandedItem is Map &&
            expandedItem.containsKey('@value')) {
          mapKey = expandedItem['language'] ?? '';
          compactedItem = expandedItem['value'];
        }
        //12.8.9.5
        else if (container.contains('@index') && indexKey == '@index') {
          mapKey = expandedItem['@index'] ?? '';
        }
        // 12.8.9.6
        else if (container.contains('@index') && indexKey != '@index') {
          // 12.8.9.6.1
          containerKey = compactIri(activeContext, indexKey, vocab: true);
          // 12.8.9.6.2 + 12.8.9.6.2.3
          if (compactedItem is Map && compactedItem.containsKey(containerKey)) {
            var containerEntry = compactedItem.remove(containerKey);
            if (containerEntry is String) {
              mapKey = containerEntry;
            } else if (containerEntry is List) {
              mapKey = containerEntry.removeAt(0);
              if (containerEntry.isNotEmpty) {
                addValue(
                    object: compactedItem,
                    key: containerKey!,
                    value: containerEntry);
              }
            }
          }
        }
        // 12.8.9.7
        else if (container.contains('@id')) {
          mapKey = compactedItem.remove(containerKey);
        }
        // 12.8.9.8
        else if (container.contains('@type')) {
          // 12.8.9.8.1 + 2 + 3
          if (compactedItem is Map && compactedItem.containsKey(containerKey)) {
            var containerEntry = compactedItem.remove(containerKey);
            if (containerEntry is String) {
              mapKey = containerEntry;
            } else if (containerEntry is List) {
              mapKey = containerEntry.removeAt(0);
              if (containerEntry.isNotEmpty) {
                addValue(
                    object: compactedItem,
                    key: containerKey!,
                    value: containerEntry);
              }
            }
          }
          // 12.8.9.8.4
          if (compactedItem is Map && compactedItem.length == 1) {
            var expandedKey = await expandIri(
                activeContext: activeContext,
                value: compactedItem.keys.first,
                vocab: true);
            if (expandedKey == '@id') {
              compactedItem = await compactImpl(activeContext,
                  itemActiveProperty, {'@id': expandedItem['@id']});
            }
          }
        }
        // 12.8.9.9
        if (mapKey.isEmpty || mapKey == '') {
          mapKey = compactIri(activeContext, '@none', vocab: true)!;
        }
        // 12.8.9.10
        addValue(
            object: mapObject,
            key: mapKey,
            value: compactedItem,
            asArray: asArray);
      }
      // 12.8.10
      addValue(
          object: nestResult,
          key: itemActiveProperty!,
          value: compactedItem,
          asArray: asArray);
    }
  }
  // 13
  print(result.runtimeType);
  return result;
}

dynamic compactValue(Context activeContext, dynamic activeProperty, Map value) {
  // 1
  dynamic result = Map.from(value);

  // 2
  activeContext.inverseContext ??= createInverseContext(activeContext);

  // 3 not needed

  // 4
  var language = activeContext.terms[activeProperty]?.languageMapping ??
      activeContext.defaultLanguage;

  // 5
  var direction = activeContext.terms[activeProperty]?.directionMapping ??
      activeContext.defaultBaseDirection;

  // 6
  if (value.containsKey('@id') &&
      ((value.length == 1) ||
          (value.length == 2 && value.containsKey('@index')))) {
    // 6.1
    if (activeContext.terms[activeProperty]?.typeMapping != null &&
        activeContext.terms[activeProperty]!.typeMapping == '@id') {
      result = compactIri(activeContext, value['@id']);
    }
    //6.2
    if (activeContext.terms[activeProperty]?.typeMapping != null &&
        activeContext.terms[activeProperty]!.typeMapping == '@vocab') {
      result = compactIri(activeContext, value['@id'], vocab: true);
    }
  }

  // 7
  else if (value.containsKey('@type') &&
      activeContext.terms[activeProperty]?.typeMapping == value['@type']) {
    result = value['@value'];
  }

  // 8
  else if (activeContext.terms[activeProperty]?.typeMapping == '@none' ||
      (value.containsKey('@type') &&
          activeContext.terms[activeProperty]?.typeMapping != value['@type'])) {
    var types = result['@type'];
    if (types != null) {
      if (types is String) {
        var newType = compactIri(activeContext, types, vocab: true);
        result['@type'] = newType;
      } else if (types is List) {
        var newTypes = [];
        for (var t in types) {
          newTypes.add(compactIri(activeContext, t, vocab: true));
        }
        result['@type'] = newTypes;
      }
    }
  }

  // 9
  else if (value['@value'] is! String) {
    // 9.1
    if ((!value.containsKey('@index')) ||
        (activeContext.terms[activeProperty]?.containerMapping != null &&
            activeContext.terms[activeProperty]!.containerMapping!
                .contains('@index'))) {
      result = value['@value'];
    }
  }

  // 10
  else if (((value.containsKey('@language') &&
              value['@language'] is String &&
              language is String &&
              language.toLowerCase() == value['@language'].toLowerCase()) ||
          (language == null &&
              ((!value.containsKey('@language')) ||
                  value['@language'] == ''))) &&
      ((direction != null &&
              direction != '' &&
              value['@direction'] is String &&
              direction.toLowerCase() == value['@direction'].toLowerCase()) ||
          ((direction == null || direction == '') &&
              (!value.containsKey('@direction') ||
                  value['@direction'] == '')))) {
    // 10.1
    if ((!value.containsKey('@index')) ||
        (activeContext.terms[activeProperty]?.containerMapping != null &&
            activeContext.terms[activeProperty]!.containerMapping!
                .contains('@index'))) {
      result = value['@value'];
    }
  }

  // 11
  if (result is Map) {
    result = result.map((key, value) =>
        MapEntry(compactIri(activeContext, key, vocab: true), value));
  }
  // 12
  return result;
}

String? compactIri(Context activeContext, String? variable,
    {dynamic value, bool vocab = false, bool reverse = false}) {
  // 1
  if (variable == null) {
    return null;
  }
  // 2
  activeContext.inverseContext ??= createInverseContext(activeContext);

  // 3
  var inverseContext = activeContext.inverseContext!;

  // 4
  if (vocab && inverseContext.containsKey(variable)) {
    // 4.1
    String defaultLanguage;
    if (activeContext.defaultBaseDirection != null &&
        activeContext.defaultBaseDirection != '') {
      defaultLanguage =
          '${activeContext.defaultLanguage ?? ''}_${activeContext.defaultBaseDirection}'
              .toLowerCase();
    } else if (activeContext.defaultLanguage != null &&
        activeContext.defaultLanguage != '') {
      defaultLanguage = activeContext.defaultLanguage!.toLowerCase();
    } else {
      defaultLanguage = '@none';
    }

    // 4.2
    if (value is Map && value.containsKey('@preserve')) {
      value = value['@preserve'];
      if (value is List) {
        value = value.first;
      }
    }

    // 4.3
    var containers = <String>[];

    // 4.4
    String? typeLanguage = '@language';
    String? typeLanguageValue = '@null';

    // 4.5
    if (value is Map && value.containsKey('@index') && !isGraphObject(value)) {
      containers.add('@index');
      containers.add('@index@set');
    }

    // 4.6
    if (reverse) {
      typeLanguage = '@type';
      typeLanguageValue = '@reverse';
      containers.add('@set');
    }

    // 4.7
    else if (value is Map && isListObject(value)) {
      // 4.7.1
      if (!value.containsKey('@index')) {
        containers.add('@list');
      }
      // 4.7.2
      var list = value['@list'] as List;
      // 4.7.3
      String? commonLanguage = list.isEmpty ? defaultLanguage : null;
      String? commonType;
      // 4.7.4
      for (var item in list) {
        // 4.7.4.1
        var itemLanguage = '@none';
        var itemType = '@none';
        // 4.7.4.2
        if (item is Map && item.containsKey('@value')) {
          // 4.7.4.2.1
          if (item.containsKey('@direction')) {
            itemLanguage = '${item['@language'] ?? ''}_${item['@direction']}'
                .toLowerCase();
          }
          // 4.7.4.2.2
          else if (item.containsKey('@language')) {
            itemLanguage = item['@language'].toLowerCase();
          }
          // 4.7.4.2.3
          else if (item.containsKey('@type')) {
            itemType = item['@type'];
          } else {
            itemLanguage = '@null';
          }
        }
        // 4.7.4.3
        itemType = '@id';
        // 4.7.4.4
        if (commonLanguage == null) {
          commonLanguage = itemLanguage;
        }
        // 4.7.4.5
        else if (itemLanguage != commonLanguage &&
            item is Map &&
            item.containsKey('@value')) {
          commonLanguage = '@none';
        }
        // 4.7.4.6
        if (commonType == null) {
          commonType = itemType;
        }
        // 4.7.4.7
        else if (itemType != commonType) {
          commonType = '@none';
        }
        // 4.7.4.8
        if (commonLanguage == '@none' && commonType == '@none') {
          break;
        }
      }
      // 4.7.5
      commonLanguage ??= '@none';
      // 4.7.6
      commonType ??= '@none';
      // 4.7.7
      if (commonType != '@none') {
        typeLanguage = '@type';
        typeLanguageValue = commonType;
      }
      // 4.7.8
      else {
        typeLanguageValue = commonLanguage;
      }
    }

    // 4.8
    else if (value is Map && isGraphObject(value)) {
      // 4.8.1
      if (value.containsKey('@index')) {
        containers.add('@graph@index');
        containers.add('@graph@index@set');
      }
      // 4.8.2
      if (value.containsKey('@id')) {
        containers.add('@graph@id');
        containers.add('@graph@id@set');
      }
      // 4.8.3
      containers.add('@graph');
      containers.add('@graph@set');
      containers.add('@set');
      // 4.8.4
      if (!value.containsKey('@index')) {
        containers.add('@graph@index');
        containers.add('@graph@index@set');
      }
      // 4.8.5
      if (!value.containsKey('@id')) {
        containers.add('@graph@id');
        containers.add('@graph@id@set');
      }
      // 4.8.6
      containers.add('@index');
      containers.add('@index@set');
      // 4.8.7
      typeLanguage = '@type';
      typeLanguageValue = '@id';
    }
    // 4.9
    else {
      // 4.9.1
      if (value is Map && isValueObject(value)) {
        // 4.9.1.1
        if (value.containsKey('@direction') && !value.containsKey('@index')) {
          typeLanguageValue =
              '${value['@language'] ?? ''}_${value['@direction']}'
                  .toLowerCase();
          containers.add('@language');
          containers.add('@language@set');
        }
        // 4.9.1.2
        else if (value.containsKey('@language') &&
            !value.containsKey('@index')) {
          typeLanguageValue = value['@language'].toLowerCase();
          containers.add('@language');
          containers.add('@language@set');
        }
        // 4.9.1.3
        else if (value.containsKey('@type')) {
          typeLanguageValue = value['@type'];
          typeLanguage = '@type';
        }
      }
      // 4.9.2
      else {
        typeLanguage = '@type';
        typeLanguageValue = '@id';
        containers.addAll(['@id', '@id@set', '@type', '@set@type']);
      }
      // 4.9.3
      containers.add('@set');
    }

    // 4.10
    containers.add('@none');

    // 4.11
    if (activeContext.options.processingMode != 'json-ld-1.0' &&
        (value is! Map || (!value.containsKey('@index')))) {
      containers.add('@index');
      containers.add('@index@set');
    }

    // 4.12
    if (activeContext.options.processingMode != 'json-ld-1.0' &&
        value is Map &&
        value.length == 1 &&
        value.containsKey('@value')) {
      containers.add('@language');
      containers.add('@language@set');
    }

    // 4.13
    typeLanguageValue ??= '@null';

    // 4.14
    var preferredValues = <String>[];

    // 4.15
    if (typeLanguageValue == '@reverse') {
      preferredValues.add('@reverse');
    }

    // 4.16
    if ((typeLanguageValue == '@id' || typeLanguageValue == '@reverse') &&
        (value is Map && value.containsKey('@id'))) {
      // 4.16.1
      var compacted = compactIri(activeContext, value['@id'], vocab: true);
      if (activeContext.terms.containsKey(compacted) &&
          activeContext.terms[compacted]!.iriMapping == value['@id']) {
        preferredValues.add('@vocab');
        preferredValues.add('@id');
        preferredValues.add('@none');
      }
      // 4.16.2
      else {
        preferredValues.add('@id');
        preferredValues.add('@vocab');
        preferredValues.add('@none');
      }
    }

    // 4.17
    else {
      preferredValues.add(typeLanguageValue);
      preferredValues.add('@none');
      if (value is Map && isListObject(value)) {
        var list = value['@list'] as List;
        if (list.isEmpty) {
          typeLanguage = '@any';
        }
      }
    }

    // 4.18
    preferredValues.add('@any');

    // 4.19
    for (var entry in preferredValues) {
      if (entry.contains('_')) {
        preferredValues.add(entry.substring(entry.indexOf('_')));
      }
    }

    // 4.20
    var term = selectTerm(
        activeContext, variable, containers, typeLanguage, preferredValues);

    // 4.21
    if (term != null) {
      return term;
    }
  }

  // 5
  if (vocab && activeContext.vocabularyMapping != null) {
    // 5.1
    if (variable.startsWith(activeContext.vocabularyMapping!) &&
        variable.length > activeContext.vocabularyMapping!.length) {
      var suffix = variable.substring(activeContext.vocabularyMapping!.length);
      if (!activeContext.terms.containsKey(suffix)) {
        return suffix;
      }
    }
  }

  // 6
  var compactIriValue = '';

  // 7
  for (var definitionKey in activeContext.terms.keys) {
    var definition = activeContext.terms[definitionKey]!;
    // 7.1
    if (definition.iriMapping == '' ||
        definition.iriMapping == variable ||
        !variable.startsWith(definition.iriMapping) ||
        definition.prefixFlag == false) {
      continue;
    }
    // 7.2
    var candidate =
        '$definitionKey:${variable.substring(definition.iriMapping.length)}';
    // 7.3
    if (((compactIriValue == '' ||
                (candidate.compareTo(compactIriValue) < 0)) &&
            !activeContext.terms.containsKey(candidate)) ||
        (activeContext.terms[candidate]!.iriMapping == variable &&
            value != null)) {
      compactIriValue = candidate;
    }
  }

  // 8
  if (compactIriValue != '') {
    return compactIriValue;
  }

  // 9
  try {
    var asUrl = Uri.parse(variable);
    if (asUrl.isAbsolute &&
        asUrl.hasScheme &&
        !asUrl.hasAuthority &&
        activeContext.terms[asUrl.scheme] != null &&
        activeContext.terms[asUrl.scheme]!.prefixFlag) {
      throw JsonLdError('IRI confused with prefix');
    }
  } on FormatException catch (_) {}

  // 10
  if (!vocab &&
      activeContext.baseIri.toString() != '' &&
      !variable.startsWith('_:')) {
    if (variable.startsWith(activeContext.baseIri.toString())) {
      variable = variable.substring(activeContext.baseIri.toString().length);
      if (variable.startsWith('/')) {
        variable = variable.substring(1);
      }
    }
  }

  // 11
  return variable;
}
