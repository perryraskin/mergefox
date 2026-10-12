import SwiftUI
import WebKit
import OSLog

struct MarkdownText: View {
    let text: String
    var compact = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 24
    @ScaledMetric private var fontSize = 17.0

    var body: some View {
        MarkdownWebView(text: text, baseURL: model.location?.host,
                        project: model.location?.project,
                        dark: colorScheme == .dark, fontSize: compact ? fontSize * 14 / 17 : fontSize, height: $height)
            .frame(maxWidth: .infinity).frame(height: height)
    }
}

// MR text is passed as a JavaScript argument, parsed locally, and sanitized before
// insertion. No GitLab credentials are given to this ephemeral web view.
struct MarkdownWebView: UIViewRepresentable {
    let text: String
    let baseURL: URL?
    var project: String? = nil
    let dark: Bool
    let fontSize: Double
    @Binding var height: CGFloat
    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "height")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.webView = view
        view.loadHTMLString(RichMarkdownDocument.html, baseURL: baseURL)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.openLink = { openURL($0) }
        context.coordinator.arguments = ["text": text, "dark": dark, "fontSize": fontSize,
                                          "base": baseURL?.absoluteString ?? "https://gitlab.com", "project": project ?? ""]
        context.coordinator.render()
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "height")
        view.stopLoading()
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        weak var webView: WKWebView?
        var ready = false
        var arguments: [String: Any] = [:]
        var lastArguments: NSDictionary?
        var openLink: ((URL) -> Void)?
        var mermaidLoading = false
        var mermaidLoaded = false
        init(height: Binding<CGFloat>) { self.height = height }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            render()
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            Logger(subsystem: "com.perryraskin.mergepocket", category: "Markdown").error("Markdown page failed: \(error.localizedDescription, privacy: .public)")
            #endif
        }
        func render() {
            guard ready, !arguments.isEmpty, lastArguments != arguments as NSDictionary else { return }
            if (arguments["text"] as? String)?.contains("mermaid") == true && !mermaidLoaded {
                guard !mermaidLoading else { return }
                mermaidLoading = true
                webView?.evaluateJavaScript(RichMarkdownDocument.script("mermaid")) { [weak self] _, _ in
                    self?.mermaidLoading = false
                    self?.mermaidLoaded = true
                    self?.render()
                }
                return
            }
            lastArguments = arguments as NSDictionary
            var renderArguments = arguments
            renderArguments["project"] = arguments["project"] ?? ""
            webView?.callAsyncJavaScript("return await window.renderMarkdown(text, dark, fontSize, base, project)", arguments: renderArguments,
                                       in: nil, in: .page, completionHandler: { result in
                #if DEBUG
                if case .failure(let error) = result { Logger(subsystem: "com.perryraskin.mergepocket", category: "Markdown").error("Markdown renderer failed: \(error.localizedDescription, privacy: .public)") }
                #endif
            })
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let number = message.body as? Double,
                  number.isFinite, number > 0, number < 1_000_000 else { return }
            let newHeight = CGFloat(ceil(number))
            if abs(height.wrappedValue - newHeight) > 0.5 { height.wrappedValue = newHeight }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    openLink?(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler((!ready && action.navigationType == .other) || action.request.url?.scheme == "about" ? .allow : .cancel)
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.navigationType == .linkActivated, let url = action.request.url,
               ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { openLink?(url) }
            return nil
        }
    }
}

