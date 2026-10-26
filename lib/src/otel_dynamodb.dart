// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

import 'otel_dynamodb_suppression.dart';

const _tracerName = 'dartastic_otel_libs_dynamodb';
const _systemValue = 'dynamodb';

APITracer _tracer() => OTelAPI.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedDynamoDb*` callback.
class DynamoDbCallResult<T> {
  /// Creates a call result.
  const DynamoDbCallResult({
    required this.value,
    this.consumedCapacity,
    this.itemCount,
  });

  /// The value returned to the caller.
  final T value;
  final double? consumedCapacity;
  final int? itemCount;
}

/// Wraps a DynamoDB operation (GetItem, PutItem, UpdateItem,
/// DeleteItem, Query, Scan, etc.) in a CLIENT span using OTel
/// db.* semconv (db.system=dynamodb).
Future<T> tracedDynamoDb<T>({
  required String operation,
  required String tableName,
  required Future<DynamoDbCallResult<T>> Function() invoke,
  String? indexName,
  String? region,
  String? consistencyMode,
}) async {
  if (dynamodbInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'db.system': _systemValue,
    'db.operation': operation,
    'db.collection.name': tableName,
    'aws.dynamodb.table.name': tableName,
    'rpc.system': 'aws-api',
    'rpc.service': 'DynamoDB',
    'rpc.method': operation,
  };
  if (indexName != null) m['aws.dynamodb.index.name'] = indexName;
  if (region != null) m['cloud.region'] = region;
  if (consistencyMode != null) {
    m['aws.dynamodb.consistent_read'] = consistencyMode == 'strong';
  }

  final span = _tracer().startSpan(
    '$operation $tableName',
    kind: SpanKind.client,
    attributes: OTelAPI.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.consumedCapacity != null) {
      extras.add(OTelAPI.attributeDouble(
        'aws.dynamodb.consumed_capacity.total',
        r.consumedCapacity!,
      ));
    }
    if (r.itemCount != null) {
      extras.add(OTelAPI.attributeInt(
        'aws.dynamodb.item_count',
        r.itemCount!,
      ));
    }
    if (extras.isNotEmpty) span.addAttributes(OTelAPI.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTelAPI.attributes([
      OTelAPI.attributeString(
        ErrorAttributes.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
