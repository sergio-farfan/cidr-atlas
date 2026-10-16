// CIDR Atlas — Scoped OCI command, selector and complete-bundle tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cidr_oci/cidr_oci.dart';
import 'package:test/test.dart';

const tenancy = 'ocid1.tenancy.oc1..fictional';
const compartment = 'ocid1.compartment.oc1..fictional';
const external = 'ocid1.compartment.oc1..external';
const vcn = {
  'id': 'vcn-selected',
  'compartment-id': compartment,
  'display-name': 'Fictional VCN',
  'cidr-blocks': ['10.0.0.0/16']
};
const externalVcn = {
  'id': 'vcn-context',
  'compartment-id': external,
  'display-name': 'Fictional context',
  'cidr-blocks': ['10.20.0.0/16']
};
const subnet = {
  'id': 'subnet-selected',
  'compartment-id': compartment,
  'display-name': 'Fictional subnet',
  'vcn-id': 'vcn-selected',
  'cidr-block': '10.0.1.0/24'
};
const externalSubnet = {
  'id': 'subnet-external',
  'compartment-id': compartment,
  'display-name': 'Fictional external subnet',
  'vcn-id': 'vcn-context',
  'cidr-block': '10.20.1.0/24'
};

OciCommandResult jsonResult(Object? data) =>
    OciCommandResult(exitCode: 0, stdout: jsonEncode({'data': data}));

List<String> suffix(OciCommand command) =>
    command.arguments.sublist(command.arguments.indexOf('--max-retries') + 2);

