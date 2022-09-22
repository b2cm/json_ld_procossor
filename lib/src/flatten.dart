import 'package:json_ld_processor/json_ld_processor.dart';
import 'package:json_ld_processor/src/utils.dart';

List<dynamic> flattenDoc({required dynamic element, bool ordered = false}) {
  //1
  var nodeMap = NodeMap();
  //2
  generateNodeMap(element: element, nodeMap: nodeMap);
  //3
  var defaultGraph = nodeMap.getGraph('@default');
  if (defaultGraph == null) {
    throw JsonLdError('Illegal State');
  }
  //4
  var graphs = nodeMap.graphs();
  if (ordered) graphs.sort();
  for (var graphName in graphs) {
    if (graphName == '@default') continue;
    var graph = nodeMap.getGraph(graphName);
    //4.1
    if (!defaultGraph.containsKey(graphName)) {
      defaultGraph[graphName] = {'@id': graphName};
    }
    //4.2
    Map<String, dynamic> entry = defaultGraph[graphName];
    //4.3
    List graphArray = [];
    //4.4
    var graphKeys = graph!.keys.toList();
    if (ordered) graphKeys.sort();
    for (var id in graphKeys) {
      var node = graph[id];
      if (node == null ||
          node is! Map ||
          node.length == 1 && node.containsKey('@id')) {
        continue;
      }
      graphArray.add(node);
    }
    Map<String, dynamic> entry2 = {};
    entry2.addAll(entry);
    entry2['@graph'] = graphArray;
    defaultGraph[graphName] = entry2;
  }

  //5
  List flattened = [];
  //6
  var defaultGraphKeys = defaultGraph.keys.toList();
  if (ordered) defaultGraphKeys.sort();
  for (var id in defaultGraphKeys) {
    var node = defaultGraph[id];
    if (node == null ||
        node is! Map ||
        (node.length == 1 && node.containsKey('@id'))) {
      continue;
    }
    flattened.add(node);
  }
  //7
  return flattened;
}

