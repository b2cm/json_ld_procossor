import 'package:json_ld_processor/json_ld_processor.dart';

void main() async {
  var exampleData = {
    "@context": [
      "https://www.w3.org/2018/credentials/v1",
      {
        'familyName': {'@id': 'http://family.org'},
        'givenName': {'@id': 'http://family.org'}
      }
    ],
    "id": "credential:000-4892",
    "issuer": 'did:example:1364723',
    "issuanceDate":
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z',
    "credentialSubject": {
      "id": 'did:example:8344648190',
      "givenName": "Max",
      "familyName": "Mustermann"
    },
    "type": ["VerifiableCredential"]
  };

// expand
  var expanded = await JsonLdProcessor.expand(exampleData);
  print('expanded:\n$expanded \n\n');
// flatten
  var flattend = await JsonLdProcessor.flatten(exampleData);
  print('flattened:\n$flattend \n\n');
//toRdf
  var rdf = await JsonLdProcessor.toRdf(exampleData);
  print('as rdf:\n$rdf \n\n');
// normalize
  var normalized = await JsonLdProcessor.normalize(exampleData,
      options: JsonLdOptions(safeMode: true));
  print('normalized:\n$normalized \n\n');

  // normalize rdf-Dataset
  var nquadString =
      '''<credential:000-4892> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://www.w3.org/2018/credentials#VerifiableCredential> .
<credential:000-4892> <https://www.w3.org/2018/credentials#credentialSubject> <did:example:8344648190> .
<credential:000-4892> <https://www.w3.org/2018/credentials#issuanceDate> "2022-09-22T17:40:19Z"^^<http://www.w3.org/2001/XMLSchema#dateTime> .
<credential:000-4892> <https://www.w3.org/2018/credentials#issuer> <did:example:1364723> .
<did:example:8344648190> <http://family.org> "Max" .
<did:example:8344648190> <http://family.org> "Mustermann" . 
''';

  var asDataset = RdfDataset.fromNQuad(nquadString);
  var normalized2 = await JsonLdProcessor.normalize(asDataset);
  print('normalized2:\n$normalized2 \n\n');
}
