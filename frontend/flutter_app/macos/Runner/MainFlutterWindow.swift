import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Open at iPhone size (390 x 844 points) so the phone layout can be checked on a Mac.
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 390, height: 844)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
