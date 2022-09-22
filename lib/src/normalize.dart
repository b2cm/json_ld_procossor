//Urdna2015 Algorithm

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:json_ld_processor/json_ld_processor.dart';
import 'package:json_ld_processor/src/flatten.dart';

String normalizeImpl(RdfDataset inputDataset) {
  //1
  var canonState = CanonicalizationState();
  //2
  for (var graphName in inputDataset.graphs.keys) {
    RdfGraph graph = inputDataset.graphs[graphName]!;
    if (graphName.startsWith('_:')) {
      List<NQuad> qudasPerGraph = [];
      for (var t in graph.triple) {
        qudasPerGraph.add(NQuad(t, graphName));
      }
      if (canonState.blankNodeToQuads.containsKey(graphName)) {
        canonState.blankNodeToQuads[graphName]!.addAll(qudasPerGraph);
      } else {
        canonState.blankNodeToQuads[graphName] = qudasPerGraph;
      }
    }
    for (var triple in graph.triple) {
      if (triple.subject.startsWith('_:')) {
        if (canonState.blankNodeToQuads.containsKey(triple.subject)) {
          canonState.blankNodeToQuads[triple.subject]!
              .add(NQuad(triple, graphName));
        } else {
          canonState.blankNodeToQuads[triple.subject] = [
            NQuad(triple, graphName)
          ];
        }
      }
      if (triple.object is String && triple.object.startsWith('_:')) {
        if (canonState.blankNodeToQuads.containsKey(triple.object)) {
          canonState.blankNodeToQuads[triple.object]!
              .add(NQuad(triple, graphName));
        } else {
          canonState.blankNodeToQuads[triple.object] = [
            NQuad(triple, graphName)
          ];
        }
      }
    }
  }
  //3
  List<String> nonNormalizedIdentifier =
      canonState.blankNodeToQuads.keys.toList();
  //4
  var simple = true;
  //5
  while (simple) {
    //5.1
    simple = false;
    //5.2
    canonState.hashToBlankNodes = {};
    //5.3
    for (var id in nonNormalizedIdentifier) {
      //5.3.1
      var hash = hashFirstDegreeQuads(canonState, id);
      //5.3.2
      if (canonState.hashToBlankNodes.containsKey(hash)) {
        canonState.hashToBlankNodes[hash]!.add(id);
      } else {
        canonState.hashToBlankNodes[hash] = [id];
      }
    }
    //5.4
    List hashes = canonState.hashToBlankNodes.keys.toList();
    hashes.sort();
    for (var hash in hashes) {
      List identifierList = canonState.hashToBlankNodes[hash]!;
      //5.4.1
      if (identifierList.length > 1) continue;
      //5.4.2
      canonState.hashToBlankNodes[hash] = [
        canonState.canonicalIssuer.createIdentifierFrom(identifierList.first)
      ];
      //5.4.3
      nonNormalizedIdentifier.remove(identifierList.first);
      //5.4.4
      canonState.hashToBlankNodes.remove(hash);
      //5.4.5
      simple = true;
    }
  }
  //6
  List hashes = canonState.hashToBlankNodes.keys.toList();
  hashes.sort();
  for (var hash in hashes) {
    //6.1
    List<HashNDegreeQuadsResult> hashPathList = [];
    //6.2
    List identifierList = canonState.hashToBlankNodes[hash]!;
    for (var id in identifierList) {
      //6.2.1
      if (canonState.canonicalIssuer.hasIdentifier(id)) continue;
      //6.2.2
      var tmpIssuer = BlankNodeIdGenerator('_:b');
      //6.2.3
      tmpIssuer.createIdentifierFrom(id);
      //6.2.4
      hashPathList.add(hashNDegreeQuads(canonState, id, tmpIssuer));
    }
    //6.3
    hashPathList.sort();
    for (var result in hashPathList) {
      //6.3.1
      for (var existingIdentifier in result.issuer.issuedIds()) {
        canonState.canonicalIssuer.createIdentifierFrom(existingIdentifier);
      }
    }
  }
  //7
  List<NQuad> normalized = [];
  for (var graphName in inputDataset.graphs.keys.toList()) {
    String normalizedGraphName = graphName.startsWith('_:')
        ? canonState.canonicalIssuer.createIdentifierFrom(graphName)
        : graphName;
    List<RdfTriple> triples = inputDataset.graphs[graphName]!.triple;
    for (var triple in triples) {
      var tmp = NQuad(
          RdfTriple(
              triple.subject.startsWith('_:')
                  ? canonState.canonicalIssuer
                      .createIdentifierFrom(triple.subject)
                  : triple.subject,
              triple.predicate,
              triple.object is String && triple.object.startsWith('_:')
                  ? canonState.canonicalIssuer
                      .createIdentifierFrom(triple.object)
                  : triple.object),
          normalizedGraphName);
      if (!normalized.contains(tmp)) {
        normalized.add(tmp);
      }
    }
  }
  normalized.sort();
  String normal = '';
  for (var value in normalized) {
    normal += value.toString();
  }
  //8
  return normal;
}

