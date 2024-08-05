import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:dart_casing/dart_casing.dart';
import 'package:json_annotation/json_annotation.dart';
import 'annotations.dart';

class RegistryCenter {
  final converterRegistry = ConverterRegistry();
  final fieldsRegistry = FieldsRegistry();
  final collectionRegistry = CollectionRegistry();
  final queryRegistry = QueryRegistry();
  final queryMixinRegistry = QueryMixinRegistry();
  final documentRegistry = DocumentRegistry();
  final databaseRegistry = DatabaseRegistry();

  void clear() {
    converterRegistry.clear();
    fieldsRegistry.clear();
    collectionRegistry.clear();
    queryRegistry.clear();
    queryMixinRegistry.clear();
    documentRegistry.clear();
    databaseRegistry.clear();
  }

  String generate() {
    return '''
${converterRegistry.generate()}
${fieldsRegistry.generate()}
${collectionRegistry.generate()}
${queryRegistry.generate()}
${queryMixinRegistry.generate()}
${documentRegistry.generate()}
${databaseRegistry.generate()}
''';
  }
}

class FirestoreGenerator extends GeneratorForAnnotation<FirestoreOdm> {
  static const _collectionChecker = TypeChecker.fromRuntime(Collection);
  static const _jsonKeyChecker = TypeChecker.fromRuntime(JsonKey);

  final Map<String, CollectionNode> _collectionTree = {};
  final Set<InterfaceType> _modelTypes = {};
  final Set<String> _processedTypes = {};
  final RegistryCenter registryCenter = RegistryCenter();

  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    _initializeGeneration();
    _collectData(element, annotation);
    _populateRegistries(element.name!);
    return registryCenter.generate();
  }

  void _initializeGeneration() {
    _collectionTree.clear();
    _modelTypes.clear();
    _processedTypes.clear();
    registryCenter.clear();
  }

  void _collectData(Element element, ConstantReader annotation) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        'Generator cannot target `${element.name}`.',
        todo: 'Remove the FirestoreOdm annotation from `${element.name}`.',
      );
    }
    _collectCollections(annotation);
  }

  void _collectCollections(ConstantReader annotation) {
    final collections = annotation.read('collections').listValue;
    for (final collection in collections) {
      _processCollection(collection, _collectionTree);
    }
  }

  void _processCollection(
      DartObject collection, Map<String, CollectionNode> currentTree) {
    if (!_collectionChecker.isExactlyType(collection.type!)) {
      throw InvalidGenerationSourceError(
        'Invalid collection type: ${collection.type}',
        todo: 'Ensure all collections are of type Collection<T>.',
      );
    }

    final collectionConstantReader = ConstantReader(collection);
    final id = collectionConstantReader.read('id').stringValue;
    final type = collection.type as ParameterizedType;
    final collectionType = type.typeArguments.first as InterfaceType;

    final node = currentTree.putIfAbsent(id, () => CollectionNode());
    node.type = collectionType;
    _modelTypes.add(collectionType);

    final subcollections =
        collectionConstantReader.read('subcollections').listValue;
    for (final subcollection in subcollections) {
      _processCollection(subcollection, node.children);
    }
  }

  void _populateRegistries(String className) {
    for (final type in _modelTypes) {
      registryCenter.converterRegistry.add(ConverterWriter(type));
      final fields = _getFields(type.element);
      registryCenter.fieldsRegistry.add(FieldsWriter(
          type, fields, registryCenter.fieldsRegistry, _processedTypes));
    }

    _populateCollectionRegistries(_collectionTree);

    registryCenter.databaseRegistry
        .add(DatabaseWriter(className, _collectionTree, registryCenter));
  }

  void _populateCollectionRegistries(Map<String, CollectionNode> tree,
      [String parentPath = '']) {
    for (final entry in tree.entries) {
      final collectionName = entry.key;
      final node = entry.value;
      final collectionType = node.type!;
      final collectionPath =
          parentPath.isEmpty ? collectionName : '$parentPath/$collectionName';

      registryCenter.collectionRegistry.add(
          CollectionWriter(collectionPath, collectionType, registryCenter));
      registryCenter.queryRegistry
          .add(QueryWriter(collectionPath, collectionType, registryCenter));
      registryCenter.queryMixinRegistry.add(
          QueryMixinWriter(collectionPath, collectionType, registryCenter));
      registryCenter.documentRegistry.add(DocumentWriter(collectionPath,
          collectionType, node.children, parentPath, registryCenter));

      if (node.children.isNotEmpty) {
        _populateCollectionRegistries(node.children, collectionPath);
      }
    }
  }

  List<(String, DartType, Element)> _getFields(
      InterfaceElement interfaceElement) {
    final objectChecker = TypeChecker.fromRuntime(Object);
    return interfaceElement.allSupertypes
        .where((supertype) => !objectChecker.isExactlyType(supertype))
        .expand((t) => t.element.accessors)
        .where((f) => !f.isStatic && f.isPublic && f.isGetter)
        .where((f) {
          final jsonKey = _jsonKeyChecker.firstAnnotationOf(f);
          if (jsonKey != null) {
            final jsonKeyConstantReader = ConstantReader(jsonKey);
            final includeFromJson =
                jsonKeyConstantReader.read('includeFromJson').boolValue;
            final includeToJson =
                jsonKeyConstantReader.read('includeToJson').boolValue;
            return includeFromJson && includeToJson;
          }
          return true;
        })
        .map((f) => (f.name, f.returnType, f))
        .toList();
  }
}

