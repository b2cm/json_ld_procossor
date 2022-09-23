import 'package:json_ld_processor/json_ld_processor.dart';
import 'package:json_ld_processor/src/constants.dart';
import 'package:json_ld_processor/src/expansion.dart';
import 'package:json_ld_processor/src/utils.dart';

class Context {
  Map<String, ContextTermDefinition> terms;
  Uri baseIri, originalBaseIri;
  Map<String, dynamic>? inverseContext;
  String? vocabularyMapping, defaultLanguage, defaultBaseDirection;
  Context? previousContext;
  JsonLdOptions options;

  Context(
      {required this.terms,
      required this.baseIri,
      required this.originalBaseIri,
      required this.options,
      this.defaultBaseDirection,
      this.defaultLanguage,
      this.inverseContext,
      this.previousContext,
      this.vocabularyMapping});

  bool _compareTerms(Map<String, ContextTermDefinition> other) {
    for (var key in terms.keys.toList()) {
      var v2 = other[key];
      if (v2 == null) {
        return false;
      }
      if (v2 != terms[key]) return false;
    }
    return true;
  }

  Context copyOf() {
    return Context(
        terms: Map.from(terms),
        baseIri: baseIri,
        originalBaseIri: originalBaseIri,
        options: options,
        defaultBaseDirection: defaultBaseDirection,
        defaultLanguage: defaultLanguage,
        inverseContext:
            inverseContext == null ? null : Map.from(inverseContext!),
        vocabularyMapping: vocabularyMapping,
        previousContext:
            previousContext == null ? null : previousContext!.copyOf());
  }

