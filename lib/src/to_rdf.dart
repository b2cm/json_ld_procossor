import 'dart:convert';

import 'package:json_ld_processor/src/constants.dart';
import 'package:json_ld_processor/src/flatten.dart';
import 'package:json_ld_processor/src/json_ld_processor_base.dart';
import 'package:json_ld_processor/src/utils.dart';

Future<void> deserializeJsonLdToRdf(NodeMap nodeMap, RdfDataset dataset,
    {bool produceGeneralizedRdf = true, String? rdfDirection}) async {
  //1
  var graphNames = nodeMap.graphs();
  graphNames.sort();
  for (var graphName in graphNames) {
    var graph = nodeMap.getGraph(graphName);
    //1.1
    if (!isAbsoluteUri(graphName)) {
      if (!graphName.startsWith('_:') && graphName != '@default') {
        continue;
      }
    }
    //1.2
    RdfGraph triples;
    if (graphName == '@default') {
      triples = dataset.defaultGraph;
    } else {
      triples = RdfGraph();
      dataset.add(graphName, triples);
    }
    //1.3
    var subjects = graph!.keys.toList();
    subjects.sort();
    for (var subject in subjects) {
      var node = graph[subject] as Map;
      //1.3.1
      if (!isAbsoluteUri(subject)) {
        if (!subject.startsWith('_:')) continue;
      }
      //1.3.2
      var properties = node.keys.toList();
      properties.sort();
      for (var property in properties) {
        var value = node[property];
        //1.3.2.1
        if (property == '@type') {
          if (value is List) {
            for (var type in value) {
              if (isAbsoluteUri(type)) {
                triples.add(RdfTriple(subject, RdfType.type.value, type));
              }
            }
          }
        }
        //1.3.2.2
        else if (keywords.contains(property)) {
          continue;
        }
        //1.3.2.3
        else if (produceGeneralizedRdf &&
            property is String &&
            property.startsWith('_:')) {
          continue;
        }
        //1.3.2.4
        if (!isAbsoluteUri(property)) {
          continue;
        } else {
          if (value is List) {
            for (var item in value) {
              //1.3.2.5.1
              List<RdfTriple> listTriples = [];
              //1.3.2.5.2
              dynamic literal;
              if (item is Map<String, dynamic>) {
                literal = objectToRdf(item, listTriples, nodeMap, rdfDirection);
              }
              if (literal != null) {
                triples.add(RdfTriple(subject, property, literal));
              }
              //1.3.2.5.3
              for (var t in listTriples) {
                triples.add(t);
              }
            }
          }
        }
      }
    }
  }
}

dynamic objectToRdf(Map<String, dynamic> item, List<RdfTriple> listTriples,
    NodeMap nodeMap, String? rdfDirection) {
  //1
  if (isNodeObject(item)) {
    if (isAbsoluteUri(item['@id'])) {
      //2
      return item['@id'];
    } else if (item['@id'].startsWith('_:')) {
      return item['@id'];
    } else {
      return null;
    }
  }
  //3
  if (isListObject(item)) {
    return listToRdf(item['@list'], listTriples, nodeMap, rdfDirection);
  }
  //4
  var value = item['@value'];
  //5
  var datatype = item['@type'];
  //6
  if (datatype != null && !isAbsoluteUri(datatype) && datatype != '@json') {
    return null;
  }
  //7
  if (item.containsKey('@language')) {
    if (!isValidLanguage(item['@language'])) return null;
  }
  //8
  if (datatype == '@json') {
    value = jsonEncode(jsonEncode(value));
    value = value.substring(1, value.length - 1);
    datatype = RdfType.json.value;
  }
  //9
  if (value is bool) {
    datatype ??= RdfType.boolean.value;
    value = value.toString();
  }
  //10
  else if (value is num) {
    if ((datatype != null && datatype == RdfType.double.value) ||
        (value is double && (value % 1 != 0.0 || value >= 10 ^ 21))) {
      datatype ??= RdfType.double.value;
      value = formatNumber(value
          .toStringAsExponential(15)
          .replaceAll('e', 'E')
          .replaceAll('+', ''));
    }
    //11
    else if (value is int || (value is double && value % 1 == 0.0)) {
      datatype ??= RdfType.integer.value;
      value = value.toStringAsFixed(0);
      if (value == '-0' || value == '+0') value = '0';
    }
  }

  //12
  else {
    if (item.containsKey('@language')) {
      datatype ??= 'xsd:langString';
    } else {
      datatype ??= 'xsd:string';
    }
  }
  //13
  RdfLiteral literal;
  if (item.containsKey('@direction') && rdfDirection != null) {
    //TODO: di things with direction
    literal = RdfLiteral(value);
  }
  //14
  else {
    literal =
        RdfLiteral(value, datatype: datatype, language: item['@language']);
  }
  return literal;
}

dynamic listToRdf(
    List list, List<RdfTriple> triples, NodeMap nodeMap, String? rdfDirection) {
  //1
  if (list.isEmpty) {
    return RdfType.nil.value;
  } else {
    //2
    List<String> bnodes = [];
    for (int i = 0; i < list.length; i++) {
      bnodes.add(nodeMap.createIdentifier());
    }
    //3
    int index = 0;
    for (var item in list) {
      String subject = bnodes[index];
      index++;
      //3.1
      List<RdfTriple> embeddedTriples = [];
      //3.2
      var object = objectToRdf(item, embeddedTriples, nodeMap, rdfDirection);
      //3.3
      if (object != null) {
        triples.add(RdfTriple(subject, RdfType.first.value, object));
      }
      //3.4
      String rest = index < list.length ? bnodes[index] : RdfType.nil.value;
      triples.add(RdfTriple(subject, RdfType.rest.value, rest));
      //3.5
      triples.addAll(embeddedTriples);
    }
    //4
    return bnodes.isEmpty ? RdfType.nil.value : bnodes.first;
  }
}

bool isValidLanguage(String? lang) {
  if (lang == null) return false;
  if (lang.contains('-')) {
    var split = lang.split('-');
    if (split.length != 2) {
      return false;
    } else {
      if (!alpha.hasMatch(split[0])) return false;
      if (!alphanumeric.hasMatch(split[1])) return false;
      return split[0].length <= 8 && split[1].length <= 8;
    }
  } else {
    if (!alpha.hasMatch(lang)) return false;
    return lang.length <= 8;
  }
}

String formatNumber(String number) {
  int cutPosition = number.indexOf('.') + 1;
  for (int i = cutPosition; i < 16; i++) {
    if (number[i] != '0') cutPosition = i;
  }

  return number.replaceRange(cutPosition + 1, 17, '');
}
