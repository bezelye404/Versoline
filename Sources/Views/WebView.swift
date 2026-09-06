import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {

    let html: String?
    let url: URL?

    init(html: String) {
        self.html = html
        self.url = nil
    }

    init(url: URL) {
        self.html = nil
        self.url = url
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let html = html {
            let styledHTML = wrapInTemplate(html)
            webView.loadHTMLString(styledHTML, baseURL: nil)
        } else if let url = url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
                color-scheme: light dark;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                font-size: 15px;
                line-height: 1.6;
                color: var(--text-color);
                background: transparent;
                padding: 0 4px;
                max-width: 100%;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            @media (prefers-color-scheme: dark) {
                :root { --text-color: #e5e5e7; --link-color: #6cb4ee; }
            }
            @media (prefers-color-scheme: light) {
                :root { --text-color: #1d1d1f; --link-color: #0066cc; }
            }
            a { color: var(--link-color); text-decoration: none; }
            a:hover { text-decoration: underline; }
            img { max-width: 100%; height: auto; border-radius: 8px; margin: 8px 0; }
            pre, code {
                font-family: "SF Mono", Menlo, monospace;
                font-size: 13px;
                background: rgba(128, 128, 128, 0.1);
                border-radius: 6px;
                padding: 2px 6px;
            }
            pre { padding: 12px; overflow-x: auto; }
            blockquote {
                border-left: 3px solid rgba(128, 128, 128, 0.3);
                margin-left: 0;
                padding-left: 16px;
                color: rgba(128, 128, 128, 0.8);
            }
            h1, h2, h3, h4 { font-weight: 600; }
            hr { border: none; border-top: 1px solid rgba(128, 128, 128, 0.2); margin: 16px 0; }
        </style>
        </head>
        <body>
        \(content)
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Open external links in the default browser
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
