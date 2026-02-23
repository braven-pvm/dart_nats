/// Connection options for NATS.
class ConnectOptions {
  static const Object _unset = Object();

  const ConnectOptions({
    this.name,
    this.maxReconnectAttempts = -1,
    this.reconnectDelay = const Duration(seconds: 2),
    this.pingInterval = const Duration(minutes: 2),
    this.maxPingOut = 2,
    this.noEcho = false,
    this.inboxPrefix = '_INBOX',
    this.authToken,
    this.user,
    this.pass,
    this.jwt,
    this.nkeyPath,
  });

  /// Display name for this client (visible in monitoring).
  final String? name;

  /// Maximum number of reconnection attempts. -1 = infinite.
  final int maxReconnectAttempts;

  /// Delay between reconnection attempts.
  final Duration reconnectDelay;

  /// Interval for sending PING to keep connection alive.
  final Duration pingInterval;

  /// Maximum number of pending PINGs before disconnecting.
  final int maxPingOut;

  /// Do not receive own published messages (when subscribed to published subjects).
  final bool noEcho;

  /// Prefix for generated inbox subjects.
  final String inboxPrefix;

  /// Static token authentication.
  final String? authToken;

  /// Username for basic authentication.
  final String? user;

  /// Password for basic authentication.
  final String? pass;

  /// JWT for decentralized authentication.
  final String? jwt;

  /// Path to NKey seed file for challenge/response authentication.
  final String? nkeyPath;

  /// Validate that auth credentials are properly set.
  ///
  /// Throws [ArgumentError] if incompatible auth modes are specified.
  void validate() {
    // Auth methods: token, user/pass, or JWT+NKey (single method)
    final hasAuthToken = authToken != null;
    final hasUserPass = user != null && pass != null;
    final hasJwt = jwt != null;
    final hasNkeyPath = nkeyPath != null;
    final hasJwtAuth = hasJwt || hasNkeyPath;

    // Validate that jwt and nkeyPath are both set together or both null
    if (hasJwt != hasNkeyPath) {
      throw ArgumentError(
        'JWT authentication requires both jwt and nkeyPath to be set together',
      );
    }

    final authCount = [
      hasAuthToken,
      hasUserPass,
      hasJwtAuth,
    ].where((x) => x).length;

    if (authCount > 1) {
      throw ArgumentError(
        'Only one authentication method can be specified: '
        'token, user/pass, or JWT+NKey',
      );
    }
  }

  /// Create a copy with some fields replaced.
  ConnectOptions copyWith({
    String? name,
    int? maxReconnectAttempts,
    Duration? reconnectDelay,
    Duration? pingInterval,
    int? maxPingOut,
    bool? noEcho,
    String? inboxPrefix,
    Object? authToken = _unset,
    Object? user = _unset,
    Object? pass = _unset,
    Object? jwt = _unset,
    Object? nkeyPath = _unset,
  }) {
    return ConnectOptions(
      name: name ?? this.name,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      pingInterval: pingInterval ?? this.pingInterval,
      maxPingOut: maxPingOut ?? this.maxPingOut,
      noEcho: noEcho ?? this.noEcho,
      inboxPrefix: inboxPrefix ?? this.inboxPrefix,
      authToken: authToken == _unset ? this.authToken : (authToken as String?),
      user: user == _unset ? this.user : (user as String?),
      pass: pass == _unset ? this.pass : (pass as String?),
      jwt: jwt == _unset ? this.jwt : (jwt as String?),
      nkeyPath: nkeyPath == _unset ? this.nkeyPath : (nkeyPath as String?),
    );
  }
}

/// Status of the NATS connection.
enum ConnectionStatus {
  /// Attempting initial connection.
  connecting,

  /// Successfully connected.
  connected,

  /// Disconnected (temporarily) and attempting to reconnect.
  reconnecting,

  /// Connection permanently closed.
  closed,
}
