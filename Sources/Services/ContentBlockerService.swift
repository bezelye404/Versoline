import Foundation
import WebKit

@Observable
@MainActor
final class ContentBlockerService {

    static let shared = ContentBlockerService()

    private let ruleListIdentifier = "EasyRSSContentBlockerRules-v4"
    private(set) var ruleList: WKContentRuleList?
    private(set) var isReady: Bool = false

    private init() {
        Task {
            await prepare()
        }
    }

    func prepare() async {
        if ruleList != nil { return }

        guard let store = WKContentRuleListStore.default() else {
            AppLogger.shared.log("WKContentRuleListStore is unavailable on this system.", level: .error, category: .system)
            return
        }

        // 1. Check if compiled rules already exist in store cache (instant load)
        if let cached = await lookupRuleList(store: store) {
            self.ruleList = cached
            self.isReady = true
            AppLogger.shared.log("Pre-compiled content blocker rules (v4) loaded from store cache.", level: .info, category: .system)
            return
        }

        // 2. Otherwise compile rule list asynchronously
        await compileRuleList(store: store)
    }

    private func lookupRuleList(store: WKContentRuleListStore) async -> WKContentRuleList? {
        await withCheckedContinuation { (continuation: CheckedContinuation<WKContentRuleList?, Never>) in
            store.lookUpContentRuleList(forIdentifier: ruleListIdentifier) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    private func compileRuleList(store: WKContentRuleListStore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.compileContentRuleList(
                forIdentifier: ruleListIdentifier,
                encodedContentRuleList: ContentBlockerRules.rulesJSON
            ) { [weak self] compiled, error in
                Task { @MainActor in
                    if let error = error {
                        AppLogger.shared.log("Failed to compile rules: \(error.localizedDescription)", level: .error, category: .system)
                    } else if let compiled = compiled {
                        self?.ruleList = compiled
                        self?.isReady = true
                        AppLogger.shared.log("Successfully compiled native WebKit content blocker rules (v4).", level: .info, category: .system)
                    }
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Curated Lightweight Content Blocking Rules

private enum ContentBlockerRules {

    static let rulesJSON: String = """
    [
      {
        "trigger": {
          "url-filter": ".*",
          "resource-type": ["popup"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*",
          "if-domain": [
            "*doubleclick.net",
            "*googlesyndication.com",
            "*googleadservices.com",
            "*google-analytics.com",
            "*googletagmanager.com",
            "*adnxs.com",
            "*taboola.com",
            "*outbrain.com",
            "*criteo.com",
            "*criteo.net",
            "*scorecardresearch.com",
            "*amazon-adsystem.com",
            "*connect.facebook.net",
            "*popads.net",
            "*propellerads.com",
            "*popcash.net",
            "*adsterra.com",
            "*adcash.com",
            "*clickadu.com",
            "*exoclick.com",
            "*hilltopads.com",
            "*monetag.com",
            "*mgid.com",
            "*yektanet.com",
            "*rubiconproject.com",
            "*pubmatic.com",
            "*openx.net",
            "*adform.net",
            "*moatads.com",
            "*clarity.ms",
            "*hotjar.com",
            "*quantserve.com",
            "*buysellads.com",
            "*revcontent.com",
            "*media.net",
            "*mc.yandex.ru",
            "*reklamstore.com",
            "*admatic.com.tr",
            "*medyanet.com.tr",
            "*gemius.pl",
            "*gemius.com",
            "*connatix.com",
            "*teads.tv",
            "*teads.com",
            "*primis.tech",
            "*aniview.com",
            "*vidoomy.com",
            "*anyclip.com",
            "*brid.tv",
            "*casalemedia.com",
            "*smartadserver.com",
            "*yieldmo.com",
            "*triplelift.com",
            "*sharethrough.com",
            "*sovrn.com",
            "*indexexchange.com",
            "*admiral.com",
            "*fundingchoicesmessages.google.com",
            "*pigeoon.com",
            "*useinsider.com",
            "*onesignal.com"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*"
        },
        "action": {
          "type": "css-display-none",
          "selector": ".advertisement, .ad-banner, .adsbygoogle, .taboola-container, #outbrain, div[id^='google_ads_'], div[id^='div-gpt-ad'], div[id^='ad-banner'], .sponsor-post, .dfp-ad, #ad-slot, ins.adsbygoogle, .ad-wrapper, .ad-container, [class*='ad-banner'], [class*='ad-modal'], [class*='popup-ad'], [id*='popup-ad'], [class*='newsletter-popup'], [class*='sticky-ad'], [id*='sticky-ad'], [class*='floating-ad'], [class*='ad-interstitial'], [id*='ad-interstitial'], .connatix-slot, .teads-inread, [class*='sponsored-post'], [class*='promoted-content'], [id^='taboola-'], [class^='outbrain-']"
        }
      }
    ]
    """
}
