import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {

    let html: String?
    let url: URL?
    let fontSize: Int
    var theme: ReaderTheme = .system
    var fontFamily: ReaderFontFamily = .system
    var lineHeight: ReaderLineHeight = .normal
    var isContentBlockerEnabled: Bool = false

    init(
        html: String,
        fontSize: Int = 16,
        theme: ReaderTheme = .system,
        fontFamily: ReaderFontFamily = .system,
        lineHeight: ReaderLineHeight = .normal
    ) {
        self.html = html
        self.url = nil
        self.fontSize = fontSize
        self.theme = theme
        self.fontFamily = fontFamily
        self.lineHeight = lineHeight
        self.isContentBlockerEnabled = false
    }

    init(
        url: URL,
        fontSize: Int = 16,
        theme: ReaderTheme = .system,
        fontFamily: ReaderFontFamily = .system,
        lineHeight: ReaderLineHeight = .normal,
        isContentBlockerEnabled: Bool = true
    ) {
        self.html = nil
        self.url = url
        self.fontSize = fontSize
        self.theme = theme
        self.fontFamily = fontFamily
        self.lineHeight = lineHeight
        self.isContentBlockerEnabled = isContentBlockerEnabled
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Attach Content Blocker ONLY for external live web URLs when enabled
        if url != nil && isContentBlockerEnabled,
           let ruleList = ContentBlockerService.shared.ruleList {
            config.userContentController.add(ruleList)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        applyBackgroundColor(to: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        applyBackgroundColor(to: webView)

        if let html = html {
            let styleChanged = coordinator.lastFontSize != fontSize ||
                               coordinator.lastTheme != theme ||
                               coordinator.lastFontFamily != fontFamily ||
                               coordinator.lastLineHeight != lineHeight

            if coordinator.lastLoadedHTML != html || styleChanged {
                coordinator.lastLoadedHTML = html
                coordinator.lastFontSize = fontSize
                coordinator.lastTheme = theme
                coordinator.lastFontFamily = fontFamily
                coordinator.lastLineHeight = lineHeight
                coordinator.lastLoadedURL = nil
                coordinator.lastContentBlockerEnabled = nil
                let styledHTML = wrapInTemplate(html)
                webView.loadHTMLString(styledHTML, baseURL: nil)
            }
        } else if let url = url {
            let blockerStateChanged = coordinator.lastContentBlockerEnabled != isContentBlockerEnabled
            let urlChanged = coordinator.lastLoadedURL != url

            if blockerStateChanged && !urlChanged && coordinator.lastLoadedURL != nil {
                coordinator.lastContentBlockerEnabled = isContentBlockerEnabled
                webView.configuration.userContentController.removeAllContentRuleLists()
                if isContentBlockerEnabled, let ruleList = ContentBlockerService.shared.ruleList {
                    webView.configuration.userContentController.add(ruleList)
                }
                webView.reload()
            } else if urlChanged {
                coordinator.lastLoadedURL = url
                coordinator.lastLoadedHTML = nil
                coordinator.lastContentBlockerEnabled = isContentBlockerEnabled
                webView.configuration.userContentController.removeAllContentRuleLists()
                if isContentBlockerEnabled, let ruleList = ContentBlockerService.shared.ruleList {
                    webView.configuration.userContentController.add(ruleList)
                }
                let request = URLRequest(url: url)
                webView.load(request)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyBackgroundColor(to webView: WKWebView) {
        switch theme {
        case .system:
            webView.underPageBackgroundColor = .clear
        case .light:
            webView.underPageBackgroundColor = .white
        case .sepia:
            webView.underPageBackgroundColor = NSColor(red: 0.97, green: 0.95, blue: 0.89, alpha: 1.0)
        case .dark:
            webView.underPageBackgroundColor = NSColor(white: 0.11, alpha: 1.0)
        case .oled:
            webView.underPageBackgroundColor = .black
        }
    }

    private func wrapInTemplate(_ content: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            :root {
                color-scheme: \(theme == .system ? "light dark" : (theme == .dark || theme == .oled ? "dark" : "light"));
            }
            body {
                font-family: \(fontFamily.cssFontFamily);
                font-size: \(fontSize)px;
                line-height: \(lineHeight.rawValue);
                color: \(theme.textColorCSS);
                background-color: \(theme.backgroundColorCSS);
                padding: 0 8px;
                max-width: 800px;
                margin: 0 auto;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            @media (prefers-color-scheme: dark) {
                :root { --text-color: #e5e5e7; --link-color: #6cb4ee; }
            }
            @media (prefers-color-scheme: light) {
                :root { --text-color: #1d1d1f; --link-color: #0066cc; }
            }
            a { color: \(theme.linkColorCSS); text-decoration: none; }
            a:hover { text-decoration: underline; }
            img { max-width: 100%; height: auto; border-radius: 8px; margin: 12px 0; }
            pre, code {
                font-family: "SF Mono", Menlo, monospace;
                font-size: 13px;
                background: rgba(128, 128, 128, 0.12);
                border-radius: 6px;
                padding: 2px 6px;
            }
            pre { padding: 12px; overflow-x: auto; }
            blockquote {
                border-left: 3px solid rgba(128, 128, 128, 0.3);
                margin-left: 0;
                padding-left: 16px;
                color: rgba(128, 128, 128, 0.85);
            }
            h1, h2, h3, h4 { font-weight: 600; line-height: 1.3; }
            hr { border: none; border-top: 1px solid rgba(128, 128, 128, 0.2); margin: 20px 0; }
        </style>
        </head>
        <body>
        \(content)
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String?
        var lastLoadedURL: URL?
        var lastFontSize: Int?
        var lastTheme: ReaderTheme?
        var lastFontFamily: ReaderFontFamily?
        var lastLineHeight: ReaderLineHeight?
        var lastContentBlockerEnabled: Bool?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
