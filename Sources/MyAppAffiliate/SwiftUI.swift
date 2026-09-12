#if canImport(SwiftUI)
  import Foundation
  import SwiftUI

  /// The one-line SwiftUI integration.
  ///
  /// ```swift
  /// @main
  /// struct MyApp: App {
  ///   var body: some Scene {
  ///     WindowGroup {
  ///       ContentView().myAppAffiliate(apiKey: "pk_live_…")
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// Starts the SDK once and forwards every incoming Universal Link to it, so
  /// the app writes no `.onOpenURL` handler of its own. Everything else — the
  /// API host, retrying an offline first launch, asking for a deferred match on
  /// a fresh install — is handled inside.
  ///
  /// You still call ``MyAppAffiliate/identify(userId:)`` once you know who the
  /// user is; nothing else can supply your user id.
  @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
  extension View {
    public func myAppAffiliate(
      apiKey: String? = nil,
      options: MyAppAffiliate.Options = MyAppAffiliate.Options()
    ) -> some View {
      modifier(MyAppAffiliateModifier(apiKey: apiKey, options: options))
    }
  }

  @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
  private struct MyAppAffiliateModifier: ViewModifier {
    let apiKey: String?
    let options: MyAppAffiliate.Options

    func body(content: Content) -> some View {
      content
        .onAppear {
          // A view can appear more than once (tab switches, re-renders); the
          // SDK's work is idempotent but starting twice would re-run bootstrap,
          // so guard on it.
          guard !MyAppAffiliate.isStarted else { return }
          MyAppAffiliate.start(apiKey: apiKey, options: options)
        }
        .onOpenURL { url in MyAppAffiliate.attribute(url: url) }
    }
  }
#endif
