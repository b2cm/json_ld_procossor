import 'package:json_ld_processor/json_ld_processor.dart';
import 'package:json_ld_processor/src/constants.dart';
import 'package:json_ld_processor/src/context_processing.dart';
import 'package:json_ld_processor/src/utils.dart';

Future<dynamic> expandDoc(
    {required Context activeContext,
    required dynamic activeProperty,
    required dynamic element,
    required Uri baseUrl,
    bool frameExpansion = false,
    bool ordered = false,
    fromMap = false,
    required bool safeMode}) async {
  //1)
  if (element == null) return null;
  //2)
  if (activeProperty == '@default') frameExpansion = false;
  //3)
  dynamic propertyScopedContext;
  if (activeContext.terms.containsKey(activeProperty)) {
    propertyScopedContext = activeContext.terms[activeProperty]!.context;
  }
  //4)
  if (element is String || element is num || element is bool) {
    //4.1
    if (activeProperty == null || activeProperty == '@graph') return null;
    //4.2
    if (propertyScopedContext != null) {
      activeContext = await processContext(
          activeContext: activeContext,
          localContext:
              propertyScopedContext.isEmpty ? null : propertyScopedContext,
          baseUrl: activeContext.terms[activeProperty]!.baseUrl ?? Uri());
    }
    //4.3
    return await expandValue(
        activeContext: activeContext,
        activeProperty: activeProperty,
        value: element);
  }

  if (element is List) {
    return await expandArray(element, activeContext, baseUrl, activeProperty,
        ordered, frameExpansion, fromMap, safeMode);
  }

  //6)
  element = element as Map;
  //7)
  if (activeContext.previousContext != null && !fromMap) {
    bool revert = true;
    for (var key in element.keys.toList()) {
      var expandedKey = await expandIri(
          activeContext: activeContext, value: key, vocab: true);
      if (expandedKey == '@value' ||
          (expandedKey == '@id' && element.length == 1)) {
        revert = false;
        break;
      }
    }
    if (revert) {
      activeContext = activeContext.previousContext!;
    }
  }
  //8)
  if (propertyScopedContext != null) {
    activeContext = await processContext(
        activeContext: activeContext,
        localContext:
            propertyScopedContext.isEmpty ? null : propertyScopedContext,
        baseUrl: activeContext.terms[activeProperty]?.baseUrl ?? Uri(),
        overwriteProtected: true);
  }
  //9)
  if (element.containsKey('@context')) {
    activeContext = await processContext(
        activeContext: activeContext,
        localContext: element['@context'],
        baseUrl: baseUrl);
  }
  //10)
  var typeScopedContext = activeContext;
  //11)
  String? inputType;
  for (var entry in element.entries) {
    var expandedKey = await expandIri(
        activeContext: activeContext, value: entry.key, vocab: true);
    if (expandedKey == '@type') {
      var value = entry.value;
      if (entry.value is! List) {
        value = [value];
      }
      value.sort();
      for (var term in value) {
        if (term is String && typeScopedContext.terms[term]?.context != null) {
          activeContext = await processContext(
              activeContext: activeContext,
              localContext: typeScopedContext.terms[term]?.context,
              baseUrl: typeScopedContext.terms[term]?.baseUrl ?? baseUrl,
              propagate: false);
        }
      }
      //12
      var type = value.last;
      if (type is! String) {
        throw JsonLdError('invalid type value');
      }
      inputType = await expandIri(
          activeContext: activeContext, value: type, vocab: true);
    }
  }
  //12
  var nests = {};
  Map<String, dynamic> result = {};

  //13 & 14
  await expandDocStep1314(
      activeContext: activeContext,
      activeProperty: activeProperty,
      element: element,
      baseUrl: baseUrl,
      result: result,
      nests: nests,
      typeScopedContext: typeScopedContext,
      inputType: inputType,
      safeMode: safeMode);
  //15
  dynamic set;
  if (result.containsKey('@value')) {
    //15.1
    var resultKeys = result.keys;
    var allowedList = ['@direction', '@index', '@language', '@type', '@value'];
    if (!resultKeys.every((element) => allowedList.contains(element))) {
      throw JsonLdError('invalid value object');
    }
    if (result.containsKey('@type')) {
      if (result.containsKey('@language') || result.containsKey('@direction')) {
        throw JsonLdError('invalid value object');
      }
    }
    var valueEntry = result['@value'];
    //15.2 && 15.3
    if (result['@type'] != '@json') {
      if (valueEntry == null || (valueEntry is List && valueEntry.isEmpty)) {
        return null;
      }
      //15.4
      else if (result.containsKey('@language') && valueEntry is! String) {
        throw JsonLdError('invalid language-tagged value');
      }
      //15.5
      else if (result.containsKey('@type')) {
        if (result['@type'] is! String || !isUri(result['@type'])) {
          throw JsonLdError('invalid typed value');
        }
      }
    }
  }
  //16
  else if (result.containsKey('@type')) {
    if (result['@type'] is! List) {
      result['@type'] = [result['@type']];
    }
  }
  //17

  else if (result.containsKey('@set') || result.containsKey('@list')) {
    if (result.length > 2 ||
        result.length == 2 && !result.containsKey('@index')) {
      throw JsonLdError('invalid set or list object');
    }
    if (result.containsKey('@set')) {
      set = result['@set'];
      //result = result['@set'];
    }
  }
  //18
  if (result.length == 1 && result.containsKey('@language')) {
    return null;
  }
  //19
  if (activeProperty == null || activeProperty == '@graph') {
    //19.1
    if (!frameExpansion && result.isEmpty ||
        result.containsKey('@value') ||
        result.containsKey('@list')) {
      return null;
    }
    //19.2
    else if (result.length == 1 &&
        result.containsKey('@id') &&
        !frameExpansion) {
      return null;
    }
  }
  //20
  return set ?? result;
}

