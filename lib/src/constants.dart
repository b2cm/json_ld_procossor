const List<String> keywords = [
  '@base',
  '@container',
  '@context',
  '@direction',
  '@graph',
  '@id',
  '@import',
  '@included',
  '@index',
  '@json',
  '@language',
  '@list',
  '@nest',
  '@none',
  '@prefix',
  '@propagate',
  '@protected',
  '@reverse',
  '@set',
  '@type',
  '@value',
  '@version',
  '@vocab'
];

const List<String> genDelims = [':', '/', '?', '#', '[', ']', '@'];

const List<String> framingKeywords = [
  '@default',
  '@embed',
  '@explicit',
  '@omitDefault',
  '@requireAll'
];

final keyWordMatcher = RegExp(r'@[A-Za-z]+$');

enum RdfType { double, type, integer, nil, boolean, rest, first, json }

extension RdfTypeExt on RdfType {
  static const Map<RdfType, String> values = {
    RdfType.type: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type',
    RdfType.double: 'http://www.w3.org/2001/XMLSchema#double',
    RdfType.integer: 'http://www.w3.org/2001/XMLSchema#integer',
    RdfType.nil: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#nil',
    RdfType.boolean: 'http://www.w3.org/2001/XMLSchema#boolean',
    RdfType.rest: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest',
    RdfType.first: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#first',
    RdfType.json: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON'
  };
  String get value => values[this]!;
}

RegExp alpha = RegExp(r'^[a-zA-Z]+$');
RegExp alphanumeric = RegExp(r'^[a-zA-Z0-9]+$');
