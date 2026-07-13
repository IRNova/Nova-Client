import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open as a compact, phone-style window so Nova shows its mobile layout. The
    // wide desktop side-rail only kicks in past ~760pt; a narrow default keeps
    // the familiar bottom-bar UI. Users can still resize larger for the rail.
    self.setContentSize(NSSize(width: 440, height: 860))
    self.minSize = NSSize(width: 380, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
