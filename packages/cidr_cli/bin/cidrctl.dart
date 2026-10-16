// CIDR Atlas desktop command-line entrypoint.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:io';

import 'package:cidr_cli/cidr_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCidrctlAsync(arguments);
}
