// CIDR Atlas — Multi-region and recursive compartment discovery regressions.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cidr_oci/cidr_oci.dart';
import 'package:test/test.dart';

const tenancy = 'ocid1.tenancy.oc1..fictional';
const child = 'ocid1.compartment.oc1..child';
const nested = 'ocid1.compartment.oc1..nested';

List<String> operation(OciCommand command) =>
    command.arguments.sublist(command.arguments.indexOf('--max-retries') + 2);
String option(OciCommand command, String name) =>
    command.arguments[command.arguments.indexOf(name) + 1];
OciCommandResult response(Object? data) =>
    OciCommandResult(exitCode: 0, stdout: jsonEncode({'data': data}));
Map<String, Object> vcn(String id, String compartmentId) => {
      'id': id,
      'compartment-id': compartmentId,
      'cidr-blocks': ['10.0.0.0/16'],
    };
Map<String, Object> subnet(String id, String compartmentId, String parent) => {
      'id': id,
      'compartment-id': compartmentId,
      'vcn-id': parent,
      'cidr-block': '10.0.1.0/24',
    };

void main() {
  late Directory temporary;
  late OciConnection connection;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cidr-oci-expanded-');
    final config = File('${temporary.path}/config');
    await config
        .writeAsString('[DEFAULT]\ntenancy=$tenancy\nregion=us-phoenix-1\n');
    connection = OciConnection(
        executable: '/fictional/oci',
        configFile: config.path,
        profile: 'DEFAULT',
        tenancyId: tenancy,
        authMode: OciAuthMode.apiKey);
  });
  tearDown(() async => temporary.delete(recursive: true));

  test('selected regions are copied trimmed deduplicated and stamped',
      () async {
    final commands = <OciCommand>[];
    final selected = [' us-phoenix-1 ', 'eu-frankfurt-1', 'us-phoenix-1'];
    final client = OciCliClient(runner: (command) async {
      commands.add(command);
      selected.clear();
      final region = option(command, '--region');
      return response(
          operation(command)[1] == 'vcn' ? [vcn('vcn-$region', child)] : []);
    });
    final discovery = await client.discover(connection,
        regions: selected, compartmentId: ' $child ');
    final bundle = jsonDecode(discovery.bundleJson);
    expect(commands.map((c) => option(c, '--region')),
        ['us-phoenix-1', 'us-phoenix-1', 'eu-frankfurt-1', 'eu-frankfurt-1']);
    expect(commands.every((c) => operation(c).last == '--all'), isTrue);
    expect(
        commands.every((c) => option(c, '--compartment-id') == child), isTrue);
    expect((bundle['vcns'] as List).map((v) => v['region']),
        ['us-phoenix-1', 'eu-frankfurt-1']);
    final metadata = bundle['metadata'];
    expect(metadata.containsKey('region'), isFalse);
    expect(metadata['regions'], ['us-phoenix-1', 'eu-frankfurt-1']);
    expect(metadata['regionMode'], 'selected');
    expect(metadata['compartmentMode'], 'selected');
    expect(metadata['scopeCount'], 2);
    expect(metadata['completedScopeCount'], 2);
    expect(metadata['vcnCount'], 2);
  });

  test(
      'all READY regions and accessible descendants form one sequential matrix',
      () async {
    final commands = <OciCommand>[];
    var active = 0;
    final progress = <String>[];
    final client = OciCliClient(runner: (command) async {
      active++;
      expect(active, 1);
      commands.add(command);
      await Future<void>.delayed(Duration.zero);
      active--;
      final args = operation(command);
      if (args[1] == 'region-subscription') {
        expect(args.last, '--all');
        return response([
          {'region-name': 'us-phoenix-1', 'status': 'READY'},
          {'region-name': 'eu-frankfurt-1', 'status': 'IN_PROGRESS'},
          {'region-name': 'us-ashburn-1', 'status': 'READY'},
          {'region-name': 'us-phoenix-1', 'status': 'READY'},
        ]);
      }
      if (args[1] == 'compartment') {
        expect(option(command, '--compartment-id'), tenancy);
        expect(option(command, '--compartment-id-in-subtree'), 'true');
        expect(option(command, '--access-level'), 'ACCESSIBLE');
        expect(option(command, '--lifecycle-state'), 'ACTIVE');
        expect(args.last, '--all');
        return response([
          {'id': child, 'name': 'Child'},
          {'id': nested, 'name': 'Nested'},
          {'id': child, 'name': 'Duplicate'},
          {'id': tenancy, 'name': 'Root'},
        ]);
      }
      final compartmentId = option(command, '--compartment-id');
      final region = option(command, '--region');
      expect(args.last, '--all');
      return response(args[1] == 'vcn'
          ? [vcn('$region-$compartmentId', compartmentId)]
          : []);
    });
    final discovery = await client.discover(connection,
        allRegions: true, allCompartments: true, onProgress: progress.add);
    final bundle = jsonDecode(discovery.bundleJson);
    final lists =
        commands.where((c) => operation(c).first == 'network').toList();
    expect(lists.length, 12);
    expect(
        lists.map(
            (c) => '${option(c, '--region')}/${option(c, '--compartment-id')}'),
        [
          for (final region in ['us-phoenix-1', 'us-ashburn-1'])
            for (final compartmentId in [tenancy, child, nested])
              for (var i = 0; i < 2; i++) '$region/$compartmentId'
        ]);
    final metadata = bundle['metadata'];
    expect(metadata['regions'], ['us-phoenix-1', 'us-ashburn-1']);
    expect(metadata['compartmentIds'], [tenancy, child, nested]);
    expect(metadata['regionMode'], 'allReady');
    expect(metadata['compartmentMode'], 'allAccessible');
    expect(metadata['scopeCount'], 6);
    expect(metadata['completedScopeCount'], 6);
    expect(metadata['vcnCount'], 6);
    expect(metadata['subnetCount'], 0);
    expect(discovery.warnings.join(' '),
        allOf(contains('IN_PROGRESS'), contains('eu-frankfurt-1')));
    expect(
        metadata['coverage'],
        allOf(contains('IAM'), contains('not a complete tenancy'),
            contains('not evidence of deletion')));
    expect(progress.join(' '),
        allOf(contains(nested), contains('us-ashburn-1'), contains('6/6')));
  });

  test('no READY region fails before compartment or network requests',
      () async {
    var calls = 0;
    final client = OciCliClient(runner: (_) async {
      calls++;
      return response([
        {'region-name': 'eu-frankfurt-1', 'status': 'IN_PROGRESS'}
      ]);
    });
    await expectLater(
        client.discover(connection, allRegions: true, allCompartments: true),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'guidance', contains('READY'))));
    expect(calls, 1);
  });

  test(
      'required late scope failure returns no partial bundle and identifies scope',
      () async {
    final commands = <OciCommand>[];
    final client = OciCliClient(runner: (command) async {
      commands.add(command);
      if (option(command, '--region') == 'us-ashburn-1' &&
          operation(command)[1] == 'subnet') {
        return const OciCommandResult(
            exitCode: 1,
            stdout: '',
            stderr: '{"code":"NotAuthorized","message":"FICTIONAL_SECRET"}');
      }
      return response(operation(command)[1] == 'vcn'
          ? [vcn('vcn-${option(command, '--region')}', child)]
          : []);
    });
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1', 'us-ashburn-1', 'eu-frankfurt-1'],
            compartmentId: child),
        throwsA(isA<OciException>().having(
            (e) => e.message,
            'scope',
            allOf(
                contains('subnet list'),
                contains('us-ashburn-1'),
                contains(child),
                contains('2/3'),
                isNot(contains('FICTIONAL_SECRET'))))));
    expect(commands.length, 4);
  });

  test(
      'collects every regional compartment list before resolving external context',
      () async {
    final commands = <OciCommand>[];
    final client = OciCliClient(runner: (command) async {
      commands.add(command);
      final args = operation(command);
      if (args[1] == 'compartment')
        return response([
          {'id': child, 'name': 'Child'},
          {'id': nested, 'name': 'Nested'}
        ]);
      if (args[2] == 'get')
        fail(
            'Known VCN from another collected compartment must not be fetched');
      final selected = option(command, '--compartment-id');
      if (args[1] == 'vcn')
        return response(selected == nested ? [vcn('shared-vcn', nested)] : []);
      return response(selected == child
          ? [subnet('child-subnet', child, 'shared-vcn')]
          : []);
    });
    final result = await client.discover(connection,
        regions: ['us-phoenix-1'], allCompartments: true);
    final bundle = jsonDecode(result.bundleJson);
    expect(bundle['vcns'].length, 1);
    expect(bundle['subnets'].length, 1);
    expect(commands.length, 7);
  });

  test(
      'external context is deduplicated per region and context is region stamped',
      () async {
    final lookups = <String>[];
    final client = OciCliClient(runner: (command) async {
      final args = operation(command);
      if (args[2] == 'get') {
        lookups.add(option(command, '--region'));
        return response(vcn('shared-parent', nested));
      }
      if (args[1] == 'vcn') return response([]);
      return response([
        subnet('subnet-one', child, 'shared-parent'),
        subnet('subnet-two', child, 'shared-parent')
      ]);
    });
    final result = await client.discover(connection,
        regions: ['us-phoenix-1', 'us-ashburn-1'], compartmentId: child);
    final bundle = jsonDecode(result.bundleJson);
    expect(lookups, ['us-phoenix-1', 'us-ashburn-1']);
    expect((bundle['vcns'] as List).map((v) => v['region']), lookups);
    expect(bundle['metadata']['contextIncludedCount'], 2);
  });

  test(
      'all-compartment empty observation does not advise selecting included children',
      () async {
    final client = OciCliClient(runner: (_) async => response([]));
    final result = await client.discover(connection,
        regions: ['us-phoenix-1'], allCompartments: true);
    expect(
        result.warnings.join(' '),
        allOf(contains('No VCNs or subnets'), contains('IAM'),
            isNot(contains('choose a child'))));
  });

  test('all-compartment enumeration failure is fatal before resource lists',
      () async {
    var calls = 0;
    final client = OciCliClient(runner: (_) async {
      calls++;
      return const OciCommandResult(
          exitCode: 1, stdout: '', stderr: 'FICTIONAL_SECRET');
    });
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], allCompartments: true),
        throwsA(isA<OciException>().having(
            (e) => e.message,
            'scope',
            allOf(contains('compartment'), contains('us-phoenix-1'),
                isNot(contains('FICTIONAL_SECRET'))))));
    expect(calls, 1);
  });

  for (final specification in <({
    List<String> regions,
    bool allRegions,
    String? compartmentId,
    bool allCompartments
  })>[
    (
      regions: [],
      allRegions: false,
      compartmentId: child,
      allCompartments: false
    ),
    (
      regions: [' '],
      allRegions: false,
      compartmentId: child,
      allCompartments: false
    ),
    (
      regions: ['us-phoenix-1', ''],
      allRegions: false,
      compartmentId: child,
      allCompartments: false
    ),
    (
      regions: ['us-phoenix-1'],
      allRegions: true,
      compartmentId: child,
      allCompartments: false
    ),
    (
      regions: ['us-phoenix-1'],
      allRegions: false,
      compartmentId: null,
      allCompartments: false
    ),
    (
      regions: ['us-phoenix-1'],
      allRegions: false,
      compartmentId: ' ',
      allCompartments: false
    ),
    (
      regions: ['us-phoenix-1'],
      allRegions: false,
      compartmentId: child,
      allCompartments: true
    ),
  ]) {
    test('invalid scope modes are rejected before requests: $specification',
        () async {
      var calls = 0;
      final client = OciCliClient(runner: (_) async {
        calls++;
        return response([]);
      });
      await expectLater(
          client.discover(connection,
              regions: specification.regions,
              allRegions: specification.allRegions,
              compartmentId: specification.compartmentId,
              allCompartments: specification.allCompartments),
          throwsA(isA<OciException>()));
      expect(calls, 0);
    });
  }

  test('broad discovery permits work beyond the single-scope default deadline',
      () async {
    Future<void> collect({required bool broad}) async {
      var calls = 0;
      final client = OciCliClient(runner: (_) async {
        calls++;
        if (calls == 1)
          await Future<void>.delayed(const Duration(milliseconds: 30));
        return response([]);
      });
      await runZoned(
          () => client.discover(connection,
              regions:
                  broad ? ['us-phoenix-1', 'us-ashburn-1'] : ['us-phoenix-1'],
              compartmentId: child), zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          // Accelerate collection deadlines only; command and cleanup bounds
          // retain their normal timing so the test observes collection behavior.
          final accelerated = duration == const Duration(seconds: 180)
              ? const Duration(milliseconds: 10)
              : duration == const Duration(seconds: 1800)
                  ? const Duration(milliseconds: 150)
                  : duration;
          return parent.createTimer(zone, accelerated, callback);
        },
      ));
    }

    await expectLater(
        collect(broad: false),
        throwsA(isA<OciException>().having(
            (e) => e.message, 'collection bound', contains('timed out'))));
    await collect(broad: true);
  });

  test(
      'all READY regions retain one selected compartment and single region metadata',
      () async {
    final commands = <OciCommand>[];
    final client = OciCliClient(runner: (command) async {
      commands.add(command);
      if (operation(command)[1] == 'region-subscription')
        return response([
          {'region-name': 'us-phoenix-1', 'status': 'READY'}
        ]);
      return response([]);
    });
    final result = await client.discover(connection,
        allRegions: true, compartmentId: child);
    expect(commands.length, 3);
    expect(
        commands
            .skip(1)
            .every((command) => option(command, '--compartment-id') == child),
        isTrue);
    final metadata = jsonDecode(result.bundleJson)['metadata'];
    expect(metadata['region'], 'us-phoenix-1');
    expect(metadata['regions'], ['us-phoenix-1']);
    expect(metadata['regionMode'], 'allReady');
    expect(metadata['compartmentMode'], 'selected');
  });

  test('injected collection deadline covers broad-mode enumeration', () async {
    OciCommand? active;
    final client = OciCliClient(
        collectionTimeout: const Duration(milliseconds: 20),
        runner: (command) {
          active = command;
          return Completer<OciCommandResult>().future;
        });
    await expectLater(
        client.discover(connection, allRegions: true, allCompartments: true),
        throwsA(isA<OciException>().having(
            (e) => e.message,
            'timeout operation',
            allOf(contains('timed out'), contains('region')))));
    expect(active?.cancellation?.isCancelled, isTrue);
  });

  test('cancellation between matrix scopes starts no later region', () async {
    final cancellation = OciCancellation();
    final commands = <OciCommand>[];
    final client = OciCliClient(runner: (command) async {
      commands.add(command);
      if (commands.length == 2) cancellation.cancel();
      return response([]);
    });
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1', 'us-ashburn-1'],
            compartmentId: child,
            cancellation: cancellation),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'cancelled', contains('cancelled'))));
    expect(commands.length, 2);
  });
}