Future<void> expandDocStep1314(
    {required Context activeContext,
    required dynamic activeProperty,
    required dynamic element,
    required Uri baseUrl,
    required Map<String, dynamic> result,
    required Map nests,
    required Context typeScopedContext,
    required String? inputType,
    bool frameExpansion = false,
    bool ordered = false,
    fromMap = false,
    required bool safeMode}) async {
  //13)
  var keyList = element.keys.toList();
  if (ordered) keyList.sort();
  for (var key in keyList) {
    var value = element[key];
    dynamic expandedValue;
    //13.1
    if (key == '@context') continue;
    //13.2
    var expandedProperty =
        await expandIri(activeContext: activeContext, value: key, vocab: true);
    //13.3
    if (expandedProperty == null ||
        (!expandedProperty.contains(':') &&
            !keywords.contains(expandedProperty))) {
      if (safeMode) {
        throw JsonLdError('property $key cannot be expanded to IRI or keyword');
      }
      continue;
    }
    //13.4
    if (keywords.contains(expandedProperty)) {
      //13.4.1
      if (activeProperty == '@reverse') {
        throw JsonLdError('invalid reverse property map');
      }
      //13.4.2
      if (result.containsKey(expandedProperty) &&
          nonMatchWordFromList(expandedProperty, ['@type', '@included'])) {
        throw JsonLdError('colliding keywords');
      }
      //13.4.3
      if (expandedProperty == '@id') {
        //13.4.3.1
        if (!frameExpansion && value is! String) {
          throw JsonLdError('invalid @id value');
        }
        //13.4.3.2
        if (frameExpansion && value is List) {
          expandedValue = List.generate(
              value.length,
              (index) => expandIri(
                  activeContext: activeContext,
                  value: value[index],
                  documentRelative: true,
                  vocab: false));
        } else {
          expandedValue = await expandIri(
              activeContext: activeContext,
              value: value,
              documentRelative: true,
              vocab: false);
        }
        result['@id'] = expandedValue;
      }
      //13.4.4
      if (expandedProperty == '@type') {
        if (value is bool || value is num) {
          throw JsonLdError('invalid type value');
        }
        //13.4.4.3
        if (value is String) {
          expandedValue = await expandIri(
              activeContext: typeScopedContext,
              value: value,
              vocab: true,
              documentRelative: true);
        } else if (value is List) {
          try {
            value = value.cast<String>();
          } catch (e) {
            throw JsonLdError('invalid type value');
          }
          expandedValue = [];
          for (var toExpand in value) {
            expandedValue.add(await expandIri(
                activeContext: typeScopedContext,
                value: toExpand,
                vocab: true,
                documentRelative: true));
          }
        } else if (frameExpansion && value is Map) {
          if (value.isEmpty) {
            //13.4.4.2
            value = expandedValue;
          } else if (value.containsKey('@default')) {
            //13.4.4.3
            expandedValue = {
              '@default': await expandIri(
                  activeContext: typeScopedContext,
                  value: value['@default'],
                  vocab: true,
                  documentRelative: true)
            };
          } else {
            throw JsonLdError('invalid type value');
          }
        } else {
          throw JsonLdError('invalid type value');
        }
        //13.4.4.5
        if (result.containsKey('@type')) {
          var priorType = result['@type'];
          var type = [];
          if (priorType is String) {
            type.add(priorType);
          } else {
            type += priorType;
          }
          if (type.isNotEmpty) {
            if (expandedValue is String) {
              type.add(expandedValue);
            } else {
              type += expandedValue;
            }
          }
          result['@type'] = type;
        } else {
          result['@type'] = expandedValue;
        }
      }
      //13.4.5
      if (expandedProperty == '@graph') {
        expandedValue = await expandDoc(
            activeContext: activeContext,
            activeProperty: '@graph',
            element: value,
            baseUrl: baseUrl,
            frameExpansion: frameExpansion,
            ordered: ordered,
            safeMode: safeMode);
        if (expandedValue is! List) {
          expandedValue = [expandedValue];
        }
      }
      //13.4.6
      if (expandedProperty == '@included') {
        //13.4.6.1
        if (activeContext.options.processingMode == 'json-ld-1.0') continue;
        //13.4.6.2
        expandedValue = await expandDoc(
            activeContext: activeContext,
            activeProperty: null,
            element: value,
            baseUrl: baseUrl,
            frameExpansion: frameExpansion,
            ordered: ordered,
            safeMode: safeMode);
        if (expandedValue is! List) {
          expandedValue = [expandedValue];
        }
        //13.4.6.3
        for (var expandedElement in expandedValue) {
          if (!isNodeObject(expandedElement)) {
            throw JsonLdError('invalid @included value');
          }
        }
        //13.4.6.4
        if (result.containsKey('@included')) {
          var priorIncluded = result['@included'];
          result['@included'] = priorIncluded + expandedValue;
        } else {
          result['@included'] = expandedValue;
        }
      }
      //13.4.7
      if (expandedProperty == '@value') {
        //13.4.7.1
        if (inputType == '@json') {
          if (activeContext.options.processingMode == 'json-ld-1.0') {
            throw JsonLdError('invalid value object value');
          }
          expandedValue = value;
        }
        //13.4.7.2
        else if (value is String || value is num || value is bool) {
          expandedValue = value;
        } else if (frameExpansion) {
          if (value is Map && value.isEmpty) {
            expandedValue = value;
          } else if (value is List) {
            expandedValue = value;
          } else {
            throw JsonLdError('invalid value object value');
          }
        } else if (value == null) {
          //13.4.7.4
          result['@value'] = null;
          continue;
        } else {
          throw JsonLdError('invalid value object value');
        }
      }
      //13.4.8
      if (expandedProperty == '@language') {
        if (value is String) {
          expandedValue = value;
        } else if (frameExpansion) {
          if (value is Map && value.isEmpty) {
            expandedValue = value;
          } else if (value is List) {
            try {
              value = value.cast<String>();
            } catch (e) {
              throw JsonLdError('invalid language-tagged string');
            }
            expandedValue = value;
          } else {
            throw JsonLdError('invalid language-tagged string');
          }
        } else {
          throw JsonLdError('invalid language-tagged string');
        }
      }
      //13.4.9
      if (expandedProperty == '@direction') {
        //13.4.9.1
        if (activeContext.options.processingMode == 'json-ld-1.0') continue;
        //13.4.9.2
        if (value == 'ltr' || value == 'rtl') {
          expandedValue = value;
        } else if (frameExpansion) {
          if (value is Map && value.isEmpty) {
            expandedValue = value;
          } else if (value is List) {
            expandedValue = value;
          } else {
            throw JsonLdError('invalid base direction');
          }
        } else {
          throw JsonLdError('invalid base direction');
        }
      }
      //13.4.10
      if (expandedProperty == '@index') {
        if (value is String) {
          expandedValue = value;
        } else {
          throw JsonLdError('invalid @index value');
        }
      }
      //13.4.11
      if (expandedProperty == '@list') {
        //13.4.11.1
        if (activeProperty == null || activeProperty == '@graph') {
          continue;
        }
        //13.4.11.2
        expandedValue = await expandDoc(
            activeContext: activeContext,
            activeProperty: activeProperty,
            element: value,
            baseUrl: baseUrl,
            frameExpansion: frameExpansion,
            ordered: ordered,
            safeMode: safeMode);

        if (expandedValue is! List) {
          expandedValue = [expandedValue];
        }
      }
      //13.4.12
      if (expandedProperty == '@set') {
        expandedValue = await expandDoc(
            activeContext: activeContext,
            activeProperty: activeProperty,
            element: value,
            baseUrl: baseUrl,
            frameExpansion: frameExpansion,
            ordered: ordered,
            safeMode: safeMode);
      }
      //13.4.13
      if (expandedProperty == '@reverse') {
        //13.4.13.1
        if (value is! Map) {
          throw JsonLdError('invalid @reverse value');
        }
        //13.4.13.2
        expandedValue = await expandDoc(
            activeContext: activeContext,
            activeProperty: '@reverse',
            element: value,
            baseUrl: baseUrl,
            frameExpansion: frameExpansion,
            ordered: ordered,
            safeMode: safeMode);
        //13.4.13.3
        if (expandedValue is Map) {
          if (expandedValue.containsKey('@reverse')) {
            expandedValue['@reverse'].forEach((property, item) {
              addValue(
                  object: result, key: property, value: item, asArray: true);
            });
          }
          //13.4.13.4
          if (expandedValue.length > 1 ||
              !expandedValue.containsKey('@reverse')) {
            //13.4.13.4.1
            var reverseMap = result['@reverse'] ?? {};
            //13.4.13.4.2
            expandedValue.forEach((property, items) {
              if (property == '@reverse') {
              } else {
                //13.4.13.4.2.1
                if (items is List) {
                  for (var item in items) {
                    //13.4.13.4.2.1.1
                    if ((item is Map && item.containsKey('@value')) ||
                        isListObject(item)) {
                      throw JsonLdError('invalid reverse property value');
                    }
                    //13.4.13.4.2.1.2
                    addValue(
                        object: reverseMap,
                        key: property,
                        value: item,
                        asArray: true);
                  }
                }
              }

              if (reverseMap.isNotEmpty) {
                result['@reverse'] = reverseMap;
              } else {
                result.remove('@reverse');
              }
            });
            //13.4.13.5
            continue;
          }
        }
      }
      //13.4.14
      if (expandedProperty == '@nest') {
        if (!nests.containsKey(key)) {
          nests[key] = [];
        }
        continue;
      }
      //13.4.15
      if (frameExpansion && framingKeywords.contains(expandedProperty)) {
        expandedValue = await expandDoc(
            activeContext: activeContext,
            activeProperty: activeProperty,
            element: value,
            baseUrl: baseUrl,
            frameExpansion: frameExpansion,
            ordered: ordered,
            safeMode: safeMode);
      }
      //13.4.16
      if (expandedValue != null ||
          (expandedProperty == '@value' && inputType == '@json')) {
        if (!result.containsKey(expandedProperty) &&
            expandedProperty != '@reverse') {
          result[expandedProperty] = expandedValue;
        }
      }
      //13.4.17
      continue;
    }
    //13.5
    var containerMapping = activeContext.terms[key]?.containerMapping;
    //13.6
    var typeMapping = activeContext.terms[key]?.typeMapping;
    if (typeMapping != null && typeMapping == '@json') {
      expandedValue = {'@value': value, '@type': '@json'};
    }
    //13.7
    else if (containerMapping != null &&
        containerMapping.contains('@language') &&
        value is Map) {
      //13.7.1
      expandedValue = [];
      //13.7.2
      var direction = activeContext.defaultBaseDirection;
      //13.7.3
      var newDir = activeContext.terms[key]?.directionMapping;
      if (newDir != null) {
        direction = newDir == '' ? null : newDir;
      }
      //13.7.4
      var languageList = value.keys.toList();
      if (ordered) {
        languageList.sort();
      }
      for (var language in languageList) {
        var languageValue = value[language];
        //13.7.4.1
        if (languageValue is! List) {
          languageValue = [languageValue];
        }
        //13.7.4.2
        for (var item in languageValue) {
          //13.7.4.2.1
          if (item == null) continue;
          //13.7.4.2.2
          if (item is! String) {
            throw JsonLdError('invalid language map value');
          }
          //13.7.4.2.3
          var v = {'@value': item, '@language': language};
          //13.7.4.2.4
          if (language == '@none' ||
              (await expandIri(
                      activeContext: activeContext, value: language)) ==
                  '@none') {
            v.remove('@language');
          }
          //13.7.4.2.5
          if (direction != null) {
            v['@direction'] = direction;
          }
          //13.7.4.2.6
          expandedValue.add(v);
        }
      }
    }
    //13.8
    else if (containerMapping != null &&
        value is Map &&
        (containerMapping.contains('@index') ||
            containerMapping.contains('@id') ||
            containerMapping.contains('@type'))) {
      //13.8.1
      expandedValue = [];
      //13.8.2
      var indexKey = activeContext.terms[key]?.indexMapping ?? '@index';
      //13.8.3
      var indexKeys = value.keys.toList();
      if (ordered) {
        indexKeys.sort();
      }
      for (var index in indexKeys) {
        var indexValue = value[index];
        //13.8.3.1
        Context mapContext = activeContext;
        if (containerMapping.contains('@id') ||
            containerMapping.contains('@type')) {
          mapContext = activeContext.previousContext ?? activeContext;
        }
        //13.8.3.2
        if (containerMapping.contains('@type') &&
            mapContext.terms[index]?.context != null) {
          mapContext = await processContext(
              activeContext: mapContext,
              localContext: mapContext.terms[index]?.context,
              baseUrl: mapContext.terms[index]?.baseUrl ?? baseUrl);
        }
        //13.8.3.3 -> not necessary

        //13.8.3.4
        var expandedIndex = await expandIri(
            activeContext: activeContext, value: index, vocab: true);
        //13.8.3.5
        if (indexValue is! List) {
          indexValue = [indexValue];
        }
        //13.8.3.6
        indexValue = await expandDoc(
            activeContext: mapContext,
            activeProperty: key,
            element: indexValue,
            baseUrl: baseUrl,
            fromMap: true,
            ordered: ordered,
            frameExpansion: frameExpansion,
            safeMode: safeMode);
        //13.8.3.7
        if (indexValue is! List) {
          indexValue = [indexValue];
        }
        for (var item in indexValue) {
          //13.8.3.7.1
          if (item is Map) {
            if (containerMapping.contains('@graph') && !isGraphObject(item)) {
              item = {
                '@graph': item is List ? item : [item]
              };
            }
          }
          //13.8.3.7.2
          if (containerMapping.contains('@index') &&
              indexKey != '@index' &&
              expandedIndex != '@none') {
            //13.8.3.7.2.1
            var reExpandedIndex = await expandValue(
                activeContext: activeContext,
                activeProperty: indexKey,
                value: index);
            //13.8.3.7.2.2
            var expandedIndexKey = await expandIri(
                activeContext: activeContext, value: indexKey, vocab: true);
            //13.8.3.7.2.3
            List<dynamic> indexPropertyValues = [reExpandedIndex];
            if (item is Map) {
              var existingValues = item[expandedIndexKey];
              if (existingValues != null) {
                if (existingValues is List) {
                  indexPropertyValues += existingValues;
                } else {
                  indexPropertyValues.add(existingValues);
                }
              }
              //13.8.3.7.2.4
              item[expandedIndexKey] = indexPropertyValues;
              //13.8.3.7.2.5
              if (item.containsKey('@value') && item.length > 1) {
                throw JsonLdError('invalid value object');
              }
            }
          }
          //13.8.3.7.3
          else if (containerMapping.contains('@index') &&
              item is Map &&
              !item.containsKey('@index') &&
              expandedIndex != '@none') {
            item['@index'] = index;
          }
          //13.8.3.7.4
          else if (containerMapping.contains('@id') &&
              item is Map &&
              !item.containsKey('@id') &&
              expandedIndex != '@none') {
            item['@id'] = await expandIri(
                activeContext: activeContext,
                value: index,
                documentRelative: true,
                vocab: false);
          }
          //13.8.3.7.5
          else if (containerMapping.contains('@type') &&
              expandedIndex != '@none') {
            List<dynamic> types = [expandedIndex];
            var existingTypes = item['@type'];
            if (existingTypes != null) {
              if (existingTypes is List) {
                types += existingTypes;
              } else {
                types.add(existingTypes);
              }
            }
            item['@type'] = types;
          }
          //13.8.3.7.6
          expandedValue.add(item);
        }
      }
    }
    //13.9
    else {
      expandedValue = await expandDoc(
          activeContext: activeContext,
          activeProperty: key,
          element: value,
          baseUrl: baseUrl,
          frameExpansion: frameExpansion,
          ordered: ordered,
          safeMode: safeMode);
    }
    //13.10
    if (expandedValue == null) continue;
    //13.11
    containerMapping = activeContext.terms[key]?.containerMapping;
    if (containerMapping != null &&
        containerMapping.contains('@list') &&
        !isListObject(expandedValue)) {
      if (expandedValue is! List) {
        expandedValue = [expandedValue];
      }
      expandedValue = {'@list': expandedValue} as Map;
    }
    //13.12
    if (containerMapping != null &&
        containerMapping.contains('@graph') &&
        !containerMapping.contains('@id') &&
        !containerMapping.contains('@index')) {
      if (expandedValue is! List) {
        expandedValue = [expandedValue];
      }
      var newEv = [];
      for (var ev in expandedValue) {
        newEv.add({
          '@graph': ev is List ? ev : [ev]
        });
      }
      expandedValue = newEv;
    }
    //13.13
    if (activeContext.terms[key] != null &&
        activeContext.terms[key]!.reverseProperty) {
      //13.13.1 & 13.3.2
      Map<String, dynamic> reverseMap = result['@reverse'] ?? {};
      //13.13.3
      if (expandedValue is! List) {
        expandedValue = [expandedValue];
      }
      //13.13.4
      for (var item in expandedValue) {
        //13.13.4.1
        if (isListObject(item) || (item is Map && item.containsKey('@value'))) {
          throw JsonLdError('invalid reverse property value');
        }
        //13.13.4.2
        reverseMap.putIfAbsent(expandedProperty, () => []);
        //13.13.4.3
        addValue(
            object: reverseMap,
            key: expandedProperty,
            value: item,
            asArray: true);
      }

      result['@reverse'] = reverseMap;
    }
    //13.14
    else {
      addValue(
          object: result,
          key: expandedProperty,
          value: expandedValue,
          asArray: true);
    }
  }
  //14
  if (nests.isNotEmpty) {
    var nestingKeys = nests.keys.toList();
    if (ordered) nestingKeys.sort();
    for (var nestingKey in nestingKeys) {
      //14.1
      var nestedValues = element[nestingKey];
      if (nestedValues is! List) nestedValues = [nestedValues];
      //14.2
      for (var nestedValue in nestedValues) {
        //14.2.1
        if (nestedValue is! Map) {
          throw JsonLdError('invalid @nest value');
        }
        for (var nestedValueKey in nestedValue.keys) {
          if (await expandIri(
                  activeContext: activeContext,
                  value: nestedValueKey as String,
                  vocab: true) ==
              '@value') {
            throw JsonLdError('invalid @nest value');
          }
        }
        //14.2.2
        await expandDocStep1314(
            activeContext: activeContext,
            activeProperty: activeProperty,
            element: nestedValue,
            baseUrl: baseUrl,
            result: result,
            nests: {},
            typeScopedContext: typeScopedContext,
            inputType: inputType,
            safeMode: safeMode);
      }
    }
  }
}

