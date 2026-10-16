import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1440, height: 900))
    self.minSize = NSSize(width: 1100, height: 740)
    self.title = "CIDR Atlas"
    self.center()
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