String hashFirstDegreeQuads(
    CanonicalizationState canonState, String referenceBlankNode) {
  //1
  List<String> nquads = [];
  //2
  List<NQuad> quads = canonState.blankNodeToQuads[referenceBlankNode] ?? [];
  //3
  for (var quad in quads) {
    nquads.add(quad.serializeSpecial(referenceBlankNode));
  }
  //4
  nquads.sort();
  String nquadString = '';
  for (var q in nquads) {
    nquadString += q;
  }
  //5
  return sha256.convert(utf8.encode(nquadString)).toString();
}

HashNDegreeQuadsResult hashNDegreeQuads(CanonicalizationState canonState,
    String identifier, BlankNodeIdGenerator tmpIssuer) {
  //1
  Map<String, List<String>> hashToRelatedBlankNodes = {};
  //2
  List<NQuad> quads = canonState.blankNodeToQuads[identifier] ?? [];
  //3
  for (var quad in quads) {
    //subject
    if (quad.triple.subject.startsWith('_:') &&
        quad.triple.subject != identifier) {
      var hash = hashRelatedBlankNode(canonState, quad.triple.subject, quad,
          tmpIssuer, GraphPosition.subject);
      if (hashToRelatedBlankNodes.containsKey(hash)) {
        hashToRelatedBlankNodes[hash]!.add(quad.triple.subject);
      } else {
        hashToRelatedBlankNodes[hash] = [quad.triple.subject];
      }
    }
    //object
    if (quad.triple.object is String &&
        quad.triple.object.startsWith('_:') &&
        quad.triple.object != identifier) {
      var hash = hashRelatedBlankNode(canonState, quad.triple.object, quad,
          tmpIssuer, GraphPosition.object);
      if (hashToRelatedBlankNodes.containsKey(hash)) {
        hashToRelatedBlankNodes[hash]!.add(quad.triple.object);
      } else {
        hashToRelatedBlankNodes[hash] = [quad.triple.object];
      }
    }
    //graphName
    if (quad.graphName.startsWith('_:') && quad.graphName != identifier) {
      var hash = hashRelatedBlankNode(
          canonState, quad.graphName, quad, tmpIssuer, GraphPosition.graphName);
      if (hashToRelatedBlankNodes.containsKey(hash)) {
        hashToRelatedBlankNodes[hash]!.add(quad.graphName);
      } else {
        hashToRelatedBlankNodes[hash] = [quad.graphName];
      }
    }
  }
  //4
  String dataToHash = '';
  //5
  var relatedHashes = hashToRelatedBlankNodes.keys.toList();
  relatedHashes.sort();

  for (var relatedHash in relatedHashes) {
    //5.1
    dataToHash += relatedHash;
    //5.2
    String chosenPath = '';
    //5.3
    BlankNodeIdGenerator chosenIssuer = BlankNodeIdGenerator.from(tmpIssuer);
    //5.4
    List<String> blankNodeList = hashToRelatedBlankNodes[relatedHash]!;
    //5.5
    var permutations = permutation(blankNodeList);
    for (var permutation in permutations) {
      //5.4.1
      BlankNodeIdGenerator issuerCopy = BlankNodeIdGenerator.from(tmpIssuer);
      //5.4.2
      String path = '';
      //5.4.3
      List<String> recursionList = [];
      //5.4.4
      for (var related in permutation) {
        //5.4.4.1
        if (canonState.canonicalIssuer.hasIdentifier(related)) {
          path += canonState.canonicalIssuer.createIdentifierFrom(related);
        }
        //5.4.4.2
        else {
          //5.4.4.2.1
          if (!issuerCopy.hasIdentifier(related)) {
            recursionList.add(related);
          }
          //5.4.4.2.2
          path += issuerCopy.createIdentifierFrom(related);
        }
        //5.4.4.3
        if (chosenPath.isNotEmpty &&
            path.length >= chosenPath.length &&
            chosenPath.compareTo(path) < 0) {
          continue;
        }
      }
      //5.4.5
      for (var related in recursionList) {
        //5.4.5.1
        var result = hashNDegreeQuads(canonState, related, issuerCopy);
        //5.4.5.2
        path += issuerCopy.createIdentifierFrom(related);
        //5.4.5.3
        path += '<${result.hash}>';
        //5.4.5.4
        issuerCopy = result.issuer;
        //5.4.5.5
        if (chosenPath.isNotEmpty &&
            path.length >= chosenPath.length &&
            chosenPath.compareTo(path) < 0) {
          continue;
        }
      }
      //5.4.6
      if (chosenPath.isEmpty || chosenPath.compareTo(path) > 0) {
        chosenPath = '' + path;
        chosenIssuer = issuerCopy;
      }
    }
    //5.5
    dataToHash += chosenPath;
    //5.6
    tmpIssuer = chosenIssuer;
  }
  return HashNDegreeQuadsResult(
      sha256.convert(utf8.encode(dataToHash)).toString(), tmpIssuer);
}

