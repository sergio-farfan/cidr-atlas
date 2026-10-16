// CIDR Atlas
// macOS application lifecycle integration.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// CIDR Atlas > Settings… (Cmd+,). Flutter handles the shortcut itself while
  /// the workspace has focus; the menu item and any unhandled shortcut ask the
  /// workspace to open Settings over the channel instead.
  @IBAction func openSettings(_ sender: Any?) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else { return }
    FlutterMethodChannel(
      name: "dev.cidratlas.desktop/menu",
      binaryMessenger: controller.engine.binaryMessenger
    ).invokeMethod("openSettings", arguments: nil)
  }
}
