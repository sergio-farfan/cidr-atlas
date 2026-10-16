// CIDR Atlas
// Strict new reservations, stale plans, and decision persistence tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:io';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:test/test.dart';

const candidate = PrefixRecord(
  id: 'fictional-plan',
  cidr: '10.91.0.0/25',
  name: 'Fictional planned VCN',
  routingDomain: 'fictional',
  status: PrefixStatus.reserved,
  resourceId: 'fictional-vcn',
  tenancy: 'fictional-tenancy',
  region: 'us-phoenix-1',
  notes:
      'Planning decision: 124 IPs including growth and maintenance; OCI /25 capacity 125.',
  source: 'planner',
);

void main() {
  test('new reservation cannot overwrite an existing record or audit entry',
      () {
    final store = InventoryStore.memory();
    addTearDown(store.close);
    store.save(candidate);
    final history = store.history().length;
    expect(() => store.reserve(candidate.copyWith(name: 'Overwrite')),
        throwsA(isA<FormatException>()));
    expect(store.list().single.name, candidate.name);
    expect(store.history().length, history);
  });

  test('stale proposal conflicts are rejected against a second connection', () {
    final directory = Directory.systemTemp.createTempSync('atlas_planning_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final first = InventoryStore.open('${directory.path}/inventory.sqlite');
    final second = InventoryStore.open('${directory.path}/inventory.sqlite');
    addTearDown(first.close);
    addTearDown(second.close);
    expect(first.list(), isEmpty);
    second.save(candidate.copyWith(id: 'other-client'));
    final before = first.history().length;
    expect(() => first.reserve(candidate),
        throwsA(isA<InventoryConflictException>()));
    expect(first.list().single.id, 'other-client');
    expect(first.history().length, before);
  });

  test('rationale survives reopen, backup transfer, and OCI refresh', () {
    final directory = Directory.systemTemp.createTempSync('atlas_rationale_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/inventory.sqlite';
    final initial = InventoryStore.open(path);
    initial.reserve(candidate);
    initial.close();
    final reopened = InventoryStore.open(path);
    addTearDown(reopened.close);
    expect(reopened.list().single.notes, candidate.notes);
    final transferred = InventoryStore.memory();
    addTearDown(transferred.close);
    transferred.applyImport(InventoryImport.json(
        InventoryImport.exportJson(reopened.list()),
        routingDomain: 'fictional'));
    expect(transferred.list().single.notes, candidate.notes);
    final refresh = InventoryImport.json('''{
      "metadata":{"tenancy":"fictional-tenancy","region":"us-phoenix-1","collectedAt":"2026-10-15T20:00:00Z"},
      "vcns":[{"id":"fictional-vcn","display-name":"Observed VCN","compartment-id":"fictional-compartment","cidr-block":"10.91.0.0/25"}],"subnets":[]
    }''', routingDomain: 'fictional', existingRecords: transferred.list());
    transferred.applyImport(refresh);
    expect(transferred.list(), hasLength(1));
    expect(transferred.list().single.notes, candidate.notes);
    expect(transferred.list().single.status, PrefixStatus.reserved);
  });
}