  @override
  bool operator ==(Object other) {
    if (other is Context) {
      return _compareTerms(other.terms) &&
          baseIri == other.baseIri &&
          originalBaseIri == other.originalBaseIri &&
          defaultBaseDirection == other.defaultBaseDirection &&
          defaultLanguage == other.defaultLanguage &&
          compareJsonLd(inverseContext, other.inverseContext) &&
          previousContext == other.previousContext &&
          vocabularyMapping == other.vocabularyMapping;
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      baseIri.hashCode +
      originalBaseIri.hashCode +
      defaultBaseDirection.hashCode +
      defaultLanguage.hashCode;
}

class ContextTermDefinition {
  String iriMapping;
  bool prefixFlag, protected, reverseProperty;
  Uri? baseUrl;
  dynamic context;
  List<String>? containerMapping;
  String? directionMapping,
      indexMapping,
      languageMapping,
      nestValue,
      typeMapping;

  ContextTermDefinition(
      {required this.iriMapping,
      required this.prefixFlag,
      required this.protected,
      required this.reverseProperty,
      this.baseUrl,
      this.context,
      this.containerMapping,
      this.directionMapping,
      this.indexMapping,
      this.languageMapping,
      this.nestValue,
      this.typeMapping});

  @override
  bool operator ==(Object other) {
    if (other is ContextTermDefinition) {
      return iriMapping == other.iriMapping &&
          prefixFlag == other.prefixFlag &&
          baseUrl == other.baseUrl &&
          compareJsonLd(context, other.context) &&
          directionMapping == other.directionMapping &&
          indexMapping == other.indexMapping &&
          languageMapping == other.languageMapping &&
          nestValue == other.nestValue &&
          typeMapping == other.typeMapping &&
          compareList(containerMapping, other.containerMapping);
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      iriMapping.hashCode + prefixFlag.hashCode + baseUrl.hashCode;
}

Future<Context> processContext(
    {required Context activeContext,
    required dynamic localContext,
    required Uri baseUrl,
    List<String>? remoteContexts,
    bool overwriteProtected = false,
    bool propagate = true,
    bool validateScopedContext = true}) async {
  // 1)
  var result = activeContext.copyOf();
  result.inverseContext = null;

  //2)
  if (localContext is Map) {
    if (localContext.containsKey('@propagate')) {
      var propagateValue = localContext['@propagate'];
      if (propagateValue is bool) {
        propagate = localContext['@propagate'];
      }
    }
  }
  //3)
  if (!propagate && result.previousContext == null) {
    result.previousContext = activeContext;
  }

  //4
  List<dynamic> localContextList;
  if (localContext is List) {
    localContextList = localContext;
  } else {
    localContextList = [localContext];
  }

  //5)
  for (var contextItem in localContextList) {
    // 5.1)
    if (contextItem == null) {
      //5.1.1)
      if (!overwriteProtected) {
        activeContext.terms.forEach((key, value) {
          if (value.protected) {
            throw JsonLdError('invalid context nullification');
          }
        });
      }
      //5.1.2)
      result = Context(
          terms: {},
          baseIri: activeContext.originalBaseIri,
          originalBaseIri: activeContext.originalBaseIri,
          options: activeContext.options,
          previousContext: propagate ? null : result.previousContext);
      //5.1.3)
      continue;
    }
    //5.2)
    if (contextItem is String) {
      //5.2.1
      var contextUri = activeContext.baseIri.resolve(contextItem);
      //5.2.2
      if (!validateScopedContext &&
          remoteContexts != null &&
          remoteContexts.contains(contextUri.toString())) {
        continue;
      }
      //5.2.3
      if (remoteContexts != null && remoteContexts.length > 10) {
        throw JsonLdError('context overflow');
      }
      remoteContexts == null
          ? [contextUri.toString()]
          : remoteContexts.add(contextUri.toString());
      //5.2.4 TODO: maybe cache?
      //5.2.5
      RemoteDocument contextDocument;
      try {
        contextDocument = await activeContext.options.documentLoader
            .call(contextUri, LoadDocumentOptions());
      } catch (e) {
        throw JsonLdError('loading remote context failed: $e');
      }
      if (contextDocument.document is! Map ||
          !contextDocument.document.containsKey('@context')) {
        throw JsonLdError('invalid remote context');
      }
      //5.2.6
      result = await processContext(
          activeContext: result,
          localContext: contextDocument.document['@context'],
          baseUrl: baseUrl,
          remoteContexts:
              remoteContexts != null ? List.from(remoteContexts) : null,
          validateScopedContext: validateScopedContext);
      //5.2.7
      continue;
    }
    //5.3
    if (contextItem is! Map) throw JsonLdError('invalid local context');
    //5.4 contextItem is Map
    //5.5)
    if (contextItem.containsKey('@version')) {
      var value = contextItem['@version'];
      //5.5.1
      if (value != 1.1) throw JsonLdError('invalid @version value');
      //5.5.2
      if (activeContext.options.processingMode == 'json-ld-1.0') {
        throw JsonLdError('processing mode conflict');
      }
    }

    //5.6
    if (contextItem.containsKey('@import')) {
      //5.6.1
      if (activeContext.options.processingMode == 'json-ld-1.0') {
        throw JsonLdError('invalid context entry');
      }
      //5.6.2
      var import = contextItem['@import'];
      if (import is! String) {
        throw JsonLdError('invalid @import value');
      }
      //5.6.4
      RemoteDocument resolved;
      if (!isAbsoluteUri(import)) {
        import = baseUrl.resolve(import);
      }
      try {
        resolved = await activeContext.options.documentLoader.call(
            import,
            LoadDocumentOptions(
                profile: ' http://www.w3.org/ns/json-ld#context',
                requestProfile: ['http://www.w3.org/ns/json-ld#context']));
      } catch (e) {
        //5.6.5
        throw JsonLdError('loading remote context failed');
      }
      //5.6.6
      var document = resolved.document;
      if (document is! Map) {
        throw JsonLdError('invalid remote context');
      }
      if (document.containsKey('@context')) {
        var importContext = document['@context'];
        if (importContext is! Map) {
          throw JsonLdError('invalid remote context');
        }
        //5.6.7
        if (importContext.containsKey('@import')) {
          throw JsonLdError('invalid context entry');
        }
        //5.6.8
        importContext.addAll(contextItem);
        contextItem = importContext;
      } else {
        throw JsonLdError('invalid remote context');
      }
    }

    //5.7
    if (contextItem.containsKey('@base') &&
        (remoteContexts == null || remoteContexts.isEmpty)) {
      //5.7.1
      var value = contextItem['@base'];
      //5.7.2
      if (value == null) {
        result.baseIri = Uri();
      }
      //5.7.3
      else if (value is String) {
        var asUri = Uri.parse(value);
        if (asUri.isAbsolute) {
          result.baseIri = asUri;
        } else {
          if (result.baseIri != Uri()) {
            result.baseIri = result.baseIri.resolveUri(asUri);
          }
        }
      } else {
        throw JsonLdError('invalid base IRI');
      }
    }

    //5.8)
    if (contextItem.containsKey('@vocab')) {
      //5.8.1
      var value = contextItem['@vocab'];
      //5.8.2
      if (value == null) {
        result.vocabularyMapping = null;
      } else if (value is String && (isUri(value) || value.startsWith('_:'))) {
        //5.8.3
        var vocabIri = await expandIri(
            activeContext: result,
            value: value,
            documentRelative: true,
            vocab: true);
        if (isUri(vocabIri) || vocabIri!.startsWith('_:')) {
          result.vocabularyMapping = vocabIri;
        } else {
          throw JsonLdError('invalid vocab mapping');
        }
      } else {
        throw JsonLdError('invalid vocab mapping');
      }
    }

    //5.9)
    if (contextItem.containsKey('@language')) {
      //5.9.1
      var value = contextItem['@language'];
      //5.9.2
      if (value == null) {
        result.defaultLanguage = null;
      } else if (value is String) {
        //5.9.3
        result.defaultLanguage = value;
      } else {
        throw JsonLdError('invalid default language');
      }
    }

    //5.10
    if (contextItem.containsKey('@direction')) {
      //5.10.1
      if (activeContext.options.processingMode == 'json-ld-1.0') {
        throw JsonLdError('invalid context entry');
      }
      //5.10.2
      var value = contextItem['@direction'];
      //5.10.3
      if (value == null) {
        result.defaultBaseDirection = null;
      } else if (value is String && (value == 'ltr' || value == 'rtl')) {
        result.defaultBaseDirection = value;
      } else {
        throw JsonLdError('invalid base direction');
      }
    }

    //5.11
    if (contextItem.containsKey('@propagate')) {
      //5.11.1
      if (activeContext.options.processingMode == 'json-ld-1.0') {
        throw JsonLdError('invalid context entry');
      }
      //5.11.2
      else {
        var propagateValue = contextItem['@propagate'];
        if (propagateValue is! bool) {
          throw JsonLdError('invalid @propagate value');
        }
      }
    }

    //5.12
    Map<String, bool> defined = {};
    //5.13
    var keys = contextItem.keys.toList();
    for (var key in keys) {
      List<String> forbidden = [
        '@base',
        '@direction',
        '@import',
        '@language',
        '@propagate',
        '@protected',
        '@version',
        '@vocab'
      ];
      if (!forbidden.contains(key)) {
        await createTermDefinition(
            activeContext: result,
            localContext: contextItem as Map<String, dynamic>,
            term: key,
            defined: defined,
            baseUrl: baseUrl,
            remoteContexts:
                remoteContexts != null ? List.from(remoteContexts) : null,
            protected: contextItem['@protected'] ?? false,
            overwriteProtected: overwriteProtected);
      }
    }
  }
  //6)
  return result;
}

Future<void> createTermDefinition(
    {required Context activeContext,
    required Map<String, dynamic> localContext,
    required String term,
    required Map<String, bool> defined,
    Uri? baseUrl,
    bool protected = false,
    bool overwriteProtected = false,
    List<String>? remoteContexts,
    bool validateScope = true}) async {
  remoteContexts ??= [];

  //1)

  if (defined[term] != null) {
    if (defined[term]!) {
      return;
    } else {
      throw JsonLdError('cyclic IRI mapping');
    }
  }

  //2)
  if (term == '') throw JsonLdError('invalid term definition');
  defined[term] = false;
  //3)
  var value = localContext[term];

  //4)
  if (term == '@type') {
    if (activeContext.options.processingMode == 'json-ld-1.0') {
      throw JsonLdError('keyword redefinition');
    }
    if (value is Map) {
      if (value.length == 1 && value.containsKey('@container')) {
        var containerValue = value['@container'];
        if (containerValue != '@set') {
          throw JsonLdError('keyword redefinition');
        }
      } else if (value.length == 2 &&
          value.containsKey('@container') &&
          value.containsKey('@protected')) {
        var containerValue = value['@container'];
        if (containerValue != '@set') {
          throw JsonLdError('keyword redefinition');
        }
      } else if (value.length != 1 && !value.containsKey('@protected')) {
        throw JsonLdError('keyword redefinition');
      }
    } else {
      throw JsonLdError('keyword redefinition');
    }
  }
  //5)
  else if (keywords.contains(term)) {
    throw JsonLdError('keyword redefinition');
  } else if (keyWordMatcher.hasMatch(term)) {
    return;
  }
  //6)
  ContextTermDefinition? previousDefinition;
  if (activeContext.terms.containsKey(term)) {
    previousDefinition = activeContext.terms.remove(term);
  }
  //7)
  Map<dynamic, dynamic> valueMap = {};
  bool simpleTerm = false;
  if (value == null) {
    valueMap = {'@id': null};
    simpleTerm = false;
  }
  //8)
  else if (value is String) {
    valueMap = {'@id': value};
    simpleTerm = true;
  }
  //9)
  else if (value is! Map) {
    throw JsonLdError('invalid term definition');
  } else {
    valueMap.addAll(value);
  }
  //10)
  ContextTermDefinition definition = ContextTermDefinition(
      iriMapping: '',
      prefixFlag: false,
      protected: protected,
      reverseProperty: false);
  //11)
  if (valueMap.containsKey('@protected')) {
    var protected = valueMap['@protected'];
    if (protected is bool) {
      definition.protected = protected;
    } else {
      throw JsonLdError('invalid @protected value');
    }
    if (activeContext.options.processingMode == 'json-ld-1.0') {
      throw JsonLdError('invalid @protected value');
    }
  }
  //12)
  if (valueMap.containsKey('@type')) {
    //12.1)
    var type = valueMap['@type'];
    if (type is! String) throw JsonLdError('invalid type mapping');
    //12.2)
    type = await expandIri(
        activeContext: activeContext,
        value: type,
        defined: defined,
        localContext: localContext,
        vocab: true);
    //12.3)
    if (((type == '@json' || type == '@none') &&
            activeContext.options.processingMode == 'json-ld-1.0') ||
        nonMatchWordFromList(type, ['@id', '@vocab', '@json', '@none']) &&
            (!isAbsoluteUri(type))) {
      throw JsonLdError('invalid type mapping');
    }
    //12.5)
    definition.typeMapping = type;
  }
  //13)
  if (valueMap.containsKey('@reverse')) {
    //13.1)
    if (valueMap.containsKey('@id') || valueMap.containsKey('@nest')) {
      throw JsonLdError('invalid reverse property');
    }
    //13.2
    var reverse = valueMap['@reverse'];
    if (reverse is! String) {
      throw JsonLdError('invalid IRI mapping');
    }
    //13.3)
    if (keyWordMatcher.hasMatch(reverse)) return;
    //13.4)
    var iri = await expandIri(
        activeContext: activeContext,
        value: reverse,
        localContext: localContext,
        defined: defined,
        vocab: true);
    if (!isUri(iri)) {
      throw JsonLdError(('invalid IRI mapping'));
    }
    definition.iriMapping = iri!;
    //13.5
    if (valueMap.containsKey('@container')) {
      var container = valueMap['@container'];
      if (container != null && container is! String) {
        throw JsonLdError('invalid reverse property');
      }
      if (container is String) {
        if (container == '@set' || container == '@index') {
          definition.containerMapping = [container];
        } else {
          throw JsonLdError('invalid reverse property');
        }
      }
    }
    //13.6)
    definition.reverseProperty = true;
    //13.7)
    activeContext.terms[term] = definition;
    defined[term] = true;
    return;
  }

  //14)
  if (valueMap.containsKey('@id') && valueMap['@id'] != term) {
    //14.1)
    if (valueMap['@id'] == null) {
    }
    //14.2)
    else {
      //14.2.1
      var id = valueMap['@id'];
      if (id is! String) {
        throw JsonLdError('invalid IRI mapping');
      }
      //14.2.2
      if (keyWordMatcher.hasMatch(id) && !keywords.contains(id)) return;
      //14.2.3
      var iri = await expandIri(
          activeContext: activeContext,
          value: id,
          localContext: localContext,
          defined: defined,
          vocab: true);
      if (!keywords.contains(iri) && !isUri(iri) && !iri!.startsWith('_:')) {
        throw JsonLdError('invalid IRI mapping');
      }
      definition.iriMapping = iri!;
      if (definition.iriMapping == '@context') {
        throw JsonLdError('invalid keyword alias');
      }
      //14.2.4
      if (term != '' &&
          (term.contains('/') ||
              term.substring(0, term.length).contains(':', 1))) {
        //14.2.4.1
        defined[term] = true;
        activeContext.terms[term] = definition;
        //14.2.4.2
        var newExpand = await expandIri(
            activeContext: activeContext,
            value: term,
            localContext: localContext,
            defined: defined,
            vocab: true);
        if (newExpand != definition.iriMapping) {
          throw JsonLdError('invalid IRI mapping');
        }
      }
      //14.2.5
      if (!term.contains(':') && !term.contains('/') && simpleTerm) {
        if (genDelims.contains(
                definition.iriMapping[definition.iriMapping.length - 1]) ||
            definition.iriMapping.startsWith('_:')) {
          definition.prefixFlag = true;
        }
      }
    }
  }

  //15
  else if (term.contains(':', 1)) {
    //15.1
    var splitIndex = term.indexOf(':', 1);
    String? termPrefix;
    if (splitIndex != -1) {
      termPrefix = term.substring(0, splitIndex);
    }
    if (termPrefix != null &&
        !termPrefix.startsWith('_') &&
        localContext.containsKey(termPrefix)) {
      await createTermDefinition(
          activeContext: activeContext,
          localContext: localContext,
          term: termPrefix,
          defined: defined);
    }
    //15.2
    if (termPrefix != null &&
        !termPrefix.startsWith('_') &&
        activeContext.terms.containsKey(termPrefix)) {
      var substringIndex = term.substring(1).indexOf(':');
      definition.iriMapping = activeContext.terms[termPrefix]!.iriMapping +
          term.substring(substringIndex + 2);
    }
    //15.3
    else if (term.startsWith('_') || isUri(term)) {
      definition.iriMapping = term;
    }
  }
  //16)
  else if (term.contains('/')) {
    //16.2
    var iri = await expandIri(
        activeContext: activeContext,
        value: term,
        localContext: localContext,
        defined: defined,
        vocab: true);
    if (!isAbsoluteUri(iri)) {
      throw JsonLdError('invalid IRI mapping');
    }
    definition.iriMapping = iri!;
  }
  //17)
  else if (term == '@type') {
    definition.iriMapping = '@type';
  }
  //18)
  else if (activeContext.vocabularyMapping == null) {
    throw JsonLdError('invalid IRI mapping');
  } else {
    definition.iriMapping = activeContext.vocabularyMapping! + term;
  }

  //19)
  if (valueMap.containsKey('@container')) {
    //19.1
    var container = valueMap['@container'];
    if (!validateContainer(container, activeContext)) {
      throw JsonLdError('invalid container mapping');
    }
    //19.3)
    if (container is List) {
      container = container.cast<String>();
    }
    definition.containerMapping = container is String ? [container] : container;
    //19.4
    if (definition.containerMapping!.contains('@type')) {
      //19.4.1
      definition.typeMapping ??= '@id';
      //19.4.2
      if (!(definition.typeMapping == '@id' ||
          definition.typeMapping == '@vocab')) {
        throw JsonLdError('invalid type mapping');
      }
    }
  }
  //20)
  if (valueMap.containsKey('@index')) {
    //20.1
    if (activeContext.options.processingMode == 'json-ld-1.0' ||
        definition.containerMapping == null ||
        !definition.containerMapping!.contains('@index')) {
      throw JsonLdError('invalid term definition');
    }
    //20.2
    var index = valueMap['@index'];
    try {
      var expand = await expandIri(
          activeContext: activeContext,
          value: index,
          localContext: localContext,
          vocab: true,
          defined: defined);
      if (keywords.contains(expand) || !isUri(expand)) {
        throw JsonLdError('invalid term definition');
      }
    } catch (e) {
      throw JsonLdError('invalid term definition');
    }
    //20.3
    definition.indexMapping = index;
  }
  //21
  if (valueMap.containsKey('@context')) {
    //21.1
    if (activeContext.options.processingMode == 'json-ld-1.0') {
      throw JsonLdError('invalid term definition');
    }
    //21.2
    var context = valueMap['@context'];
    var oldContext = Context(
        terms: Map.from(activeContext.terms),
        baseIri: activeContext.baseIri,
        originalBaseIri: activeContext.originalBaseIri,
        options: activeContext.options,
        previousContext: activeContext.previousContext,
        vocabularyMapping: activeContext.vocabularyMapping,
        defaultLanguage: activeContext.defaultLanguage,
        defaultBaseDirection: activeContext.defaultBaseDirection,
        inverseContext: activeContext.inverseContext);
    //21.3
    try {
      await processContext(
          activeContext: oldContext,
          localContext:
              context is Map ? Map<String, dynamic>.from(context) : context,
          baseUrl: baseUrl ?? Uri(),
          overwriteProtected: true,
          remoteContexts: List.from(remoteContexts),
          validateScopedContext: false);
    } catch (e) {
      throw JsonLdError('invalid scoped context');
    }
    //21.4
    definition.context = context ?? {};
    definition.baseUrl = baseUrl;
  }
  //22)
  if (valueMap.containsKey('@language') && !valueMap.containsKey('@type')) {
    //22.1
    var language = valueMap['@language'];
    if (language != null) {
      if (language is! String) {
        throw JsonLdError('invalid language mapping');
      }
    }
    //22.2
    definition.languageMapping = language ?? '';
  }
  //23)
  if (valueMap.containsKey('@direction') && !valueMap.containsKey('@type')) {
    var direction = valueMap['@direction'];

    if (direction == null || direction != 'ltr' || direction != 'rtl') {
      definition.directionMapping = direction ?? '';
    } else if (direction is String) {
      if (direction == 'ltr' || direction == 'rtl') {
        definition.directionMapping = direction;
      } else {
        throw JsonLdError('invalid base direction');
      }
    } else {
      throw JsonLdError('invalid base direction');
    }
  }
  //24
  if (valueMap.containsKey('@nest')) {
    //24.1
    if (activeContext.options.processingMode == 'json-ld-1.0') {
      throw JsonLdError('invalid term definition');
    }
    //24.2
    var nest = valueMap['@nest'];
    if (nest is String) {
      if (keywords.contains(nest) && nest != '@nest') {
        throw JsonLdError('invalid @nest value');
      }
      definition.nestValue = nest;
    } else {
      throw JsonLdError('invalid @nest value');
    }
  }
  //25)
  if (valueMap.containsKey('@prefix')) {
    //25.1
    if (activeContext.options.processingMode == 'json-ld-1.0' ||
        term.contains(':') ||
        term.contains('/')) {
      throw JsonLdError('invalid term definition');
    }
    //25.2
    var prefix = valueMap['@prefix'];
    if (prefix is! bool) throw JsonLdError('invalid @prefix value');
    definition.prefixFlag = prefix;
    //25.3
    if (definition.prefixFlag && keywords.contains(definition.iriMapping)) {
      throw JsonLdError('invalid term definition');
    }
  }
  //26
  var allowed = [
    '@id',
    '@reverse',
    '@container',
    '@context',
    '@type',
    '@direction',
    '@index',
    '@language',
    '@nest',
    '@prefix',
    '@protected'
  ];
  var keys = valueMap.keys;
  if (!keys.every((element) => allowed.contains(element))) {
    throw JsonLdError('invalid term definition');
  }
  //27
  if (!overwriteProtected &&
      previousDefinition != null &&
      previousDefinition.protected) {
    //27.1
    if (definition != previousDefinition) {
      throw JsonLdError('protected term redefinition');
    }
    //27.2
    definition = previousDefinition;
  }

  //28)
  activeContext.terms[term] = definition;
  defined[term] = true;
  return;
}