expandArray(
    List<dynamic> element,
    Context activeContext,
    Uri baseUrl,
    dynamic activeProperty,
    bool ordered,
    bool frameExpansion,
    bool fromMap,
    bool safeMode) async {
  //5)
  //5.1
  var result = [];
  //5.2
  for (var item in element) {
    //5.2.1
    var expandedItem = await expandDoc(
        activeContext: activeContext,
        activeProperty: activeProperty,
        element: item,
        baseUrl: baseUrl,
        frameExpansion: frameExpansion,
        ordered: ordered,
        fromMap: fromMap,
        safeMode: safeMode);
    //5.2.2
    if (activeContext.terms[activeProperty]?.containerMapping != null &&
        activeContext.terms[activeProperty]!.containerMapping!
            .contains('@list') &&
        expandedItem is List) {
      expandedItem = {'@list': expandedItem} as Map;
    }
    //5.2.3
    if (expandedItem != null) {
      if (expandedItem is List) {
        result += expandedItem;
      } else {
        result.add(expandedItem);
      }
    }
  }
  //5.3
  return result;
}

Future<String?> expandIri(
    {required Context activeContext,
    required String value,
    bool documentRelative = false,
    bool vocab = false,
    Map<String, dynamic>? localContext,
    Map<String, bool>? defined}) async {
  //short for 1) and 2) without warning.
  if (keywords.contains(value)) return value;
  if (keyWordMatcher.hasMatch(value)) return null;
  //3)
  if (localContext != null) {
    if (localContext.containsKey(value) && !(defined!.containsKey(value))) {
      await createTermDefinition(
          activeContext: activeContext,
          localContext: localContext,
          term: value,
          defined: defined);
    }
  }
  //4)
  if (activeContext.terms.containsKey(value) &&
      activeContext.terms[value]!.iriMapping.startsWith('@')) {
    return activeContext.terms[value]!.iriMapping;
  }

  //5)
  if (vocab && activeContext.terms.containsKey(value)) {
    return activeContext.terms[value]!.iriMapping;
  }

  //6)
  if (value.contains(':')) {
    //6.1)
    var firstColon = value.indexOf(':');
    var prefix = value.substring(0, firstColon);
    var suffix = value.substring(firstColon + 1);
    //6.2)
    if (prefix == '_' || suffix.startsWith('//')) {
      return value;
    }
    //6.3)
    if (localContext != null) {
      if (localContext.containsKey(prefix) && !(defined!.containsKey(value))) {
        await createTermDefinition(
            activeContext: activeContext,
            localContext: localContext,
            term: prefix,
            defined: defined);
      }
    }
    //6.4)
    if (activeContext.terms.containsKey(prefix)) {
      var prefixTerm = activeContext.terms[prefix];
      if (prefixTerm!.prefixFlag) {
        return prefixTerm.iriMapping + suffix;
      }
    }
    //6.5)
    if (value.startsWith('_:') || isAbsoluteUri(value)) {
      return value;
    }
  }

  //7)
  if (vocab && activeContext.vocabularyMapping != null) {
    return activeContext.vocabularyMapping! + value;
  }

  //8)
  if (documentRelative) {
    value = activeContext.baseIri.resolve(value).toString();
  }

  //9)
  return value;
}