String hashRelatedBlankNode(
    CanonicalizationState canonState,
    String relatedBlankNode,
    NQuad quad,
    BlankNodeIdGenerator issuer,
    GraphPosition position) {
  //1
  String identifier;
  if (canonState.canonicalIssuer.hasIdentifier(relatedBlankNode)) {
    identifier =
        canonState.canonicalIssuer.createIdentifierFrom(relatedBlankNode);
  } else if (issuer.hasIdentifier(relatedBlankNode)) {
    identifier = issuer.createIdentifierFrom(relatedBlankNode);
  } else {
    identifier = hashFirstDegreeQuads(canonState, relatedBlankNode);
  }

  //2
  String input = position.value;
  //3
  if (position != GraphPosition.graphName) {
    input += '<${quad.triple.predicate}>';
  }
  //4
  input += identifier;
  return sha256.convert(utf8.encode(input)).toString();
}

enum GraphPosition { subject, object, graphName }

extension GraphPositionExt on GraphPosition {
  static const Map<GraphPosition, String> values = {
    GraphPosition.subject: 's',
    GraphPosition.object: 'o',
    GraphPosition.graphName: 'g'
  };

  String get value => values[this]!;
}

class CanonicalizationState {
  Map<String, List<NQuad>> blankNodeToQuads;
  Map<String, List<String>> hashToBlankNodes;
  BlankNodeIdGenerator canonicalIssuer;

  CanonicalizationState()
      : blankNodeToQuads = {},
        hashToBlankNodes = {},
        canonicalIssuer = BlankNodeIdGenerator('_:c14n');
}

class NQuad implements Comparable {
  RdfTriple triple;
  String graphName;

  NQuad(this.triple, this.graphName);

  String serializeSpecial(String referenceId) {
    RdfTriple tmpTriple = RdfTriple(
        triple.subject.startsWith('_:')
            ? ((triple.subject == referenceId) ? '_:a' : '_:z')
            : triple.subject,
        triple.predicate,
        triple.object is String && triple.object.startsWith('_:')
            ? ((triple.object == referenceId) ? '_:a' : '_:z')
            : triple.object);

    return '$tmpTriple ${graphName == 'null' ? '' : (graphName.startsWith('_:') ? (graphName == referenceId ? '_:a ' : '_:z ') : '<$graphName> ')}.\n';
  }

  @override
  String toString() {
    return '$triple ${graphName == 'null' ? '' : (graphName.startsWith('_:') ? '$graphName ' : '<$graphName> ')}.\n';
  }

  @override
  operator ==(other) {
    return other.toString() == toString();
  }

  @override
  int get hashCode =>
      int.parse(md5.convert(utf8.encode(toString())).toString().substring(20),
          radix: 16);

  @override
  int compareTo(other) {
    return toString().compareTo(other.toString());
  }
}

class HashNDegreeQuadsResult implements Comparable {
  String hash;
  BlankNodeIdGenerator issuer;

  HashNDegreeQuadsResult(this.hash, this.issuer);

  @override
  int compareTo(other) {
    return hash.compareTo(other.hash);
  }
}

List<List<String>> permutation(List<String> str) {
  List<List<String>> result = [];
  permutation2([], str, result);
  return result;
}

void permutation2(
    List<String> prefix, List<String> str, List<List<String>> result) {
  int n = str.length;
  if (n == 0) {
    result.add(prefix);
  } else {
    for (int i = 0; i < n; i++) {
      permutation2(
          prefix + [str[i]], str.sublist(0, i) + str.sublist(i + 1, n), result);
    }
  }
}
