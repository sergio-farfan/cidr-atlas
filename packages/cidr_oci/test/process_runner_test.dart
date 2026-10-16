// CIDR Atlas — Real child-process lifecycle and stream regression tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cidr_oci/cidr_oci.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File child;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cidr-oci-child-');
    child = File('${directory.path}/child.dart');
  });
  tearDown(() async => directory.delete(recursive: true));

  OciCommand command(
          {OciCancellation? cancellation,
          Duration timeout = const Duration(seconds: 10),
          List<String> arguments = const [],
          Map<String, String> environment = const {}}) =>
      OciCommand(
          executable: Platform.resolvedExecutable,
          arguments: [child.path, ...arguments],
          environment: environment,
          timeout: timeout,
          cancellation: cancellation);

  test('drains both streams concurrently, closes stdin and preserves arguments',
      () async {
    await child.writeAsString('''
import 'dart:io';
import 'dart:convert';
Future<void> main(List<String> args) async {
  await stdin.drain<void>();
  for (var i = 0; i < 128; i++) {
    stdout.write('x' * 8192);
    stderr.write('y' * 8192);
  }
  stdout.writeln(jsonEncode(args));
}
''');
    final result = await const OciProcessRunner()
        .run(command(arguments: ['space value', r'$(never-run)', ';literal']));
    expect(result.exitCode, 0);
    expect(result.stderr.length, 1048576);
    expect(result.stdout.substring(1048576).trim(),
        jsonEncode(['space value', r'$(never-run)', ';literal']));
  });

  test('does not inherit unspecified environment values', () async {
    expect(Platform.environment['PUB_CACHE'], isNotNull);
    await child.writeAsString(
        "import 'dart:io'; void main() { stdout.write(Platform.environment['PUB_CACHE'] ?? 'absent'); }");
    final result = await const OciProcessRunner().run(command());
    expect(result.stdout, 'absent');
  });

  Future<File> sleepingChild() async {
    final marker = File('${directory.path}/finished');
    await child.writeAsString('''
import 'dart:async';
import 'dart:io';
Future<void> main() async {
  File('${directory.path}/ready').writeAsStringSync('ready');
  await Future<void>.delayed(const Duration(seconds: 3));
  File('${marker.path}').writeAsStringSync('should never finish');
}
''');
    return marker;
  }

  test('timeout kills a real child before its delayed side effect', () async {
    final marker = await sleepingChild();
    final stopwatch = Stopwatch()..start();
    await expectLater(
        const OciProcessRunner()
            .run(command(timeout: const Duration(milliseconds: 450))),
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('timed out'))));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(await marker.exists(), isFalse);
  });

  test('cancellation kills a running real child and drains it', () async {
    final marker = await sleepingChild();
    final cancellation = OciCancellation();
    final pending =
        const OciProcessRunner().run(command(cancellation: cancellation));
    final outcome = expectLater(
        pending,
        throwsA(isA<OciException>()
            .having((e) => e.message, 'message', contains('cancelled'))));
    final ready = File('${directory.path}/ready');
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!await ready.exists() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await ready.exists(), isTrue);
    cancellation.cancel();
    await outcome;
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(await marker.exists(), isFalse);
  });

  test('pre-cancelled command does not start a child', () async {
    final marker = File('${directory.path}/started');
    await child.writeAsString(
        "import 'dart:io'; void main() { File('${marker.path}').writeAsStringSync('started'); }");
    final cancellation = OciCancellation()..cancel();
    await expectLater(
        const OciProcessRunner().run(command(cancellation: cancellation)),
        throwsA(isA<OciException>()));
    expect(await marker.exists(), isFalse);
  });

  test(
      'missing executable produces safe guidance without platform error detail',
      () async {
    await expectLater(
        const OciProcessRunner().run(OciCommand(
            executable: '${directory.path}/FICTIONAL_SECRET',
            arguments: [],
            environment: {},
            timeout: const Duration(seconds: 1))),
        throwsA(isA<OciException>().having((e) => e.message, 'safe message',
            isNot(contains('FICTIONAL_SECRET')))));
  });

  test('malformed UTF-8 is a safe failure and terminates a still-running child',
      () async {
    final marker = File('${directory.path}/finished');
    await child.writeAsString('''
import 'dart:async';
import 'dart:io';
Future<void> main() async {
  stdout.add([255]);
  await stdout.flush();
  await Future<void>.delayed(const Duration(seconds: 2));
  File('${marker.path}').writeAsStringSync('finished');
}
''');
    final stopwatch = Stopwatch()..start();
    await expectLater(
        const OciProcessRunner().run(command()), throwsA(isA<OciException>()));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await marker.exists(), isFalse);
  });

  test('cancellation escalates when a POSIX child ignores termination',
      () async {
    final ready = File('${directory.path}/ready');
    await child.writeAsString('''
import 'dart:async';
import 'dart:io';
Future<void> main() async {
  ProcessSignal.sigterm.watch().listen((_) {});
  File('${ready.path}').writeAsStringSync('ready');
  await Completer<void>().future;
}
''');
    final cancellation = OciCancellation();
    final pending =
        const OciProcessRunner().run(command(cancellation: cancellation));
    final outcome = expectLater(pending, throwsA(isA<OciException>()));
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!await ready.exists() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await ready.exists(), isTrue);
    final stopwatch = Stopwatch()..start();
    cancellation.cancel();
    await outcome;
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  }, skip: Platform.isWindows ? 'POSIX signal behavior' : false);
}