Future<Map<String, dynamic>> expandValue(
    {required Context activeContext,
    required dynamic activeProperty,
    required dynamic value}) async {
  var termDef = activeContext.terms[activeProperty];
  //1)
  if (termDef != null && termDef.typeMapping != null && value is String) {
    if (termDef.typeMapping == '@id') {
      return {
        '@id': await expandIri(
            activeContext: activeContext,
            value: value,
            documentRelative: true,
            vocab: false)
      };
    }
    //2)
    if (termDef.typeMapping == '@vocab') {
      return {
        '@id': await expandIri(
            activeContext: activeContext,
            value: value,
            documentRelative: true,
            vocab: true)
      };
    }
  }
  //3)
  var result = {'@value': value};

  //4)
  if (termDef != null &&
      termDef.typeMapping != null &&
      termDef.typeMapping != '@id' &&
      termDef.typeMapping != '@vocab' &&
      termDef.typeMapping != '@none') {
    result['@type'] = termDef.typeMapping;
  }
  //5)
  else if (value is String) {
    var lang = termDef?.languageMapping ?? activeContext.defaultLanguage;
    var dir = termDef?.directionMapping ?? activeContext.defaultBaseDirection;
    if (lang != null && lang != '') result['@language'] = lang;
    if (dir != null && dir != '') result['@direction'] = dir;
  }
  //6)
  return result;
}
