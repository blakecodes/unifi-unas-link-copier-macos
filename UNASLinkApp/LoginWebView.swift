import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    let configuration: UNASConfiguration
    let onSessionCaptured: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration, onSessionCaptured: onSessionCaptured, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = context.coordinator

        if let url = configuration.normalizedServerURL {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let configuration: UNASConfiguration
        private let onSessionCaptured: () -> Void
        private let onError: (String) -> Void
        private var captured = false

        init(configuration: UNASConfiguration, onSessionCaptured: @escaping () -> Void, onError: @escaping (String) -> Void) {
            self.configuration = configuration
            self.onSessionCaptured = onSessionCaptured
            self.onError = onError
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard !captured else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self,
                      let host = self.configuration.normalizedServerURL?.host,
                      let cookie = cookies.first(where: {
                          $0.name == "TOKEN" && (host == $0.domain || host.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))))
                      }) else { return }

                do {
                    let claims = try JWTClaims.decode(from: cookie.value)
                    guard !claims.isExpired else { return }
                    try KeychainStore.saveSessionToken(cookie.value)
                    self.captured = true
                    DispatchQueue.main.async { self.onSessionCaptured() }
                } catch {
                    DispatchQueue.main.async { self.onError(error.localizedDescription) }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard configuration.allowSelfSignedCertificate,
                  challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  challenge.protectionSpace.host == configuration.normalizedServerURL?.host,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }
}
