// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_dynamodb/otel_dynamodb.dart';

/// Traces Dynamodb calls with OpenTelemetry.
///
/// `otel_dynamodb` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Dynamodb call in
/// [tracedDynamoDb]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'dynamodb-example');

  // Wraps a DynamoDB operation (GetItem, PutItem, UpdateItem, DeleteItem, Query, Scan, etc.) in a CLIENT span using OTel db.* semconv (db.system=dynamodb).
  final dynamoDbId = await tracedDynamoDb<String>(
    operation: 'create',
    tableName: 'orders',
    indexName: 'products',
    region: 'us-east-1',
    consistencyMode: 'example',
    invoke: () async {
      // Make the Dynamodb call here, then report what it returned.
      const id = 'dynamodb_8f3a2c';
      return const DynamoDbCallResult(
          value: id, consumedCapacity: 0.5, itemCount: 3);
    },
  );
  OTelLog.info('tracedDynamoDb create returned $dynamoDbId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutDynamodbInstrumentationAsync.
  await runWithoutDynamodbInstrumentationAsync(
    () => tracedDynamoDb<String>(
      operation: 'create',
      tableName: 'orders',
      indexName: 'products',
      region: 'us-east-1',
      consistencyMode: 'example',
      invoke: () async {
        const id = 'dynamodb_8f3a2c';
        return const DynamoDbCallResult(
            value: id, consumedCapacity: 0.5, itemCount: 3);
      },
    ),
  );

  await OTel.shutdown();
}
