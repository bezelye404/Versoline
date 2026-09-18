import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {

    // Shared ephemeral data store for Reader Mode to prevent spawning multiple isolated sessions
    static let sharedEphemeralDataStore = WKWebsiteDataStore.nonPersistent()

    @MainActor
    static func flushMemoryCache() {
        let types = Set([WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache])
        sharedEphemeralDataStore.removeData(
            ofTypes: types,
            modifiedSince: .distantPast,
            completionHandler: {}
        )
        WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: .distantPast,
            completionHandler: {}
        )
    }

    let html: String?
    let url: URL?
    let fontSize: Int
    var theme: ReaderTheme = .system
    var fontFamily: ReaderFontFamily = .system
    var lineHeight: ReaderLineHeight = .normal
    var isContentBlockerEnabled: Bool = false
    var isBionicReadingEnabled: Bool = false

    init(
        html: String,
        fontSize: Int = 16,
        theme: ReaderTheme = .system,
        fontFamily: ReaderFontFamily = .system,
        lineHeight: ReaderLineHeight = .normal,
        isBionicReadingEnabled: Bool = false
    ) {
        self.html = html
        self.url = nil
        self.fontSize = fontSize
        self.theme = theme
        self.fontFamily = fontFamily
        self.lineHeight = lineHeight
        self.isContentBlockerEnabled = false
        self.isBionicReadingEnabled = isBionicReadingEnabled
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
        self.isBionicReadingEnabled = false
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        // For local Reader Mode HTML, disable JavaScript to prevent spinning up the JavaScriptCore JIT/VM heap (-25MB RAM)
        if html != nil {
            config.defaultWebpagePreferences.allowsContentJavaScript = false
            config.websiteDataStore = Self.sharedEphemeralDataStore
        } else {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        // Attach Content Blocker ONLY for external live web URLs when enabled
        if url != nil && isContentBlockerEnabled,
           let ruleList = ContentBlockerService.shared.ruleList {
            config.userContentController.add(ruleList)
        }

        // Neutralize browser-level popups, dialogs, web push prompts, and scroll-locks
        if url != nil {
            let popupNeutralizerSource = """
            (function() {
                try {
                    window.open = function() { return null; };
                    window.alert = function() {};
                    window.confirm = function() { return false; };
                    window.prompt = function() { return null; };
                    if (window.Notification) {
                        window.Notification.requestPermission = function() { return Promise.resolve('denied'); };
                        window.Notification.permission = 'denied';
                    }
                    var unlockScroll = function() {
                        if (document.documentElement) {
                            document.documentElement.style.setProperty('overflow', 'auto', 'important');
                        }
                        if (document.body) {
                            document.body.style.setProperty('overflow', 'auto', 'important');
                        }
                    };
                    if (document.readyState === 'loading') {
                        document.addEventListener('DOMContentLoaded', unlockScroll);
                    } else {
                        unlockScroll();
                    }
                } catch(e) {}
            })();
            """
            let popupNeutralizerScript = WKUserScript(
                source: popupNeutralizerSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(popupNeutralizerScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        applyBackgroundColor(to: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isHTMLMode = (html != nil)
        applyBackgroundColor(to: webView)

        if let html = html {
            let styleChanged = coordinator.lastFontSize != fontSize ||
                               coordinator.lastTheme != theme ||
                               coordinator.lastFontFamily != fontFamily ||
                               coordinator.lastLineHeight != lineHeight ||
                               coordinator.lastBionicReading != isBionicReadingEnabled

            if coordinator.lastLoadedHTML != html || styleChanged {
                if coordinator.lastLoadedHTML != nil && coordinator.lastLoadedHTML != html {
                    Self.flushMemoryCache()
                }
                coordinator.lastLoadedHTML = html
                coordinator.lastFontSize = fontSize
                coordinator.lastTheme = theme
                coordinator.lastFontFamily = fontFamily
                coordinator.lastLineHeight = lineHeight
                coordinator.lastBionicReading = isBionicReadingEnabled
                coordinator.lastLoadedURL = nil
                coordinator.lastContentBlockerEnabled = nil
                let processedContent = prepareHTMLContent(html)
                let styledHTML = wrapInTemplate(processedContent)
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

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        // Load about:blank so the WebContent process immediately purges DOM, render layers, and decoded image memory
        if let blankURL = URL(string: "about:blank") {
            webView.load(URLRequest(url: blankURL))
        }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeAllContentRuleLists()
        coordinator.lastLoadedHTML = nil
        coordinator.lastLoadedURL = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isHTMLMode: html != nil)
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

    private func prepareHTMLContent(_ raw: String) -> String {
        var content = NativeCodeHighlighter.highlight(raw)
        if isBionicReadingEnabled {
            content = BionicReadingFormatter.format(content)
        }
        return content
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
                padding: 0 24px;
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
            img {
                max-width: 100%;
                height: auto;
                border-radius: 8px;
                margin: 12px 0;
                content-visibility: auto;
            }
            
            /* Native Code & Syntax Highlighting */
            pre, code {
                font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
            }
            code {
                font-size: 0.9em;
                background: rgba(128, 128, 128, 0.12);
                border-radius: 4px;
                padding: 2px 5px;
            }
            pre {
                background: rgba(128, 128, 128, 0.08);
                border: 1px solid rgba(128, 128, 128, 0.15);
                border-radius: 8px;
                padding: 12px 16px;
                overflow-x: auto;
                font-size: 13px;
                line-height: 1.55;
            }
            pre code {
                background: transparent;
                padding: 0;
                font-size: inherit;
            }
            .tok-kw { color: #cf222e; font-weight: 600; }
            .tok-str { color: #0a3069; }
            .tok-com { color: #6e7781; font-style: italic; }
            .tok-num { color: #0550ae; }
            .tok-typ { color: #953800; font-weight: 600; }
            @media (prefers-color-scheme: dark) {
                .tok-kw { color: #ff7b72; font-weight: 600; }
                .tok-str { color: #a5d6ff; }
                .tok-com { color: #8b949e; font-style: italic; }
                .tok-num { color: #79c0ff; }
                .tok-typ { color: #ffa657; font-weight: 600; }
            }

            /* Bionic Reading Highlighting */
            b.bionic {
                font-weight: 700;
                opacity: 0.96;
            }

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

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var isHTMLMode: Bool
        var lastLoadedHTML: String?
        var lastLoadedURL: URL?
        var lastFontSize: Int?
        var lastTheme: ReaderTheme?
        var lastFontFamily: ReaderFontFamily?
        var lastLineHeight: ReaderLineHeight?
        var lastContentBlockerEnabled: Bool?
        var lastBionicReading: Bool?

        init(isHTMLMode: Bool = false) {
            self.isHTMLMode = isHTMLMode
        }

        // 1. Block popup window creation (window.open, target=_blank auxiliary windows)
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // If the user deliberately clicked a target="_blank" link inside the browser, keep reading in the same view
            if !isHTMLMode && navigationAction.navigationType == .linkActivated {
                webView.load(navigationAction.request)
            }
            // Always return nil: strictly prevents auxiliary popup webview windows from spawning
            return nil
        }

        // 2. Decide navigation policy (contain browsing, eliminate click-trap popups)
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if isHTMLMode {
                // Reader Mode: Clicking external article links opens in user's default browser
                if navigationAction.navigationType == .linkActivated,
                   let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            } else {
                // In-App Web Browser Mode:
                if navigationAction.targetFrame == nil {
                    // Website is attempting target="_blank" or script popup
                    if navigationAction.navigationType == .linkActivated {
                        // Keep user-initiated links inside the in-app browser
                        webView.load(navigationAction.request)
                    }
                    // Cancel auxiliary window/popup creation
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        // 3. Suppress JavaScript alert popups
        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable () -> Void
        ) {
            completionHandler()
        }

        // 4. Suppress JavaScript confirm dialog popups
        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
        ) {
            completionHandler(false)
        }

        // 5. Suppress JavaScript text input prompt popups
        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable (String?) -> Void
        ) {
            completionHandler(nil)
        }

        // 6. Handle web content process termination gracefully (e.g. under system memory pressure)
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            AppLogger.shared.log("WKWebView WebContent process terminated, restoring content...", level: .warning, category: .storage)
            if let lastHTML = lastLoadedHTML {
                webView.loadHTMLString(lastHTML, baseURL: nil)
            } else if let lastURL = lastLoadedURL {
                webView.load(URLRequest(url: lastURL))
            }
        }
    }
}

// MARK: - Native Lightweight Code Syntax Highlighter (Zero External JS / Minimal RAM)

enum NativeCodeHighlighter {
    private static let preBlockRegex = try? NSRegularExpression(
        pattern: #"(<pre[^>]*>)([\s\S]*?)(</pre>)"#,
        options: [.caseInsensitive]
    )

    private static let keywordRegex = try? NSRegularExpression(
        pattern: #"\b(func|let|var|def|class|struct|enum|import|return|if|else|guard|switch|case|break|continue|for|while|in|try|catch|throw|async|await|public|private|static|const|function|interface|type|nil|null|true|false)\b"#,
        options: []
    )

    private static let stringRegex = try? NSRegularExpression(
        pattern: #"("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')"#,
        options: []
    )

    private static let commentRegex = try? NSRegularExpression(
        pattern: #"(//[^\n\r]*|/\*[\s\S]*?\*/|#[^\n\r]*)"#,
        options: []
    )

    private static let numberRegex = try? NSRegularExpression(
        pattern: #"\b\d+(?:\.\d+)?\b"#,
        options: []
    )

    static func highlight(_ html: String) -> String {
        guard let preRegex = preBlockRegex, html.contains("<pre") else { return html }

        let nsString = html as NSString
        let matches = preRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return html }

        var result = ""
        result.reserveCapacity(html.count + 500)
        var lastIndex = 0

        for match in matches {
            let preRange = match.range
            let leadingRange = NSRange(location: lastIndex, length: preRange.location - lastIndex)
            result += nsString.substring(with: leadingRange)

            let openTag = nsString.substring(with: match.range(at: 1))
            let innerCode = nsString.substring(with: match.range(at: 2))
            let closeTag = nsString.substring(with: match.range(at: 3))

            let styledInner = highlightCodeContent(innerCode)
            result += openTag + styledInner + closeTag
            lastIndex = preRange.location + preRange.length
        }

        if lastIndex < nsString.length {
            result += nsString.substring(from: lastIndex)
        }

        return result
    }

    private static func highlightCodeContent(_ code: String) -> String {
        // Simple token replacement that protects strings and comments
        var output = code

        // Strings
        if let sRegex = stringRegex {
            output = sRegex.stringByReplacingMatches(
                in: output,
                options: [],
                range: NSRange(location: 0, length: (output as NSString).length),
                withTemplate: #"<span class="tok-str">$1</span>"#
            )
        }

        // Keywords
        if let kwRegex = keywordRegex {
            output = kwRegex.stringByReplacingMatches(
                in: output,
                options: [],
                range: NSRange(location: 0, length: (output as NSString).length),
                withTemplate: #"<span class="tok-kw">$1</span>"#
            )
        }

        return output
    }
}

// MARK: - Native Bionic Reading Engine (Word Fixation Highlighting)

enum BionicReadingFormatter {
    private static let tagRegex = try? NSRegularExpression(
        pattern: #"(<[^>]+>|&[a-zA-Z0-9#]+;)"#,
        options: []
    )

    private static let skipTagsRegex = try? NSRegularExpression(
        pattern: #"(?i)<(pre|code|script|style|a|svg)[\s>][\s\S]*?</\1>"#,
        options: []
    )

    static func format(_ html: String) -> String {
        guard !html.isEmpty else { return html }

        // Find skip blocks (pre, code, a, script, style) to protect their text
        var protectedRanges: [NSRange] = []
        if let skipRegex = skipTagsRegex {
            let ns = html as NSString
            let matches = skipRegex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
            for m in matches {
                protectedRanges.append(m.range)
            }
        }

        let nsString = html as NSString
        let fullLength = nsString.length

        // Tokenize between HTML tags & entities and raw text
        guard let tRegex = tagRegex else { return html }
        let tagMatches = tRegex.matches(in: html, options: [], range: NSRange(location: 0, length: fullLength))

        var result = ""
        result.reserveCapacity(Int(Double(html.count) * 1.2))

        var currentIndex = 0

        for match in tagMatches {
            let tagRange = match.range
            if tagRange.location > currentIndex {
                // Text chunk before this tag
                let textRange = NSRange(location: currentIndex, length: tagRange.location - currentIndex)
                let textChunk = nsString.substring(with: textRange)

                // Check if this text chunk falls within any protected range
                let isProtected = protectedRanges.contains { protected in
                    NSIntersectionRange(protected, textRange).length > 0
                }

                if isProtected {
                    result += textChunk
                } else {
                    result += bionicTransformText(textChunk)
                }
            }

            // Append the tag/entity untouched
            result += nsString.substring(with: tagRange)
            currentIndex = tagRange.location + tagRange.length
        }

        if currentIndex < fullLength {
            let remainingRange = NSRange(location: currentIndex, length: fullLength - currentIndex)
            let remainingText = nsString.substring(with: remainingRange)
            let isProtected = protectedRanges.contains { protected in
                NSIntersectionRange(protected, remainingRange).length > 0
            }
            if isProtected {
                result += remainingText
            } else {
                result += bionicTransformText(remainingText)
            }
        }

        return result
    }

    private static func bionicTransformText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var output = ""
        output.reserveCapacity(text.count + 50)

        var currentWord = ""

        func flushWord() {
            guard !currentWord.isEmpty else { return }
            let len = currentWord.count
            if len <= 1 {
                output += currentWord
            } else {
                let boldLength: Int
                switch len {
                case 2...3: boldLength = 1
                case 4...6: boldLength = 2
                case 7...9: boldLength = 3
                default:    boldLength = max(3, len / 2)
                }

                let boldPart = currentWord.prefix(boldLength)
                let restPart = currentWord.dropFirst(boldLength)
                output += "<b class=\"bionic\">\(boldPart)</b>\(restPart)"
            }
            currentWord.removeAll(keepingCapacity: true)
        }

        for char in text {
            if char.isLetter || char.isNumber {
                currentWord.append(char)
            } else {
                flushWord()
                output.append(char)
            }
        }
        flushWord()

        return output
    }
}