void main() {
  late Directory directory;
  late OciConnection connection;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cidr-oci-collection-');
    final config = File('${directory.path}/config');
    await config
        .writeAsString('[DEFAULT]\ntenancy=$tenancy\nregion=us-phoenix-1\n');
    connection = OciConnection(
        executable: '/fictional/oci',
        configFile: config.path,
        profile: 'DEFAULT',
        tenancyId: tenancy,
        authMode: OciAuthMode.apiKey);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('stamps the query region onto each collected resource', () async {
    final client = OciCliClient(
        runner: (command) async =>
            jsonResult(suffix(command)[1] == 'vcn' ? [vcn] : [subnet]));
    final result = await client.discover(connection,
        regions: ['us-ashburn-1'], compartmentId: compartment);
    final bundle = jsonDecode(result.bundleJson);
    expect(bundle['vcns'].single['region'], 'us-ashburn-1');
    expect(bundle['subnets'].single['region'], 'us-ashburn-1');
  });

  test(
      'isolates connection options, rc defaults and OCI environment for every request',
      () async {
    final commands = <OciCommand>[];
    final rcFiles = <String>[];
    final client = OciCliClient(
        environment: {
          'PATH': '/usr/bin',
          'HOME': '/fictional/home',
          'OCI_CLI_AUTH': 'instance_principal',
          'OCI_CLI_ENDPOINT': 'https://invalid',
          'OCI_CLI_QUERY': 'data[0]',
          'OCI_CLI_CONFIG_FILE': '/other/config',
          'OCI_CLI_PROFILE': 'OTHER',
          'OCI_CLI_RC_FILE': '/other/rc',
          'OCI_CLI_AUTO_PROMPT': 'True',
          'OCI_REGION_METADATA': 'redirect',
          'OCI_CONFIG_FILE': 'wrong',
          'SSL_CERT_FILE': '/trust/cert.pem',
          'REQUESTS_CA_BUNDLE': '/trust/requests.pem',
          'OCI_CLI_CERT_BUNDLE': '/trust/oci.pem',
        },
        runner: (command) async {
          commands.add(command);
          final rc =
              command.arguments[command.arguments.indexOf('--cli-rc-file') + 1];
          rcFiles.add(rc);
          expect(await File(rc).readAsString(), isEmpty);
          expect(command.executable, '/fictional/oci');
          expect(command.arguments.take(12), [
            '--config-file',
            connection.configFile,
            '--profile',
            'DEFAULT',
            '--auth',
            'api_key',
            '--region',
            'us-ashburn-1',
            '--output',
            'json',
            '--cli-rc-file',
            rc
          ]);
          expect(command.environment, {
            'PATH': '/usr/bin',
            'HOME': '/fictional/home',
            'SSL_CERT_FILE': '/trust/cert.pem',
            'REQUESTS_CA_BUNDLE': '/trust/requests.pem',
            'OCI_CLI_CERT_BUNDLE': '/trust/oci.pem',
          });
          expect(command.timeout, const Duration(seconds: 120));
          String option(String name) =>
              command.arguments[command.arguments.indexOf(name) + 1];
          // OCI CLI 3.94.1 passes --max-retries to the SDK as max_attempts,
          // which counts total attempts: 3 means one try plus two retries.
          expect(option('--max-retries'), '3');
          // 3 x (10 s connect + 15 s read) plus SDK backoff (at most ~5 s for
          // two retries) fits inside the 120 s per-command deadline.
          expect(option('--connection-timeout'), '10');
          expect(option('--read-timeout'), '15');
          return jsonResult(suffix(command)[1] == 'vcn' ? [vcn] : [subnet]);
        });
    final result = await client.discover(connection,
        regions: ['us-ashburn-1'], compartmentId: compartment);
    expect(jsonDecode(result.bundleJson)['subnets'], [
      {...subnet, 'region': 'us-ashburn-1'}
    ]);
    expect(commands.map(suffix), [
      ['network', 'vcn', 'list', '--compartment-id', compartment, '--all'],
      ['network', 'subnet', 'list', '--compartment-id', compartment, '--all'],
    ]);
    for (final file in rcFiles) {
      expect(await File(file).exists(), isFalse);
    }
  });

  test(
      'returns region subscriptions and status using explicit default profile region',
      () async {
    final client = OciCliClient(runner: (command) async {
      expect(command.arguments[command.arguments.indexOf('--region') + 1],
          'us-phoenix-1');
      expect(suffix(command), [
        'iam',
        'region-subscription',
        'list',
        '--tenancy-id',
        tenancy,
        '--all'
      ]);
      return jsonResult([
        {
          'region-name': 'us-phoenix-1',
          'status': 'READY',
          'is-home-region': true
        },
        {
          'region-name': 'eu-frankfurt-1',
          'status': 'IN_PROGRESS',
          'is-home-region': false
        },
      ]);
    });
    final regions = await client.regions(connection);
    expect(regions.map((r) => r.name), ['us-phoenix-1', 'eu-frankfurt-1']);
    expect(regions.map((r) => r.status), ['READY', 'IN_PROGRESS']);
    expect(regions.first.isHome, isTrue);
  });

  test(
      'lists accessible active compartments and synthetic root without include-root',
      () async {
    final client = OciCliClient(runner: (command) async {
      expect(suffix(command), [
        'iam',
        'compartment',
        'list',
        '--compartment-id',
        tenancy,
        '--compartment-id-in-subtree',
        'true',
        '--access-level',
        'ACCESSIBLE',
        '--lifecycle-state',
        'ACTIVE',
        '--all'
      ]);
      return jsonResult([
        {'id': compartment, 'name': 'Fictional project'}
      ]);
    });
    final scopes =
        await client.compartments(connection, region: 'us-phoenix-1');
    expect(scopes.map((c) => c.id), [tenancy, compartment]);
    expect(scopes.first.name.toLowerCase(), contains('tenancy root'));
  });

  test('explicit security token authentication is passed to the child',
      () async {
    final tokenConnection = OciConnection(
        executable: connection.executable,
        configFile: connection.configFile,
        profile: connection.profile,
        tenancyId: tenancy,
        authMode: OciAuthMode.securityToken);
    final client = OciCliClient(runner: (command) async {
      expect(command.arguments[command.arguments.indexOf('--auth') + 1],
          'security_token');
      return jsonResult([]);
    });
    final result = await client.discover(tokenConnection,
        regions: ['us-phoenix-1'], compartmentId: tenancy);
    expect(jsonDecode(result.bundleJson)['vcns'], isEmpty);
  });

  for (final output in ['', ' \n\t']) {
    test(
        'successful empty CLI list output is an empty scoped observation: ${output.isEmpty ? "empty" : "whitespace"}',
        () async {
      final client = OciCliClient(
          runner: (_) async => OciCommandResult(exitCode: 0, stdout: output));
      final discovery = await client.discover(connection,
          regions: ['us-phoenix-1'], compartmentId: tenancy);
      final bundle = jsonDecode(discovery.bundleJson);
      expect(bundle['vcns'], isEmpty);
      expect(bundle['subnets'], isEmpty);
      expect(
          discovery.warnings.join(' '),
          allOf(contains('No VCNs or subnets'), contains('directly'),
              contains('child compartment')));
      expect(
          bundle['metadata']['coverage'], contains('not evidence of deletion'));
    });
  }

  test('empty VCN list still collects subnets and required VCN context',
      () async {
    final client = OciCliClient(runner: (command) async {
      final args = suffix(command);
      if (args[2] == 'get') return jsonResult(externalVcn);
      if (args[1] == 'vcn') {
        return const OciCommandResult(exitCode: 0, stdout: '');
      }
      return jsonResult([externalSubnet]);
    });
    final discovery = await client.discover(connection,
        regions: ['us-phoenix-1'], compartmentId: compartment);
    final bundle = jsonDecode(discovery.bundleJson);
    expect(bundle['vcns'], [
      {...externalVcn, 'region': 'us-phoenix-1'}
    ]);
    expect(bundle['subnets'], [
      {...externalSubnet, 'region': 'us-phoenix-1'}
    ]);
    expect(discovery.warnings.join(' '), isNot(contains('No VCNs or subnets')));
  });

  test(
      'empty subscription and compartment CLI lists preserve valid empty selectors',
      () async {
    final client = OciCliClient(
        runner: (_) async => const OciCommandResult(exitCode: 0, stdout: ''));
    expect(await client.regions(connection), isEmpty);
    final scopes =
        await client.compartments(connection, region: 'us-phoenix-1');
    expect(scopes.map((scope) => scope.id), [tenancy]);
  });

  test('empty successful context is malformed with a safe operation and type',
      () async {
    final client = OciCliClient(runner: (command) async {
      final args = suffix(command);
      if (args[2] == 'get') {
        return const OciCommandResult(exitCode: 0, stdout: '');
      }
      return jsonResult(args[1] == 'vcn' ? [] : [externalSubnet]);
    });
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>().having(
            (error) => error.message,
            'safe operation and expected response type',
            allOf(contains('referenced VCN lookup'), contains('JSON object'),
                contains('empty'), isNot(contains('vcn-context'))))));
  });

  test(
      'malformed subnet fields identify operation and field without exposing values',
      () async {
    final client = OciCliClient(
        runner: (command) async => jsonResult(suffix(command)[1] == 'vcn'
            ? [vcn]
            : [
                {
                  ...subnet,
                  'vcn-id': {'FICTIONAL_SECRET': 'FICTIONAL_SECRET'}
                }
              ]));
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>().having(
            (error) => error.message,
            'safe operation and expected field type',
            allOf(
                contains('subnet list'),
                contains('vcn-id'),
                contains('string'),
                isNot(contains('FICTIONAL_SECRET')),
                isNot(contains('subnet-selected'))))));
  });

  test(
      'malformed list envelope identifies expected type without exposing output',
      () async {
    final client = OciCliClient(
        runner: (_) async => const OciCommandResult(
            exitCode: 0, stdout: '{"data":"FICTIONAL_SECRET"}'));
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>().having(
            (error) => error.message,
            'safe operation and expected list type',
            allOf(contains('VCN list'), contains('data'), contains('list'),
                isNot(contains('FICTIONAL_SECRET'))))));
  });

  test('empty failed list is never treated as a successful empty observation',
      () async {
    final client = OciCliClient(
        runner: (_) async => const OciCommandResult(
            exitCode: 1, stdout: '', stderr: 'FICTIONAL_SECRET'));
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>().having((error) => error.message,
            'failure is safe', isNot(contains('FICTIONAL_SECRET')))));
  });

  test(
      'deduplicates external VCN context without enumerating its other subnets',
      () async {
    final commands = <List<String>>[];
    final times = [
      DateTime.parse('2026-10-15T12:00:00Z'),
      DateTime.parse('2026-10-15T12:00:30Z')
    ].iterator;
    final progress = <String>[];
    final client = OciCliClient(clock: () {
      times.moveNext();
      return times.current;
    }, runner: (command) async {
      final args = suffix(command);
      commands.add(args);
      if (args[2] == 'get') return jsonResult(externalVcn);
      if (args[1] == 'vcn') return jsonResult([vcn]);
      return jsonResult([
        subnet,
        externalSubnet,
        {...externalSubnet, 'id': 'subnet-external-two'}
      ]);
    });
    final discovery = await client.discover(connection,
        regions: ['us-phoenix-1'],
        compartmentId: compartment,
        onProgress: progress.add);
    final bundle = jsonDecode(discovery.bundleJson);
    expect(bundle['vcns'], [
      {...vcn, 'region': 'us-phoenix-1'},
      {...externalVcn, 'region': 'us-phoenix-1'}
    ]);
    expect(bundle['subnets'].length, 3);
    expect(commands, [
      ['network', 'vcn', 'list', '--compartment-id', compartment, '--all'],
      ['network', 'subnet', 'list', '--compartment-id', compartment, '--all'],
      ['network', 'vcn', 'get', '--vcn-id', 'vcn-context'],
    ]);
    expect(bundle['metadata']['tenancy'], tenancy);
    expect(bundle['metadata']['region'], 'us-phoenix-1');
    expect(
        bundle['metadata']['collectionStartedAt'], '2026-10-15T12:00:00.000Z');
    expect(bundle['metadata']['collectedAt'], '2026-10-15T12:00:30.000Z');
    final coverage = bundle['metadata']['coverage'] as String;
    for (final evidence in [
      compartment,
      'us-phoenix-1',
      'all pages',
      'not a transactionally consistent',
      'not a complete tenancy',
      'vcn-context',
      '2026-10-15T12:00:00.000Z'
    ]) {
      expect(coverage, contains(evidence));
    }
    expect(discovery.warnings.join(' '), contains(external));
    expect(progress.length, greaterThanOrEqualTo(3));
  });

  for (final code in ['NotAuthorizedOrNotFound', 'NotFound', 'NotAuthorized']) {
    test('denied or missing context remains a warning: $code', () async {
      final client = OciCliClient(runner: (command) async {
        final args = suffix(command);
        if (args[2] == 'get') {
          return OciCommandResult(
              exitCode: 1,
              stdout: '',
              stderr: 'ServiceError:\n${jsonEncode({
                    'code': code,
                    'message': 'FICTIONAL_SECRET'
                  })}');
        }
        return jsonResult(args[1] == 'vcn' ? [] : [externalSubnet]);
      });
      final discovery = await client.discover(connection,
          regions: ['us-phoenix-1'], compartmentId: compartment);
      final bundle = jsonDecode(discovery.bundleJson);
      expect(bundle['vcns'], isEmpty);
      expect(bundle['subnets'][0]['vcn-id'], 'vcn-context');
      expect(bundle['subnets'][0].containsKey('parentId'), isFalse);
      expect(discovery.warnings.join(' '), contains('vcn-context'));
      expect(discovery.warnings.join(' '), isNot(contains('FICTIONAL_SECRET')));
      expect(bundle['metadata']['coverage'], contains('unavailable'));
    });
  }

  test(
      'required second list failure never returns a partial discovery or raw stderr',
      () async {
    final client = OciCliClient(
        runner: (command) async => suffix(command)[1] == 'vcn'
            ? jsonResult([vcn])
            : const OciCommandResult(
                exitCode: 1, stdout: '', stderr: 'FICTIONAL_SECRET'));
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>().having((e) => e.message, 'safe error',
            isNot(contains('FICTIONAL_SECRET')))));
  });

  test(
      'expired authentication gives repair guidance rather than interactive login',
      () async {
    final client = OciCliClient(
        runner: (_) async => const OciCommandResult(
            exitCode: 1,
            stdout: '',
            stderr:
                'ServiceError:\n{"code":"NotAuthenticated","message":"FICTIONAL_SECRET"}'));
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>().having(
            (e) => e.message,
            'guidance',
            allOf(contains('profile'), contains('authentication'),
                isNot(contains('FICTIONAL_SECRET'))))));
  });

  for (final stdout in [
    'not json',
    '[]',
    '{}',
    '{"data":{}}',
    '{"data":[1]}',
    '{"data":[{"id":"vcn"}]}'
  ]) {
    test('malformed successful resource output is fatal: $stdout', () async {
      final client = OciCliClient(
          runner: (_) async => OciCommandResult(exitCode: 0, stdout: stdout));
      await expectLater(
          client.discover(connection,
              regions: ['us-phoenix-1'], compartmentId: compartment),
          throwsA(isA<OciException>()));
    });
  }

  test('malformed successful context is fatal', () async {
    final client = OciCliClient(runner: (command) async {
      final args = suffix(command);
      if (args[2] == 'get') {
        return jsonResult({'id': 'wrong-vcn', 'compartment-id': external});
      }
      return jsonResult(args[1] == 'vcn' ? [] : [externalSubnet]);
    });
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>()));
  });

  test(
      'context server errors fail collection rather than looking like missing resources',
      () async {
    final client = OciCliClient(runner: (command) async {
      final args = suffix(command);
      if (args[2] == 'get') {
        return const OciCommandResult(
            exitCode: 1, stdout: '', stderr: '{"code":"InternalError"}');
      }
      return jsonResult(args[1] == 'vcn' ? [] : [externalSubnet]);
    });
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>()));
  });

  test(
      'cancellation ignores a late runner result and never starts the second list',
      () async {
    final cancellation = OciCancellation();
    final pending = Completer<OciCommandResult>();
    var calls = 0;
    final client = OciCliClient(runner: (_) {
      calls++;
      return pending.future;
    });
    final result = client.discover(connection,
        regions: ['us-phoenix-1'],
        compartmentId: compartment,
        cancellation: cancellation);
    final expectation = expectLater(
        result,
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('cancelled'))));
    // Only bounds a wait for success; generous for a loaded runner.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (calls == 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    cancellation.cancel();
    await expectation;
    pending.complete(jsonResult([vcn]));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
  });

  test(
      'overall deadline cancels current request even when individual timeout is longer',
      () async {
    OciCommand? active;
    final client = OciCliClient(
        collectionTimeout: const Duration(milliseconds: 25),
        runner: (command) {
          active = command;
          return Completer<OciCommandResult>().future;
        });
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('timed out'))));
    expect(active?.cancellation?.isCancelled, isTrue);
  });

  test('per-command deadline bounds an injected unresponsive runner', () async {
    final client = OciCliClient(
        commandTimeout: const Duration(milliseconds: 25),
        runner: (_) => Completer<OciCommandResult>().future);
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('timed out'))));
  });

  test(
      'cancellation during context lookup is fatal and ignores a late context result',
      () async {
    final cancellation = OciCancellation();
    final contextStarted = Completer<void>();
    final contextResult = Completer<OciCommandResult>();
    final client = OciCliClient(runner: (command) async {
      final args = suffix(command);
      if (args[2] == 'get') {
        contextStarted.complete();
        return contextResult.future;
      }
      return jsonResult(args[1] == 'vcn' ? [] : [externalSubnet]);
    });
    final pending = client.discover(connection,
        regions: ['us-phoenix-1'],
        compartmentId: compartment,
        cancellation: cancellation);
    final expectation = expectLater(
        pending,
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('cancelled'))));
    await contextStarted.future;
    cancellation.cancel();
    contextResult.complete(jsonResult(externalVcn));
    await expectation;
  });

  test(
      'wrong-compartment successful resources fail rather than broadening selected scope',
      () async {
    final client = OciCliClient(runner: (_) async => jsonResult([externalVcn]));
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>()));
  });

  test('blank scope is rejected before starting a request', () async {
    var calls = 0;
    final client = OciCliClient(runner: (_) async {
      calls++;
      return jsonResult([]);
    });
    await expectLater(
        client.discover(connection, regions: [' '], compartmentId: compartment),
        throwsA(isA<OciException>()));
    expect(calls, 0);
  });

  test('recognizes installed CLI plain-text expired-session failure safely',
      () async {
    final client = OciCliClient(
        runner: (_) async => const OciCommandResult(
            exitCode: 1,
            stdout:
                'ERROR: This CLI session has expired, so it cannot currently be used to run commands\n'
                'Do you want to re-authenticate your CLI session profile? [Y/n]: ',
            stderr: 'Aborted! FICTIONAL_SECRET'));
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>().having(
            (error) => error.message,
            'safe renewal guidance',
            allOf(contains('profile'), contains('session'), contains('renew'),
                isNot(contains('FICTIONAL_SECRET'))))));
  });

  test('unrelated unstructured expiry text remains a generic safe failure',
      () async {
    final client = OciCliClient(
        runner: (_) async => const OciCommandResult(
            exitCode: 1,
            stdout: '',
            stderr:
                'FICTIONAL_SECRET resource display-name says session expired'));
    await expectLater(
        client.discover(connection,
            regions: ['us-phoenix-1'], compartmentId: compartment),
        throwsA(isA<OciException>().having(
            (error) => error.message,
            'safe generic guidance',
            allOf(isNot(contains('authentication failed')),
                isNot(contains('FICTIONAL_SECRET'))))));
  });
}