generateNodeMap(
    {required dynamic element,
    required NodeMap nodeMap,
    String activeGraph = '@default',
    String? activeSubject,
    String? activeProperty,
    Map<String, dynamic>? list,
    Map<String, dynamic>? referencedNode}) {
  //1
  if (element is List) {
    for (var item in element) {
      //1.1
      generateNodeMap(
          element: item,
          nodeMap: nodeMap,
          activeGraph: activeGraph,
          activeProperty: activeProperty,
          activeSubject: activeSubject,
          list: list,
          referencedNode: referencedNode);
    }
  }
  //2
  else if (element is Map) {
    //3
    if (element.containsKey('@type')) {
      dynamic newType;
      var oldType = element['@type'];

      if (oldType is String) {
        if (oldType.startsWith('_:')) {
          newType = nodeMap.createIdentifier(oldType);
        } else {
          newType = oldType;
        }
      } else if (oldType is List) {
        newType = [];
        for (String type in oldType) {
          if (type.startsWith('_:')) {
            newType.add(nodeMap.createIdentifier(type));
          } else {
            newType.add(type);
          }
        }
      }
      element['@type'] = newType;
    }

    //4
    if (element.containsKey('@value')) {
      //4.1
      if (list == null) {
        //4.1.1
        if (nodeMap.contains(activeGraph, activeSubject!, activeProperty)) {
          List activePropertyValue =
              nodeMap.getValue(activeGraph, activeSubject, activeProperty);
          bool isIn = false;
          for (var item in activePropertyValue) {
            isIn = compareJsonLd(item, element);
            if (isIn) break;
          }
          if (!isIn) {
            nodeMap.set(activeGraph, activeSubject, activeProperty!,
                activePropertyValue + [element]);
          }
        }
        //4.1.2
        else {
          nodeMap.set(activeGraph, activeSubject, activeProperty!, [element]);
        }
      }
      //4.2
      else {
        List? oldList = list['@list'];
        if (oldList != null) {
          oldList.add(element);
        } else {
          list['@list'] = [element];
        }
      }
    }
    //5
    else if (element.containsKey('@list')) {
      //5.1
      Map<String, dynamic> result = {};
      result['@list'] = [];

      //5.2
      generateNodeMap(
          element: element['@list'],
          nodeMap: nodeMap,
          activeSubject: activeSubject,
          activeProperty: activeProperty,
          activeGraph: activeGraph,
          list: result,
          referencedNode: referencedNode);

      //5.3
      if (list == null) {
        if (nodeMap.contains(activeGraph, activeSubject!, activeProperty)) {
          var value = [];
          var fromNodeMap =
              nodeMap.getValue(activeGraph, activeSubject, activeProperty);
          if (fromNodeMap is List) {
            value += fromNodeMap;
          } else {
            value.add(fromNodeMap);
          }
          value.add(result);
          nodeMap.set(activeGraph, activeSubject, activeProperty!, value);
        } else {
          nodeMap.set(activeGraph, activeSubject, activeProperty!, [result]);
        }
      }
      //5.4
      else {
        List? oldList = list['@list'];
        if (oldList != null) {
          oldList.add(result);
        } else {
          list['@list'] = [result];
        }
      }
    }
    //6
    else if (isNodeObject(element)) {
      dynamic id;
      //6.1
      if (element.containsKey('@id')) {
        id = element['@id'];
        if (id == null || id is! String) {
          return;
        }
        if (id.startsWith('_:')) {
          id = nodeMap.createIdentifier(id);
        }
        element.remove('@id');
      }
      //6.2
      else {
        id = nodeMap.createIdentifier();
      }
      //6.3
      if (id != null && !nodeMap.contains(activeGraph, id)) {
        nodeMap.set(activeGraph, id, '@id', id);
      }
      //6.4

      //6.5
      if (referencedNode != null) {
        //6.5.1
        if (nodeMap.contains(activeGraph, id, activeProperty)) {
          var activePropertyValue =
              nodeMap.getValue(activeGraph, id, activeProperty);
          if (activePropertyValue is! List) {
            activePropertyValue = [activePropertyValue];
          }
          bool isIn = false;
          for (var item in activePropertyValue) {
            isIn = compareJsonLd(item, element);
            if (isIn) break;
          }
          if (!isIn) {
            nodeMap.set(activeGraph, id, activeProperty!,
                activePropertyValue + [referencedNode]);
          }
        }
        //6.5.2
        nodeMap.set(activeGraph, id, activeProperty!, [referencedNode]);
      }
      //6.6
      else if (activeProperty != null) {
        //6.6.1
        var reference = {'@id': id};
        //6.6.2
        if (list == null) {
          //6.6.2.2
          if (nodeMap.contains(activeGraph, activeSubject!, activeProperty)) {
            var activePropertyValue =
                nodeMap.getValue(activeGraph, activeSubject, activeProperty);
            if (activePropertyValue is! List) {
              activePropertyValue = [activePropertyValue];
            }
            bool isIn = false;
            for (var item in activePropertyValue) {
              isIn = compareJsonLd(item, element);
              if (isIn) break;
            }
            if (!isIn) {
              nodeMap.set(activeGraph, activeSubject, activeProperty,
                  activePropertyValue + [reference]);
            }
          }
          //6.6.2.1
          else {
            nodeMap
                .set(activeGraph, activeSubject, activeProperty, [reference]);
          }
        }
        //6.6.3
        else {
          List? oldList = list['@list'];
          if (oldList != null) {
            oldList.add(reference);
          } else {
            list['@list'] = [reference];
          }
        }
      }
      //6.7
      if (element.containsKey('@type')) {
        Set<String> nodeType = {};
        var nodeTypeValue = nodeMap.getValue(activeGraph, id, '@type');
        if (nodeTypeValue is List) {
          for (var item in nodeTypeValue) {
            if (item != null) {
              nodeType.add(item);
            }
          }
        } else if (nodeTypeValue != null) {
          nodeType.add(nodeTypeValue);
        }

        var typeValue = element['@type'];
        if (typeValue is List) {
          for (var item in typeValue) {
            if (item != null) {
              nodeType.add(item);
            }
          }
        } else if (typeValue != null) {
          nodeType.add(typeValue);
        }

        nodeMap.set(activeGraph, id, '@type', nodeType.toList());
        element.remove('@type');
      }
      //6.8
      if (element.containsKey('@index')) {
        if (nodeMap.contains(activeGraph, id, '@index')) {
          throw JsonLdError('conflicting indexes');
        }
        nodeMap.set(activeGraph, id, '@index', element['@index']);
        element.remove('@index');
      }
      //6.9
      if (element.containsKey('@reverse')) {
        //6.9.1
        Map<String, dynamic> referenced = {'@id': id};
        //6.9.2
        Map reverseMap = element['@reverse'];
        //6.9.3
        for (var reverseKey in reverseMap.keys.toList()) {
          var entryValue = reverseMap[reverseKey];
          if (entryValue is! List) {
            entryValue[entryValue];
          }
          //6.9.3.1
          for (var value in entryValue) {
            //6.9.3.1.1
            generateNodeMap(
                element: value,
                nodeMap: nodeMap,
                activeGraph: activeGraph,
                referencedNode: referenced,
                activeProperty: reverseKey);
          }
        }
        //6.9.4
        element.remove('@reverse');
      }
      //6.10
      if (element.containsKey('@graph')) {
        generateNodeMap(
            element: element['@graph'], nodeMap: nodeMap, activeGraph: id);
        element.remove('@graph');
      }
      //6.11
      if (element.containsKey('@included')) {
        generateNodeMap(
            element: element['@included'],
            nodeMap: nodeMap,
            activeGraph: activeGraph);
        element.remove('@included');
      }
      //6.12
      for (String property in element.keys.toList()) {
        var value = element[property];

        if (value == null || value is! List && value is! Map) {
          continue;
        }
        //6.12.1
        if (property.startsWith('_:')) {
          property = nodeMap.createIdentifier(property);
        }
        //6.12.2
        if (!nodeMap.contains(activeGraph, id, property)) {
          nodeMap.set(activeGraph, id, property, []);
        }
        //6.12.3
        generateNodeMap(
            element: value,
            nodeMap: nodeMap,
            activeGraph: activeGraph,
            activeSubject: id,
            activeProperty: property);
      }
    }
  }
}