abstract class ClassWriter {
  String get name;
  String get key; // New getter for the registry key
  String generate();
}

abstract class ClassRegistry<T extends ClassWriter> {
  final Map<String, T> writers = {};

  void add(T writer) {
    writers[writer.key] = writer; // Use the key getter instead of name
  }

  void clear() {
    writers.clear();
  }

  T? getWriter(String key) => writers[key];

  String resolveName(String key) {
    final writer = writers[key];
    if (writer == null) {
      throw StateError('No writer found for key: $key');
    }
    return writer.name;
  }

  String generate() {
    return writers.values.map((writer) => writer.generate()).join('\n');
  }
}

class ConverterRegistry extends ClassRegistry<ConverterWriter> {}

class FieldsRegistry extends ClassRegistry<FieldsWriter> {}

class CollectionRegistry extends ClassRegistry<CollectionWriter> {}

class QueryRegistry extends ClassRegistry<QueryWriter> {}

class QueryMixinRegistry extends ClassRegistry<QueryMixinWriter> {}

class DocumentRegistry extends ClassRegistry<DocumentWriter> {}

class DatabaseRegistry extends ClassRegistry<DatabaseWriter> {}

class ConverterWriter extends ClassWriter {
  final InterfaceType type;

  ConverterWriter(this.type);

  @override
  String get name =>
      '${type.getDisplayString(withNullability: false)}Converter';

  @override
  String get key => type.getDisplayString(withNullability: false);

  @override
  String generate() {
    final className = type.getDisplayString(withNullability: false);
    return '''
class $name implements FirestoreConverter<$className> {
  static const $name instance = $name();
  const $name();

  @override
  $className fromJson(Map<String, dynamic> data) => $className.fromJson(data);

  @override
  Map<String, dynamic> toJson($className value) => value.toJson();
}
''';
  }
}

class FieldsWriter extends ClassWriter {
  final InterfaceType type;
  final List<(String, DartType, Element)> fields;
  final FieldsRegistry fieldsRegistry;
  final Set<String> processedTypes;

  FieldsWriter(
      this.type, this.fields, this.fieldsRegistry, this.processedTypes) {
    _processNestedTypes();
  }

  void _processNestedTypes() {
    for (final (_, fieldType, _) in fields) {
      if (_isNestedObject(fieldType) && fieldType is InterfaceType) {
        final nestedTypeString =
            fieldType.getDisplayString(withNullability: false);
        if (!processedTypes.contains(nestedTypeString)) {
          processedTypes.add(nestedTypeString);
          final nestedFields = _getFieldsFromType(fieldType);
          fieldsRegistry.add(FieldsWriter(
              fieldType, nestedFields, fieldsRegistry, processedTypes));
        }
      }
    }
  }

  List<(String, DartType, Element)> _getFieldsFromType(InterfaceType type) {
    final element = type.element;
    if (element is ClassElement) {
      return element.fields
          .where((f) => !f.isStatic && f.isPublic)
          .map((f) => (f.name, f.type, f))
          .toList();
    }
    return [];
  }

  @override
  String get name => '${type.getDisplayString(withNullability: false)}Fields';

  @override
  String get key => type.getDisplayString(withNullability: false);

