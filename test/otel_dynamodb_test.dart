// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_dynamodb/otel_dynamodb.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_dynamodb-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('GetItem records CLIENT span with consumed capacity', () async {
    await tracedDynamoDb<String>(
      operation: 'GetItem',
      tableName: 'Orders',
      consistencyMode: 'strong',
      region: 'us-east-1',
      invoke: () async => const DynamoDbCallResult(
        value: 'ok',
        consumedCapacity: 0.5,
      ),
    );
    final span = spans.findSpanByName('GetItem Orders');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.client);
    final a = attrsOf(span);
    expect(a['db.system'], 'dynamodb');
    expect(a['db.operation'], 'GetItem');
    expect(a['db.collection.name'], 'Orders');
    expect(a['aws.dynamodb.table.name'], 'Orders');
    expect(a['aws.dynamodb.consistent_read'], true);
    expect(a['cloud.region'], 'us-east-1');
    expect(a['aws.dynamodb.consumed_capacity.total'], 0.5);
  });

  test('Query with GSI records index name + item count', () async {
    await tracedDynamoDb<String>(
      operation: 'Query',
      tableName: 'Orders',
      indexName: 'byCustomer',
      invoke: () async => const DynamoDbCallResult(
        value: 'ok',
        itemCount: 3,
      ),
    );
    final a = attrsOf(spans.findSpanByName('Query Orders')!);
    expect(a['aws.dynamodb.index.name'], 'byCustomer');
    expect(a['aws.dynamodb.item_count'], 3);
  });

  test('records exception', () async {
    await expectLater(
      tracedDynamoDb<String>(
        operation: 'GetItem',
        tableName: 'T',
        invoke: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      spans.findSpanByName('GetItem T')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutDynamodbInstrumentationAsync(() async {
      await tracedDynamoDb<String>(
        operation: 'GetItem',
        tableName: 'T',
        invoke: () async => const DynamoDbCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('GetItem '), isEmpty);
  });
}
