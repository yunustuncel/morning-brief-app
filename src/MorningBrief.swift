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