  @override
  String generate() {
    final className = type.getDisplayString(withNullability: false);
    final buffer = StringBuffer();

    buffer.writeln(
        'final class $name extends FirestoreDocumentFields<$className> {');
    buffer.writeln('  const $name([super.prefix]);');

    for (final (name, fieldType, _) in fields) {
      if (_isNestedObject(fieldType)) {
        final nestedTypeName =
            fieldType.getDisplayString(withNullability: false);
        final nestedFieldsName = fieldsRegistry.resolveName(nestedTypeName);
        buffer.writeln(
            '  final ${Casing.camelCase(name)} = const $nestedFieldsName(\'$name.\');');
      } else {
        final typeParam = _getTypeString(fieldType);
        final cardinality = _isNullable(fieldType) ? 'Nullable' : 'NonNullable';
        buffer.writeln(
            '  final ${Casing.camelCase(name)} = const FirestoreField<$typeParam, $cardinality>(\'$name\');');
      }
    }

    buffer.writeln('}');
    return buffer.toString();
  }

  bool _isNestedObject(DartType type) {
    return type is InterfaceType &&
        !type.isDartCoreString &&
        !type.isDartCoreInt &&
        !type.isDartCoreDouble &&
        !type.isDartCoreBool &&
        !_isDateTime(type) &&
        !_isIterable(type) &&
        !type.isDartCoreMap;
  }

  bool _isDateTime(DartType type) {
    return type.element?.name == 'DateTime' &&
        type.element?.library?.name == 'dart.core';
  }

  bool _isIterable(DartType type) {
    return type is InterfaceType &&
        (type.isDartCoreIterable ||
            type.allSupertypes.any((t) => t.isDartCoreIterable));
  }

  bool _isNullable(DartType type) {
    return type.nullabilitySuffix == NullabilitySuffix.question;
  }

  String _getTypeString(DartType type) {
    if (_isIterable(type)) {
      final itemType = (type as InterfaceType).typeArguments.first;
      final itemTypeString = itemType.getDisplayString(withNullability: false);
      return 'List<$itemTypeString>';
    } else {
      return type.getDisplayString(withNullability: false);
    }
  }
}

class DatabaseWriter extends ClassWriter {
  final String className;
  final Map<String, CollectionNode> collectionTree;
  final RegistryCenter registryCenter;

  DatabaseWriter(this.className, this.collectionTree, this.registryCenter);

  @override
  String get name => '_\$$className';

  @override
  String get key => className; // Use className as the key

  @override
  String generate() {
    final collections = collectionTree.keys.map((collectionName) {
      final collectionClassName =
          registryCenter.collectionRegistry.resolveName(collectionName);
      return '''
  late final $collectionClassName ${Casing.camelCase(collectionName)} = $collectionClassName(sdk);''';
    }).join('\n');

    return '''
class $name extends FirestoreODM {
  $name(super.sdk);
$collections
}
''';
  }
}

class CollectionWriter extends ClassWriter {
  final String collectionPath;
  final InterfaceType collectionType;
  final RegistryCenter registryCenter;

  CollectionWriter(
      this.collectionPath, this.collectionType, this.registryCenter);

  @override
  String get name => '${Casing.pascalCase(collectionPath)}Collection';

  @override
  String get key => collectionPath; // Use collectionPath as the key

  @override
  String generate() {
    final typeString = collectionType.getDisplayString(withNullability: false);
    final queryName = registryCenter.queryRegistry.resolveName(collectionPath);
    final fieldsName = registryCenter.fieldsRegistry.resolveName(typeString);
    final queryMixinName =
        registryCenter.queryMixinRegistry.resolveName(collectionPath);
    final documentName =
        registryCenter.documentRegistry.resolveName(collectionPath);
    final collectionId = collectionPath.split('/').last;

    return '''
final class $name extends FirestoreCollection<$typeString> 
    with FieldQueryMixin<$typeString, $queryName, $fieldsName>, 
         $queryMixinName {
  $name(FirestoreSDK sdk, [String basePath = '']) : super(sdk, '\$basePath/$collectionId');

  @override
  $documentName doc([String? id]) => super.doc(id) as $documentName;

  @override
  $documentName getDocument(String path) => $documentName(sdk, path);
}
''';
  }
}

class QueryWriter extends ClassWriter {
  final String collectionPath;
  final InterfaceType collectionType;
  final RegistryCenter registryCenter;

  QueryWriter(this.collectionPath, this.collectionType, this.registryCenter);

  @override
  String get name => '${Casing.pascalCase(collectionPath)}Query';

  @override
  String get key => collectionPath; // Use collectionPath as the key