class BlankNodeIdGenerator {
  final Map<String, String> _map;
  int _counter;
  final String _prefix;

  BlankNodeIdGenerator(this._prefix)
      : _counter = 0,
        _map = {};

  BlankNodeIdGenerator.from(BlankNodeIdGenerator old)
      : _counter = 0 + old._counter,
        _map = Map.from(old._map),
        _prefix = old._prefix;

  String createIdentifier() {
    return '$_prefix${_counter++}';
  }

  String createIdentifierFrom(String? identifier) {
    if (identifier == null || identifier.trim() == '') {
      return createIdentifier();
    }

    if (_map.containsKey(identifier)) {
      return _map[identifier]!;
    }

    String blankId = createIdentifier();
    _map[identifier] = blankId;
    return blankId;
  }

  bool hasIdentifier(String identifier) {
    return _map.containsKey(identifier);
  }

  List<String> issuedIds() {
    return _map.keys.toList();
  }
}

class NodeMap {
  final Map<String, Map<String, Map<String, dynamic>>> _base;
  final BlankNodeIdGenerator _idGenerator;

  NodeMap()
      : _base = {},
        _idGenerator = BlankNodeIdGenerator('_:b') {
    _base['@default'] = {};
  }

  void set(String graphName, String subject, String property, dynamic value) {
    _base
        .putIfAbsent(graphName, () => {})
        .putIfAbsent(subject, () => {})[property] = value;
  }

  Map? getGraph(String graphName) {
    return _base[graphName];
  }

  dynamic getValue(String graphName, String subject, [String? property]) {
    if (property == null) {
      return _base[graphName]?[subject];
    } else {
      return _base[graphName]?[subject]?[property];
    }
  }

  bool contains(String graphName, String subject, [String? property]) {
    if (property == null) {
      return _base.containsKey(graphName) &&
          _base[graphName]!.containsKey(subject);
    } else {
      return _base.containsKey(graphName) &&
          _base[graphName]!.containsKey(subject) &&
          _base[graphName]![subject]!.containsKey(property);
    }
  }

  List<String> graphs() {
    return _base.keys.toList();
  }

  String createIdentifier([String? name]) {
    if (name == null) {
      return _idGenerator.createIdentifier();
    } else {
      return _idGenerator.createIdentifierFrom(name);
    }
  }
}