enum RichMarkdownDocument {
    static func script(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return source.replacingOccurrences(of: "</script", with: "<\\/script")
    }
    static var html: String {
        let nonce = UUID().uuidString
        func script(_ name: String) -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                #if DEBUG
                Logger(subsystem: "com.perryraskin.mergepocket", category: "Markdown").error("Missing renderer resource: \(name, privacy: .public)")
                #endif
                return ""
            }
            return source.replacingOccurrences(of: "</script", with: "<\\/script")
        }
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="referrer" content="no-referrer">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'nonce-\(nonce)'; img-src https: data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
        <style nonce="\(nonce)">
        :root { color-scheme: light; --muted:#f4f0fc; --border:#dcdbd9; --link:#2566b5; --text:#18171d; }
        :root.dark { color-scheme:dark; --muted:#3a383d; --border:#4d4b4e; --link:#9dc8f2; --text:#ecebea; }
        * { box-sizing:border-box; } html,body { margin:0; padding:0; background:transparent; }
        body { font:17px -apple-system, sans-serif; line-height:1.45; color:var(--text); }
        #content { display:flow-root; width:100%; overflow-wrap:anywhere; }
        #content > :first-child { margin-top:0; } #content > :last-child { margin-bottom:0; }
        p,ul,ol,pre,blockquote,details,table { margin:0 0 12px; }
        h1,h2,h3,h4 { line-height:1.25; margin:20px 0 10px; } h1 { font-size:1.5em; } h2 { font-size:1.3em; } h3 { font-size:1.15em; }
        a { color:var(--link); text-decoration:none; } img { max-width:100%; height:auto; vertical-align:middle; }
        a.mention { font-weight:600; }
        .idiff.deletion { background:#fce8e6; color:#a02020; text-decoration:line-through; }
        .idiff.addition { background:#ddf4e4; color:#176b39; }
        :root.dark .idiff.deletion { background:#522d30; color:#ffb4b4; }
        :root.dark .idiff.addition { background:#203e2c; color:#a4e5b8; }
        ul,ol { padding-left:24px; } li { margin:5px 0; }
        code { font:0.85em ui-monospace,monospace; background:var(--muted); border-radius:4px; padding:2px 4px; }
        pre { overflow-x:auto; padding:12px; border-radius:10px; background:var(--muted); white-space:pre; }
        pre code { padding:0; background:none; font-size:0.85em; }
        blockquote { border-left:3px solid var(--border); padding-left:12px; opacity:0.8; }
        details { border:1px solid var(--border); border-radius:8px; padding:10px; } summary { cursor:pointer; font-weight:600; } details[open] summary { margin-bottom:10px; }
        table { display:block; overflow-x:auto; border-collapse:collapse; max-width:100%; } th,td { border:1px solid var(--border); padding:7px; }
        hr { border:0; border-top:1px solid var(--border); margin:16px 0; }
        input[type=checkbox] { pointer-events:none; }
        .mermaid-diagram { overflow-x:auto; padding:12px; border:1px solid var(--border); border-radius:10px; margin-bottom:12px; }
        .mermaid-diagram svg { display:block; max-width:none !important; }
        </style></head><body><main id="content"></main>
        <script nonce="\(nonce)">\(script("marked"))</script>
        <script nonce="\(nonce)">\(script("dompurify"))</script>
        <script nonce="\(nonce)">
        const content = document.getElementById('content');
        function reportHeight() { window.webkit?.messageHandlers?.height?.postMessage(content.getBoundingClientRect().height); }
        function linkMentions(base) {
          const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
          const nodes = [];
          while (walker.nextNode()) {
            if (!walker.currentNode.parentElement.closest('a,code,pre,kbd,samp')) nodes.push(walker.currentNode);
          }
          for (const node of nodes) {
            const pattern = /(^|[^A-Za-z0-9_@/])@([A-Za-z0-9_](?:[A-Za-z0-9_.-]*[A-Za-z0-9_])?)/g;
            const fragment = document.createDocumentFragment();
            let end = 0, match;
            while ((match = pattern.exec(node.data)) !== null) {
              const start = match.index + match[1].length;
              fragment.append(document.createTextNode(node.data.slice(end, start)));
              const link = document.createElement('a');
              link.className = 'mention';
              link.textContent = '@' + match[2];
              link.href = new URL('/' + encodeURIComponent(match[2]), base).href;
              fragment.append(link);
              end = pattern.lastIndex;
            }
            if (end) {
              fragment.append(document.createTextNode(node.data.slice(end)));
              node.replaceWith(fragment);
            }
          }
          content.querySelectorAll('a').forEach(link => {
            if (/^@[A-Za-z0-9_]/.test(link.textContent)) link.classList.add('mention');
          });
        }
        function linkCommits(base, project) {
          if (!project) return;
          const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT), nodes = [];
          while (walker.nextNode()) if (!walker.currentNode.parentElement.closest('a,code,pre,kbd,samp')) nodes.push(walker.currentNode);
          for (const node of nodes) {
            const pattern = /(^|[^A-Za-z0-9_])([a-fA-F0-9]{7,40})(?![A-Za-z0-9_])/g;
            const fragment = document.createDocumentFragment();
            let end = 0, match;
            while ((match = pattern.exec(node.data)) !== null) {
              if (!/[0-9]/.test(match[2]) || !/[a-fA-F]/.test(match[2])) continue;
              const start = match.index + match[1].length;
              fragment.append(document.createTextNode(node.data.slice(end, start)));
              const link = document.createElement('a');
              link.textContent = match[2];
              link.href = new URL('/' + project.split('/').map(encodeURIComponent).join('/') + '/-/commit/' + match[2], base).href;
              fragment.append(link);
              end = pattern.lastIndex;
            }
            if (end) { fragment.append(document.createTextNode(node.data.slice(end))); node.replaceWith(fragment); }
          }
        }
        let renderGeneration = 0;
        window.renderMarkdown = async (text, dark, fontSize, base, project = '') => {
          const generation = ++renderGeneration;
          document.documentElement.classList.toggle('dark', dark);
          document.body.style.fontSize = fontSize + 'px';
          if (typeof marked === 'undefined' || typeof DOMPurify === 'undefined') { content.textContent = text; reportHeight(); return; }
          content.innerHTML = DOMPurify.sanitize(marked.parse(text, {gfm:true}), {
            FORBID_TAGS:['script','style','iframe','object','embed','form','video','audio'],
            FORBID_ATTR:['style','srcset','id','name'], USE_PROFILES:{html:true}
          });
          linkMentions(base);
          linkCommits(base, project);
          content.querySelectorAll('a[href],img[src]').forEach(el => {
            const attr = el.tagName === 'A' ? 'href' : 'src';
            try {
              const url = new URL(el.getAttribute(attr), base + '/');
              const allowed = attr === 'href' ? ['https:','http:','mailto:'] : ['https:'];
              if (!allowed.includes(url.protocol)) el.removeAttribute(attr);
              else el.setAttribute(attr, url.href);
            } catch { el.removeAttribute(attr); }
          });
          requestAnimationFrame(reportHeight);
          const diagrams = [...content.querySelectorAll('pre > code.language-mermaid')];
          if (diagrams.length && typeof mermaid !== 'undefined') {
            mermaid.initialize({startOnLoad:false, securityLevel:'strict', theme:dark ? 'dark' : 'neutral',
              htmlLabels:false, flowchart:{htmlLabels:false}, suppressErrorRendering:true,
              secure:['secure','securityLevel','startOnLoad','htmlLabels','flowchart','themeCSS','maxTextSize','maxEdges'],
              maxTextSize:50000, maxEdges:500});
            for (let i = 0; i < diagrams.length; i++) {
              const code = diagrams[i], source = code.textContent;
              try {
                const {svg} = await mermaid.render('diagram-' + generation + '-' + i, source);
                if (generation !== renderGeneration) return;
                const container = document.createElement('div');
                container.className = 'mermaid-diagram';
                container.setAttribute('role', 'img'); container.setAttribute('aria-label', 'Mermaid diagram');
                container.innerHTML = DOMPurify.sanitize(svg, {USE_PROFILES:{svg:true,svgFilters:true},
                  ADD_TAGS:['style'], FORBID_TAGS:['foreignObject','script'], FORBID_ATTR:['href','xlink:href']});
                container.querySelectorAll('style').forEach(style => style.setAttribute('nonce', '\(nonce)'));
                const image = container.querySelector('svg');
                if (image) {
                  const bounds = image.viewBox.baseVal;
                  image.setAttribute('width', Math.max(280, bounds.width)); image.setAttribute('height', bounds.height);
                }
                code.parentElement.replaceWith(container);
              } catch {
                if (generation !== renderGeneration) return;
                const warning = document.createElement('p'); warning.textContent = 'Couldn’t render this diagram. Source shown below.';
                code.parentElement.before(warning);
              }
              reportHeight();
            }
          }
        };
        new ResizeObserver(reportHeight).observe(content);
        document.addEventListener('toggle', reportHeight, true);
        document.addEventListener('load', reportHeight, true);
        </script></body></html>
        """
    }
}
