/// Optional consumer-side hook that `ext.dusk.navigate` consults before
/// falling back to [SystemNavigator.routeInformationUpdated].
///
/// Hosts that own a router with a non-default RouteInformationProvider
/// (GoRouter wired through Magic / MagicRoute, auto_route with custom
/// parser) register an adapter so dusk pushes through the host router's
/// public API instead of broadcasting a platform message the delegate
/// may not be listening to.
///
/// Contract:
/// 1. Return `true` when the route was accepted and the active router
///    has begun the navigation. Return `false` when the adapter cannot
///    handle the request so dusk falls back to the platform broadcast.
/// 2. Throw to surface an adapter-internal failure; dusk swallows the
///    throw (logs to `dusk` developer log) and still falls back.
/// 3. The adapter MUST NOT block on long-running async work. Push the
///    route synchronously (or with a single `await` on the router's
///    public push API) and return.
typedef DuskNavigateAdapter = Future<bool> Function(String route);
