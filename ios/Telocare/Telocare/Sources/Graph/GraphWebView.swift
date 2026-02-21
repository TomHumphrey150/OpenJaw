import SwiftUI
import WebKit

struct GraphWebView: UIViewRepresentable {
    let graphData: CausalGraphData
    let displayFlags: GraphDisplayFlags
    let focusedNodeID: String?
    let onEvent: (GraphEvent) -> Void

    private let messageHandlerName = "graphBridge"

    func makeCoordinator() -> Coordinator {
        Coordinator(
            messageHandlerName: messageHandlerName,
            onEvent: onEvent
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.webView = webView

        let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Graph")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")

        if let indexURL {
            let graphDirectoryURL = indexURL.deletingLastPathComponent()
            webView.loadFileURL(indexURL, allowingReadAccessTo: graphDirectoryURL)
        } else {
            onEvent(.renderError(message: "Graph resource missing."))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.sync(
            graphData: graphData,
            displayFlags: displayFlags,
            focusedNodeID: focusedNodeID
        )
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: coordinator.messageHandlerName)
        uiView.navigationDelegate = nil
    }
}

final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let messageHandlerName: String
    let onEvent: (GraphEvent) -> Void

    weak var webView: WKWebView?

    private var isPageLoaded = false
    private var queuedJavaScript: [String] = []
    private var lastGraphData: CausalGraphData?
    private var lastDisplayFlags: GraphDisplayFlags?
    private var lastFocusedNodeID: String?

    init(messageHandlerName: String, onEvent: @escaping (GraphEvent) -> Void) {
        self.messageHandlerName = messageHandlerName
        self.onEvent = onEvent
    }

    func enqueue(command: GraphCommand) {
        guard let commandJSON = command.jsonString() else {
            return
        }

        let script = "window.TelocareGraph.receiveSwiftMessage(\(javaScriptStringLiteral(for: commandJSON)));"
        enqueue(javaScript: script)
    }

    func sync(
        graphData: CausalGraphData,
        displayFlags: GraphDisplayFlags,
        focusedNodeID: String?
    ) {
        if lastGraphData != graphData {
            enqueue(command: .setGraphData(graphData))
            lastGraphData = graphData
            lastFocusedNodeID = nil
        }

        if lastDisplayFlags != displayFlags {
            enqueue(command: .setDisplayFlags(displayFlags))
            lastDisplayFlags = displayFlags
            lastFocusedNodeID = nil
        }

        guard let focusedNodeID else {
            lastFocusedNodeID = nil
            return
        }

        guard lastFocusedNodeID != focusedNodeID else {
            return
        }

        enqueue(command: .focusNode(focusedNodeID))
        lastFocusedNodeID = focusedNodeID
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true
        flushQueuedJavaScript(on: webView)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == messageHandlerName else {
            return
        }

        guard let body = message.body as? [String: Any], let eventName = body["event"] as? String else {
            onEvent(.renderError(message: "Invalid bridge event payload."))
            return
        }

        let payload = body["payload"] as? [String: Any]

        switch eventName {
        case "graphReady":
            onEvent(.graphReady)
        case "nodeSelected":
            let id = payload?["id"] as? String ?? ""
            let label = payload?["label"] as? String ?? id
            lastFocusedNodeID = id
            onEvent(.nodeSelected(id: id, label: label))
        case "edgeSelected":
            let sourceID = payload?["source"] as? String ?? ""
            let targetID = payload?["target"] as? String ?? ""
            let sourceLabel = payload?["sourceLabel"] as? String ?? sourceID
            let targetLabel = payload?["targetLabel"] as? String ?? targetID
            let label = payload?["label"] as? String
            onEvent(
                .edgeSelected(
                    sourceID: sourceID,
                    targetID: targetID,
                    sourceLabel: sourceLabel,
                    targetLabel: targetLabel,
                    label: label
                )
            )
        case "viewportChanged":
            let zoom = Self.doubleValue(payload?["zoom"]) ?? 1.0
            onEvent(.viewportChanged(zoom: zoom))
        case "renderError":
            let message = payload?["message"] as? String ?? "Unknown graph rendering error."
            onEvent(.renderError(message: message))
        default:
            onEvent(.renderError(message: "Unsupported bridge event \(eventName)."))
        }
    }

    private func enqueue(javaScript: String) {
        guard let webView else {
            return
        }

        if isPageLoaded {
            evaluate(javaScript, on: webView)
        } else {
            queuedJavaScript.append(javaScript)
        }
    }

    private func flushQueuedJavaScript(on webView: WKWebView) {
        for script in queuedJavaScript {
            evaluate(script, on: webView)
        }

        queuedJavaScript.removeAll()
    }

    private func evaluate(_ script: String, on webView: WKWebView) {
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let error else {
                return
            }

            self?.onEvent(.renderError(message: error.localizedDescription))
        }
    }

    private func javaScriptStringLiteral(for value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        return "\"\(escaped)\""
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double {
            return number
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let text = value as? String {
            return Double(text)
        }

        return nil
    }
}
