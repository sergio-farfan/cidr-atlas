// CIDR Atlas — Bounded subprocess execution for OCI requests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

typedef OciCommandRunner = Future<OciCommandResult> Function(
    OciCommand command);

class OciCommand {
  const OciCommand(
      {required this.executable,
      required this.arguments,
      required this.environment,
      required this.timeout,
      this.cancellation});
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final Duration timeout;
  final OciCancellation? cancellation;
}

class OciCommandResult {
  const OciCommandResult(
      {required this.exitCode, required this.stdout, this.stderr = ''});
  final int exitCode;
  final String stdout, stderr;
}

class OciProcessRunner {
  const OciProcessRunner();
  Future<OciCommandResult> run(OciCommand command) async {
    if (command.cancellation?.isCancelled ?? false) {
      throw const OciException('OCI request cancelled.');
    }
    final watch = Stopwatch()..start();
    final Process process;
    try {
      process = await Process.start(command.executable, command.arguments,
          environment: command.environment,
          includeParentEnvironment: false,
          runInShell: false);
    } on ProcessException {
      throw const OciException(
          'Cannot start the OCI CLI. Check its executable path and installation.');
    }
    final output = _CapturedOutput(process.stdout);
    final errors = _CapturedOutput(process.stderr);
    final completed = Future.wait<Object>(
        [process.exitCode, output.done, errors.done],
        eagerError: true);
    final interrupted = Completer<Object>();
    void interrupt(String message) {
      if (!interrupted.isCompleted) interrupted.complete(OciException(message));
    }

    final remaining = command.timeout - watch.elapsed;
    final timer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => interrupt(
            'OCI request timed out. Retry the selected scope or check connectivity.'));
    command.cancellation?.whenCancelled
        .then((_) => interrupt('OCI request cancelled.'));
    try {
      // Subscribe to both streams before closing stdin or awaiting process exit.
      await process.stdin.close();
      if (command.cancellation?.isCancelled ?? false)
        interrupt('OCI request cancelled.');
      final result = await Future.any<Object>([completed, interrupted.future]);
      if (result is OciException) throw result;
      final values = result as List<Object>;
      return OciCommandResult(
          exitCode: values[0] as int,
          stdout: values[1] as String,
          stderr: values[2] as String);
    } catch (error) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(milliseconds: 300));
      } on TimeoutException {
        process.kill(
            Platform.isWindows ? ProcessSignal.sigterm : ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 1));
        } on TimeoutException {/* Stream cancellation below bounds cleanup. */}
      }
      try {
        await completed.timeout(const Duration(seconds: 1));
      } catch (_) {/* Error details may contain credentials. */}
      if (error is OciException) rethrow;
      throw const OciException(
          'Cannot read the OCI CLI response. Check the CLI installation and retry.');
    } finally {
      timer.cancel();
      await output.close();
      await errors.close();
    }
  }
}

class _CapturedOutput {
  _CapturedOutput(Stream<List<int>> stream) {
    _subscription = stream.transform(utf8.decoder).listen(_buffer.write,
        onError: (Object error, StackTrace stack) {
      if (!_done.isCompleted) _done.completeError(error, stack);
    }, onDone: () {
      if (!_done.isCompleted) _done.complete(_buffer.toString());
    });
  }
  final _buffer = StringBuffer();
  final _done = Completer<String>();
  late final StreamSubscription<String> _subscription;
  Future<String> get done => _done.future;
  Future<void> close() => _subscription.cancel();
}
