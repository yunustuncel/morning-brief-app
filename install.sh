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

class AckHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let date = body["date"] as? String,
              let id = body["id"] as? String,
              let checked = body["checked"] as? Bool else { return }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/MorningBrief/acks-\(date).json")

        var acks: [String: Bool] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] {
            acks = existing
        }
        if checked { acks[id] = true } else { acks.removeValue(forKey: id) }
        if let data = try? JSONSerialization.data(withJSONObject: acks) {
            try? data.write(to: url)
        }
    }
}

class ItemsHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let date = body["date"] as? String,
              let items = body["items"] as? [[String: String]] else { return }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/MorningBrief/items-\(date).json")
        if let data = try? JSONSerialization.data(withJSONObject: items) {
            try? data.write(to: url)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let ackHandler = AckHandler()
    let itemsHandler = ItemsHandler()

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
        cfg.userContentController.add(ackHandler, name: "acks")
        cfg.userContentController.add(itemsHandler, name: "items")

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
        let ackJS = #"""
        (function() {
            if (!document.getElementById('mb-ack-override')) {
                var s = document.createElement('style');
                s.id = 'mb-ack-override';
                s.textContent = '.item-ack{width:auto!important;padding:4px 12px!important}';
                document.head.appendChild(s);
            }
            var today = new Date().toISOString().slice(0, 10);
            var lsKey = 'morning-brief-acks-' + today;
            var saved = JSON.parse(localStorage.getItem(lsKey) || '{}');

            document.querySelectorAll('.ack-cb').forEach(function(cb) {
                if (saved[cb.id]) { cb.checked = true; cb.disabled = true; }
                cb.addEventListener('change', function() {
                    if (!this.checked) return;
                    this.disabled = true;
                    var state = JSON.parse(localStorage.getItem(lsKey) || '{}');
                    state[this.id] = true;
                    localStorage.setItem(lsKey, JSON.stringify(state));
                    window.webkit.messageHandlers.acks.postMessage({
                        date: today, id: this.id, checked: true
                    });
                });
            });

            var items = [];
            document.querySelectorAll('.ack-cb').forEach(function(cb) {
                var li = cb.closest('li');
                var titleEl = li && li.querySelector('.item-title');
                var sentenceEl = li && li.querySelector('.item-sentence');
                items.push({
                    id: cb.id,
                    title: titleEl ? titleEl.textContent.trim() : '',
                    sentence: sentenceEl ? sentenceEl.textContent.trim() : ''
                });
            });
            window.webkit.messageHandlers.items.postMessage({ date: today, items: items });
        })();
        """#

        let todoJS = #"""
        (function() {
            var TODOS_KEY = 'morning-brief-todos';
            var today = new Date().toISOString().slice(0, 10);

            function loadTodos() {
                try { return JSON.parse(localStorage.getItem(TODOS_KEY) || '[]'); }
                catch(e) { return []; }
            }

            function saveTodos(todos) {
                localStorage.setItem(TODOS_KEY, JSON.stringify(todos));
            }

            function genId() {
                return 'todo-' + Date.now() + '-' + Math.random().toString(36).slice(2, 7);
            }

            function render() {
                var list = document.getElementById('mb-todo-list');
                if (!list) return;
                list.innerHTML = '';
                var empty = document.getElementById('mb-todo-empty');
                var visible = loadTodos().filter(function(t) { return !t.done || t.date === today; });
                if (empty) empty.style.display = visible.length === 0 ? 'block' : 'none';
                var n = 1;
                loadTodos().forEach(function(todo) {
                    if (todo.done && todo.date !== today) return;
                    var li = document.createElement('li');
                    li.className = 'mb-todo-item' + (todo.done ? ' mb-done' : '');

                    var numSpan = document.createElement('span');
                    numSpan.className = 'mb-todo-num';
                    numSpan.textContent = n++;
                    li.appendChild(numSpan);

                    var textSpan = document.createElement('span');
                    textSpan.className = 'mb-todo-text';
                    textSpan.textContent = todo.text;
                    li.appendChild(textSpan);

                    if (!todo.done) {
                        var doneBtn = document.createElement('button');
                        doneBtn.className = 'mb-btn mb-btn-done';
                        doneBtn.textContent = 'Mark as done';
                        doneBtn.onclick = (function(id) { return function() {
                            var ts = loadTodos();
                            ts.forEach(function(t) { if (t.id === id) t.done = true; });
                            saveTodos(ts); render();
                        }; })(todo.id);
                        li.appendChild(doneBtn);
                    }

                    var removeBtn = document.createElement('button');
                    removeBtn.className = 'mb-btn mb-btn-remove';
                    removeBtn.textContent = 'Remove';
                    removeBtn.onclick = (function(id) { return function() {
                        saveTodos(loadTodos().filter(function(t) { return t.id !== id; }));
                        render();
                    }; })(todo.id);
                    li.appendChild(removeBtn);

                    list.appendChild(li);
                });
            }

            if (!document.getElementById('mb-todo-styles')) {
                var st = document.createElement('style');
                st.id = 'mb-todo-styles';
                st.textContent =
                    '#mb-todo-section .mb-todo-row{display:flex;gap:10px;margin-top:14px;margin-bottom:18px}' +
                    '#mb-todo-section .mb-todo-input{flex:1;background:#272729;border:1px solid #3A3A38;border-radius:6px;padding:6px 12px;color:#E5E4DC;font-size:13px;font-family:-apple-system,sans-serif;outline:none}' +
                    '#mb-todo-section .mb-todo-input::placeholder{color:#555550}' +
                    '#mb-todo-section .mb-todo-input:focus{border-color:#555550}' +
                    '#mb-todo-section .mb-add-btn{flex-shrink:0;padding:4px 12px;background:#fff;border:1px solid #C8C7BE;border-radius:6px;color:#17171A;font-family:-apple-system,sans-serif;cursor:pointer;box-sizing:border-box;-webkit-appearance:none;appearance:none}' +
                    '#mb-todo-section .mb-add-btn:hover{background:#f0f0ee;border-color:#8A8A82}' +
                    '#mb-todo-section #mb-todo-list{list-style:none;display:flex;flex-direction:column;gap:14px}' +
                    '#mb-todo-section .mb-todo-empty{font-size:12px;color:#555550;margin-top:6px}' +
                    '#mb-todo-section .mb-todo-item{display:flex;align-items:flex-start;gap:12px}' +
                    '#mb-todo-section .mb-todo-num{font-size:11px;color:#555550;min-width:16px;padding-top:3px;flex-shrink:0}' +
                    '#mb-todo-section .mb-todo-text{flex:1;font-size:13px;color:#E5E4DC;line-height:1.5;padding-top:2px}' +
                    '#mb-todo-section .mb-done .mb-todo-text{color:#555550;text-decoration:line-through}' +
                    '#mb-todo-section .mb-btn{flex-shrink:0;padding:4px 12px;text-align:center;border-radius:6px;font-family:-apple-system,sans-serif;cursor:pointer;box-sizing:border-box;-webkit-appearance:none;appearance:none}' +
                    '#mb-todo-section .mb-btn-done{background:#2D7A4F;border:1px solid #2D7A4F;color:#fff}' +
                    '#mb-todo-section .mb-btn-done:hover{background:#256640;border-color:#256640}' +
                    '#mb-todo-section .mb-btn-remove{background:transparent;border:1px solid #555550;color:#8A8A82}' +
                    '#mb-todo-section .mb-btn-remove:hover{border-color:#8A8A82;color:#E5E4DC}';
                document.head.appendChild(st);
            }

            if (!document.getElementById('mb-todo-section')) {
                var section = document.createElement('div');
                section.className = 'section';
                section.id = 'mb-todo-section';

                var heading = document.createElement('div');
                heading.className = 'section-heading';
                heading.textContent = "Today's tasks";
                section.appendChild(heading);

                var row = document.createElement('div');
                row.className = 'mb-todo-row';

                var input = document.createElement('input');
                input.type = 'text';
                input.className = 'mb-todo-input';
                input.placeholder = 'Add a task...';
                row.appendChild(input);

                var addBtn = document.createElement('button');
                addBtn.className = 'mb-add-btn';
                addBtn.textContent = 'Add';
                row.appendChild(addBtn);
                section.appendChild(row);

                var emptyMsg = document.createElement('p');
                emptyMsg.className = 'mb-todo-empty';
                emptyMsg.id = 'mb-todo-empty';
                emptyMsg.textContent = 'No tasks yet.';
                section.appendChild(emptyMsg);

                var list = document.createElement('ul');
                list.id = 'mb-todo-list';
                section.appendChild(list);

                function addTodo() {
                    var text = input.value.trim();
                    if (!text) return;
                    var ts = loadTodos();
                    ts.push({ id: genId(), text: text, done: false, date: today });
                    saveTodos(ts);
                    input.value = '';
                    render();
                }
                addBtn.onclick = addTodo;
                input.addEventListener('keydown', function(e) { if (e.key === 'Enter') addTodo(); });

                var bottomInner = document.querySelector('.band-bottom .inner');
                if (bottomInner) {
                    bottomInner.insertBefore(section, bottomInner.firstChild);
                }
            }

            render();
        })();
        """#

        webView.evaluateJavaScript(ackJS, completionHandler: nil)
        webView.evaluateJavaScript(todoJS, completionHandler: nil)
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
