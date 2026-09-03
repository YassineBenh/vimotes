import AppKit

@main
@MainActor
enum ViMotesApplication {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()

    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()

    withExtendedLifetime(delegate) {}
  }
}
