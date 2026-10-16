// CIDR Atlas — Profile metadata and executable discovery contract tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:io';

import 'package:cidr_oci/cidr_oci.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File config;
  late File executable;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cidr-oci-profiles-');
    config = File('${directory.path}/config');
    executable = File('${directory.path}/oci');
    await executable.writeAsString('#!/bin/sh\nexit 0\n');
    if (!Platform.isWindows) {
      await Process.run('/bin/chmod', ['700', executable.path]);
    }
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> writeConfig() => config.writeAsString('''
[DEFAULT]
tenancy=ocid1.tenancy.oc1..fictional
region=us-phoenix-1
user=ocid1.user.oc1..fictional
fingerprint=FICTIONAL_FINGERPRINT
key_file=/not/read/private-key.pem
pass_phrase=FICTIONAL_SECRET
[PRODUCTION]
region=us-ashburn-1
[TOKEN]
security_token_file=/not/read/token
[OWN]
tenancy=ocid1.tenancy.oc1..another
region=eu-frankfurt-1
''');

  test('inherits DEFAULT metadata without reading credential files', () async {
    await writeConfig();
    final profiles = await OciCliClient().profiles(configFile: config.path);
    expect(
        profiles.map((p) => p.name), ['DEFAULT', 'PRODUCTION', 'TOKEN', 'OWN']);
    expect(profiles[1].tenancyId, 'ocid1.tenancy.oc1..fictional');
    expect(profiles[1].region, 'us-ashburn-1');
    expect(profiles[1].authMode, OciAuthMode.apiKey);
    expect(profiles[2].authMode, OciAuthMode.securityToken);
    expect(profiles[2].region, 'us-phoenix-1');
    expect(profiles[3].tenancyId, 'ocid1.tenancy.oc1..another');
  });

  test('suggests inherited token authentication and permits explicit override',
      () async {
    await config.writeAsString(
        '[DEFAULT]\ntenancy=fictional\nregion=us-phoenix-1\nsecurity_token_file=/missing\n[CHILD]\n');
    final client = OciCliClient();
    final profiles = await client.profiles(configFile: config.path);
    expect(profiles.last.authMode, OciAuthMode.securityToken);
    final connection = await client.connection(
        profile: 'CHILD',
        configFile: config.path,
        executable: executable.path,
        authMode: OciAuthMode.apiKey);
    expect(connection.authMode, OciAuthMode.apiKey);
    expect(connection.tenancyId, 'fictional');
  });

  test('finds an executable in PATH with spaces without executing it',
      () async {
    await writeConfig();
    final path = Directory('${directory.path}/tools with spaces');
    await path.create();
    final tool = await executable.copy('${path.path}/oci');
    final client = OciCliClient(
        environment: {'PATH': path.path}, executableCandidates: []);
    final connection =
        await client.connection(profile: 'DEFAULT', configFile: config.path);
    expect(connection.executable, tool.path);
  });

  test('uses standard-location candidates when Finder PATH omits tooling',
      () async {
    await writeConfig();
    final client = OciCliClient(
        environment: {'PATH': '/missing'},
        executableCandidates: [executable.path]);
    expect(
        (await client.connection(profile: 'DEFAULT', configFile: config.path))
            .executable,
        executable.path);
  });

  test('explicit missing executable never silently falls back', () async {
    await writeConfig();
    await expectLater(
        OciCliClient(executableCandidates: [executable.path]).connection(
            profile: 'DEFAULT',
            configFile: config.path,
            executable: '${directory.path}/missing'),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('executable'))));
  });

  test('missing tool gives actionable safe error', () async {
    await writeConfig();
    await expectLater(
        OciCliClient(environment: {'PATH': ''}, executableCandidates: [])
            .connection(profile: 'DEFAULT', configFile: config.path),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('OCI CLI'))));
  });

  test('explicit config wins over OCI environment path', () async {
    await writeConfig();
    final profiles =
        await OciCliClient(environment: {'OCI_CLI_CONFIG_FILE': '/missing'})
            .profiles(configFile: config.path);
    expect(profiles.first.name, 'DEFAULT');
  });

  test('missing config returns safe setup guidance', () async {
    await expectLater(
        OciCliClient().profiles(configFile: '${directory.path}/missing'),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('configuration'))));
  });

  for (final text in [
    'FICTIONAL_SECRET',
    '[broken',
    '[A]\nregion',
    '[A]\nregion=x\nregion=y',
    '[A]\n[A]'
  ]) {
    test(
        'malformed config is rejected without including raw content: ${text.length}',
        () async {
      await config.writeAsString(text);
      await expectLater(
          OciCliClient().profiles(configFile: config.path),
          throwsA(isA<OciException>().having((e) => e.message, 'safe message',
              isNot(contains('FICTIONAL_SECRET')))));
    });
  }

  test('missing tenancy is rejected before connecting', () async {
    await config.writeAsString('[DEFAULT]\nregion=us-phoenix-1\n');
    await expectLater(
        OciCliClient().connection(
            profile: 'DEFAULT',
            configFile: config.path,
            executable: executable.path),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('tenancy'))));
  });

  test('unknown profile is rejected before executable or credential access',
      () async {
    await writeConfig();
    await expectLater(
        OciCliClient().connection(
            profile: 'MISSING',
            configFile: config.path,
            executable: executable.path),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('profile'))));
  });

  test('a readable nonexecutable file is rejected as a CLI', () async {
    await writeConfig();
    await Process.run('/bin/chmod', ['600', executable.path]);
    await expectLater(
        OciCliClient().connection(
            profile: 'DEFAULT',
            configFile: config.path,
            executable: executable.path),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('executable'))));
  }, skip: Platform.isWindows ? 'POSIX executable permissions' : false);

  test('normalizes mixed-case options including inherited token metadata',
      () async {
    await config.writeAsString('''
[DEFAULT]
TENANCY=ocid1.tenancy.oc1..fictional
Region=us-phoenix-1
SECURITY_TOKEN_FILE=/fictional/token-not-read
[CHILD]
rEgIoN=us-ashburn-1
''');
    final client = OciCliClient();
    final profiles = await client.profiles(configFile: config.path);
    expect(profiles.last.region, 'us-ashburn-1');
    expect(profiles.last.tenancyId, 'ocid1.tenancy.oc1..fictional');
    expect(profiles.last.authMode, OciAuthMode.securityToken);
    final selected = await client.connection(
        profile: 'CHILD', configFile: config.path, executable: executable.path);
    expect(selected.tenancyId, 'ocid1.tenancy.oc1..fictional');
    expect(selected.authMode, OciAuthMode.securityToken);
  });

  test('accepts colon delimiters and preserves subsequent delimiters in values',
      () async {
    await config.writeAsString('''
[DEFAULT]
tenancy : ocid1.tenancy.oc1..fictional=value
region = literal:region=value
security_token_file : /fictional/token=not:read
''');
    final profiles = await OciCliClient().profiles(configFile: config.path);
    expect(profiles.single.tenancyId, 'ocid1.tenancy.oc1..fictional=value');
    expect(profiles.single.region, 'literal:region=value');
    expect(profiles.single.authMode, OciAuthMode.securityToken);
  });

  test('preserves section whitespace so connection selects the exact profile',
      () async {
    await config.writeAsString('''
[DEFAULT]
tenancy=ocid1.tenancy.oc1..default
region=us-phoenix-1
[ Team ]
tenancy=ocid1.tenancy.oc1..padded
[Team]
tenancy=ocid1.tenancy.oc1..plain
[ DEFAULT ]
tenancy=ocid1.tenancy.oc1..padded-default
''');
    final client = OciCliClient();
    final profiles = await client.profiles(configFile: config.path);
    expect(profiles.map((profile) => profile.name),
        ['DEFAULT', ' Team ', 'Team', ' DEFAULT ']);
    final selected = await client.connection(
        profile: ' Team ',
        configFile: config.path,
        executable: executable.path);
    expect(selected.profile, ' Team ');
    expect(selected.tenancyId, 'ocid1.tenancy.oc1..padded');
    expect(profiles.last.tenancyId, 'ocid1.tenancy.oc1..padded-default');
  });

  test(
      'rejects duplicate options after case normalization without exposing values',
      () async {
    await config
        .writeAsString('[DEFAULT]\nREGION=FICTIONAL_SECRET\nregion=other\n');
    await expectLater(
        OciCliClient().profiles(configFile: config.path),
        throwsA(isA<OciException>().having((error) => error.message,
            'safe message', isNot(contains('FICTIONAL_SECRET')))));
  });

  test(
      'accepts a section header followed by trailing text as ConfigParser does',
      () async {
    await config.writeAsString('[DEFAULT]\n'
        'tenancy=ocid1.tenancy.oc1..fictional\n'
        'region=us-ashburn-1\n'
        '[PROD] # production tenancy\n'
        'region=us-phoenix-1\n');
    final profiles = await OciCliClient().profiles(configFile: config.path);
    expect(profiles.map((profile) => profile.name), ['DEFAULT', 'PROD']);
    expect(profiles.last.region, 'us-phoenix-1');
    expect(profiles.last.tenancyId, 'ocid1.tenancy.oc1..fictional');
  });

  test('ignores indented continuation lines of credential options', () async {
    await config.writeAsString('[DEFAULT]\n'
        'tenancy=ocid1.tenancy.oc1..fictional\n'
        'region=us-ashburn-1\n'
        'key_file=/fictional/a\n'
        '  continued\n'
        '\n'
        '\tFICTIONAL_SECRET continued after a blank line\n'
        '[CHILD]\n'
        'region=us-phoenix-1\n');
    final profiles = await OciCliClient().profiles(configFile: config.path);
    expect(profiles.map((profile) => profile.name), ['DEFAULT', 'CHILD']);
    expect(profiles.first.region, 'us-ashburn-1');
    expect(profiles.last.region, 'us-phoenix-1');
  });

  test('continuation of a retained option is appended as ConfigParser does',
      () async {
    await config.writeAsString(
        '[DEFAULT]\ntenancy=ocid1.tenancy.oc1..fictional\nregion=us-\n  ashburn-1\n');
    final profiles = await OciCliClient().profiles(configFile: config.path);
    expect(profiles.single.region, 'us-\nashburn-1');
    expect(profiles.single.tenancyId, 'ocid1.tenancy.oc1..fictional');
  });

  test('equally indented options are separate options, not continuations',
      () async {
    await config.writeAsString('[DEFAULT]\n'
        '  tenancy=ocid1.tenancy.oc1..fictional\n'
        '  region=us-phoenix-1\n'
        '[NEXT]\n'
        '    region=eu-frankfurt-1\n');
    final profiles = await OciCliClient().profiles(configFile: config.path);
    expect(profiles.first.tenancyId, 'ocid1.tenancy.oc1..fictional');
    expect(profiles.first.region, 'us-phoenix-1');
    expect(profiles.last.region, 'eu-frankfurt-1');
  });

  for (final text in [
    '[DEFAULT]\n  continued\nregion=x',
    '[A]\nregion=x\n[A] # duplicate',
    // A valid section is open first, so only the empty header is at fault.
    '[DEFAULT]\ntenancy=t\n[] trailing\nregion=x',
  ]) {
    test('continuation and header edge cases stay strict: ${text.length}',
        () async {
      await config.writeAsString(text);
      await expectLater(OciCliClient().profiles(configFile: config.path),
          throwsA(isA<OciException>()));
    });
  }

  test('expands a home-relative explicit executable path', () async {
    await writeConfig();
    final connection = await OciCliClient(
            environment: {'HOME': directory.path}, executableCandidates: [])
        .connection(
            profile: 'DEFAULT', configFile: config.path, executable: '~/oci');
    expect(connection.executable, executable.path);
  });

  test('default candidates include the Oracle installer HOME/bin location',
      () async {
    await writeConfig();
    final bin = Directory('${directory.path}/bin');
    await bin.create();
    final installed = await executable.copy('${bin.path}/oci');
    if (!Platform.isWindows) {
      await Process.run('/bin/chmod', ['700', installed.path]);
    }
    final connection = await OciCliClient(
            environment: {'PATH': '/missing', 'HOME': directory.path})
        .connection(profile: 'DEFAULT', configFile: config.path);
    expect(connection.executable, installed.path);
  });

  test(
      'keeps interpolation-shaped metadata literal as OCI disables interpolation',
      () async {
    await config
        .writeAsString('[DEFAULT]\ntenancy=fictional\nregion=%(unexpanded)s\n');
    final profiles = await OciCliClient().profiles(configFile: config.path);
    expect(profiles.single.region, '%(unexpanded)s');
  });
}
