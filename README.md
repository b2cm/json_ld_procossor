# Json LD Processing Library
This package implements the [JSON-LD Processing algorithms 1.1](https://www.w3.org/TR/json-ld11-api/) and the [URDNA2015 Canonicalization](https://w3c-ccg.github.io/rdf-dataset-canonicalization/spec/) algorithm in pure Dart.

**Important Note**: This package is work-in-progress. Not all algorithms are implemented for now and not everything works perfect (See Implementation Status).
But in general it works.

## Usage
```Dart
Map<String, dynamic> input = {}; //a valid Json-ld document
//expansion
var exapnded = await JsonLdProcessor.expand(input);
//flattening
var flattened = await JsonLdProcessor.flatten(input);
//toRdf
var rdf = await JsonLdProcessor.toRdf(input);
//normalize (URDNA2015) with additional options
var exapnded = await JsonLdProcessor.normalize(input, options: JsonLdOptions(safeMode: true));
```

## SafeMode Option
As the implementor of the normalization algorithms URDNA2015 and URGNA2012 in java [showed in his repo](https://github.com/setl/rdf-urdna/tree/master/jsonld-warnings), using json-ld and normalization for signing there are some security flaws. In some cases the documents could be manipulated and the signatures stays correct.
One reasons for this can be found in the expansion algorithm. If a property of the input document can't be expanded to an IRI or keyword, it is dropped and so not included in the normalized dataset.To be able to throw an exception in this case, there is a safeMode option. It is default set to false.
But if it is true, the exception is thrown. If not, the property is dropped as standardized.
I recommend setting it to true, if you normalize a json-ld document before signing.

**Note:** The idea introducing this option is borrowed from tha [JavaScript implementation](https://github.com/digitalbazaar/jsonld.js/) which powers the [JSON-LD Playground](https://json-ld.org/playground/) as well. This option is not part of the standard yet.

## Implementation Status and Test Coverage
| Algorithm | Tests passed | Tests failed | Notes |
|------|------|----------|-------|
| expand | 363 | 8 | |
| flatten | 55 | 1 | one failed, because of missing compaction algorithm
| compact |0 | 0 | not implemented yet|
| fromRdf | 0 |0 | not implemented yet |
| toRdf | 397 | 39 | <ul><li> respect rdfDirection option is not implemented yet</li> <li> to check if the resulting list of n-quads is correct, I only use string comparison and no test to graph isomorphism. Therefore 12 tests are stated falsely as not passed if you run them on your own</ul></li> |
| normalize | 62 | 1 | |

### Run tests
The test data is taken from [here](https://github.com/w3c/json-ld-api/) for json-ld api test and [here](https://github.com/w3c-ccg/rdf-dataset-canonicalization) for normalization tests.
Therefore you need to clone these two repos next to this, if you would like to run the tests.

## Future Plans
- remove bugs
- implement Compaction and toRdf
- support [framing](https://www.w3.org/TR/json-ld11-framing/)