  @override
  String generate() {
    final typeString = collectionType.getDisplayString(withNullability: false);
    final fieldsName = registryCenter.fieldsRegistry.resolveName(typeString);
    final queryMixinName =
        registryCenter.queryMixinRegistry.resolveName(collectionPath);

    return '''
final class $name extends FirestoreQuery<$typeString> 
    with FieldQueryMixin<$typeString, $name, $fieldsName>, 
         $queryMixinName {
  $name(super.sdk, super.path);
  $name._withState(super.sdk, super.path, super.state) : super.withState();
}
''';
  }
}

class QueryMixinWriter extends ClassWriter {
  final String collectionPath;
  final InterfaceType collectionType;
  final RegistryCenter registryCenter;

  QueryMixinWriter(
      this.collectionPath, this.collectionType, this.registryCenter);

  @override
  String get name => '${Casing.pascalCase(collectionPath)}QueryMixin';

  @override
  String get key => collectionPath; // Use collectionPath as the key

  @override
  String generate() {
    final typeString = collectionType.getDisplayString(withNullability: false);
    final converterName =
        registryCenter.converterRegistry.resolveName(typeString);
    final fieldsName = registryCenter.fieldsRegistry.resolveName(typeString);
    final queryName = registryCenter.queryRegistry.resolveName(collectionPath);

    return '''
mixin $name on FirestoreQuery<$typeString> {
  @override
  final FirestoreConverter<$typeString> converter = $converterName.instance;

  @override
  final $fieldsName fields = const $fieldsName();

  @override
  $queryName getQuery(FirestoreQueryState state) =>
      $queryName._withState(sdk, path, state);
}
''';
  }
}

class DocumentWriter extends ClassWriter {
  final String collectionPath;
  final InterfaceType collectionType;
  final Map<String, CollectionNode> subTree;
  final String parentPath;
  final RegistryCenter registryCenter;

  DocumentWriter(this.collectionPath, this.collectionType, this.subTree,
      this.parentPath, this.registryCenter);

  @override
  String get name => '${Casing.pascalCase(collectionPath)}Document';

  @override
  String get key => collectionPath;

  @override
  String generate() {
    final typeString = collectionType.getDisplayString(withNullability: false);
    final converterName =
        registryCenter.converterRegistry.resolveName(typeString);

    final subCollections = subTree.keys.map((subCollectionName) {
      final subCollectionPath = parentPath.isEmpty
          ? '$collectionPath/$subCollectionName'
          : '$parentPath/$collectionPath/$subCollectionName';
      final subCollectionClassName =
          registryCenter.collectionRegistry.resolveName(subCollectionPath);
      return '''
  late final $subCollectionClassName ${Casing.camelCase(subCollectionName)} = 
      $subCollectionClassName(sdk, path);''';
    }).join('\n');

    return '''
class $name extends FirestoreDocument<$typeString> {
  $name(super.sdk, super.path);

  @override
  final FirestoreConverter<$typeString> converter = $converterName.instance;

$subCollections
}
''';
  }
}

class CollectionNode {
  InterfaceType? type;
  final Map<String, CollectionNode> children = {};

  CollectionNode();
}

// Helper functions

bool _isNestedObject(DartType type) {
  return type is InterfaceType &&
      !type.isDartCoreString &&
      !type.isDartCoreInt &&
      !type.isDartCoreDouble &&
      !type.isDartCoreBool &&
      !_isDateTime(type) &&
      !_isIterable(type) &&
      !type.isDartCoreMap;
}

bool _isIterable(DartType type) {
  return type is InterfaceType &&
      (type.isDartCoreIterable ||
          type.allSupertypes.any((t) => t.isDartCoreIterable));
}

bool _isNullable(DartType type) {
  return type is DynamicType ||
      type.isDartCoreNull ||
      type.nullabilitySuffix == NullabilitySuffix.question;
}

bool _isDateTime(DartType type) {
  return type.element?.name == 'DateTime' &&
      type.element?.library?.name == 'dart.core';
}

String _getTypeString(DartType type) {
  if (_isIterable(type)) {
    final itemType = (type as InterfaceType).typeArguments.first;
    final itemTypeString = itemType.getDisplayString(withNullability: false);
    return 'List<$itemTypeString>';
  } else {
    return type.getDisplayString(withNullability: false);
  }
}

// Builder definition

Builder firestoreBuilder(BuilderOptions options) => SharedPartBuilder(
      [FirestoreGenerator()],
      'odm',
    );
