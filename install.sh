#!/usr/bin/env bash
# Morning Brief — install script
# Compiles the macOS app and installs it to ~/Applications.
# Prerequisites: macOS 12+, Xcode Command Line Tools (xcode-select --install)
set -euo pipefail

APP_DIR="$HOME/Applications/Morning Brief.app"
BRIEF_DIR="$HOME/Documents/MorningBrief"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP" /tmp/MorningBrief.iconset 2>/dev/null || true' EXIT

echo "→ Building Morning Brief.app …"

# ── App source ────────────────────────────────────────────────────────────────
cat > "$TMP/MorningBrief.swift" << 'SWIFT'
import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Morning Brief"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.102, alpha: 1)
        window.center()
        window.setFrameAutosaveName("MorningBriefWindow")

        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: window.contentView!.bounds, configuration: cfg)
        webView.autoresizingMask = [.width, .height]
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView!.addSubview(webView)

        loadBrief()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func loadBrief() {
        let briefURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/MorningBrief/today.html")
        if FileManager.default.fileExists(atPath: briefURL.path) {
            webView.loadFileURL(briefURL, allowingReadAccessTo: briefURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(placeholder(), baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (function() {
            var today = new Date().toISOString().slice(0, 10);
            var key = 'morning-brief-acks-' + today;
            var saved = JSON.parse(localStorage.getItem(key) || '{}');
            document.querySelectorAll('.ack-cb').forEach(function(cb) {
                if (saved[cb.id]) cb.checked = true;
                cb.addEventListener('change', function() {
                    var state = JSON.parse(localStorage.getItem(key) || '{}');
                    state[this.id] = this.checked;
                    localStorage.setItem(key, JSON.stringify(state));
                });
            });
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func placeholder() -> String {
        return """
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{background:#17171A;color:#8A8A82;font-family:-apple-system,sans-serif;
             display:flex;flex-direction:column;align-items:center;justify-content:center;
             height:100vh;gap:10px}
        h2{color:#E5E4DC;font-weight:500;font-size:20px}
        p{font-size:14px}
        </style></head>
        <body>
          <h2>No brief for today yet</h2>
          <p>Generated automatically at 8 AM when Claude Code is running.</p>
        </body></html>
        """
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
SWIFT

# ── Icon source ───────────────────────────────────────────────────────────────
cat > "$TMP/MakeIcon.swift" << 'SWIFT'
import Cocoa

func makeIcon(_ size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let bg = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.102, alpha: 1)
    bg.setFill()
    let r = s * 0.22
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: r, yRadius: r).fill()

    let clay = NSColor(srgbRed: 0.831, green: 0.443, blue: 0.290, alpha: 1)
    clay.setFill()
    clay.setStroke()

    let cx = s / 2, cy = s * 0.52
    let sr = s * 0.185
    let lw = max(1.5, s * 0.028)

    NSBezierPath(ovalIn: NSRect(x: cx - sr, y: cy - sr, width: sr * 2, height: sr * 2)).fill()

    for i in 0..<8 {
        let angle = Double(i) * .pi / 4 + .pi / 8
        let ri = sr * 1.38, ro = sr * 1.78
        let x1 = cx + CGFloat(cos(angle)) * ri, y1 = cy + CGFloat(sin(angle)) * ri
        let x2 = cx + CGFloat(cos(angle)) * ro, y2 = cy + CGFloat(sin(angle)) * ro
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x1, y: y1))
        p.line(to: NSPoint(x: x2, y: y2))
        p.lineWidth = lw
        p.lineCapStyle = .round
        p.stroke()
    }

    let hy = cy - s * 0.16
    let h = NSBezierPath()
    h.move(to: NSPoint(x: s * 0.18, y: hy))
    h.line(to: NSPoint(x: s * 0.82, y: hy))
    h.lineWidth = lw * 0.85
    h.lineCapStyle = .round
    h.stroke()

    img.unlockFocus()
    return img
}

func savePNG(_ img: NSImage, to path: String) {
    guard let tiff = img.tiffRepresentation,
          let bm = NSBitmapImageRep(data: tiff),
          let png = bm.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let iconsetPath = "/tmp/MorningBrief.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16,"icon_16x16"), (32,"icon_16x16@2x"),
    (32,"icon_32x32"), (64,"icon_32x32@2x"),
    (128,"icon_128x128"), (256,"icon_128x128@2x"),
    (256,"icon_256x256"), (512,"icon_256x256@2x"),
    (512,"icon_512x512"), (1024,"icon_512x512@2x")
]

for (size, name) in specs {
    savePNG(makeIcon(size), to: "\(iconsetPath)/\(name).png")
}
SWIFT

# ── Compile ───────────────────────────────────────────────────────────────────
echo "  Compiling app binary (~60 s)…"
swiftc -framework Cocoa -framework WebKit -o "$TMP/MorningBrief" "$TMP/MorningBrief.swift"

echo "  Generating icon…"
swiftc -framework Cocoa -o "$TMP/MakeIcon" "$TMP/MakeIcon.swift"
"$TMP/MakeIcon"
iconutil -c icns /tmp/MorningBrief.iconset -o "$TMP/AppIcon.icns"

# ── Bundle ────────────────────────────────────────────────────────────────────
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Morning Brief</string>
  <key>CFBundleExecutable</key><string>MorningBrief</string>
  <key>CFBundleIdentifier</key><string>com.dynatrace.morningbrief</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$TMP/MorningBrief" "$APP_DIR/Contents/MacOS/MorningBrief"
cp "$TMP/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
mkdir -p "$BRIEF_DIR"

echo ""
echo "✓  Installed: $APP_DIR"
echo ""
echo "Next steps:"
echo "  1. Drag 'Morning Brief' from ~/Applications to your Dock"
echo "  2. First launch: right-click → Open  (one-time Gatekeeper bypass)"
echo "  3. Set up your daily brief — see README.md"
