/// Connection options for NATS.
class ConnectOptions {
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
    final authCount = [
      authToken != null,
      (user != null && pass != null),
      jwt != null,
      nkeyPath != null,
    ].where((x) => x).length;

    if (authCount > 1) {
      throw ArgumentError('Only one authentication method can be specified: '
          'token, user/pass, JWT, or NKey');
    }
  }

  ConnectOptions copyWith({
    String? name,
    int? maxReconnectAttempts,
    Duration? reconnectDelay,
    Duration? pingInterval,
    int? maxPingOut,
    bool? noEcho,
    String? inboxPrefix,
    String? authToken,
    String? user,
    String? pass,
    String? jwt,
    String? nkeyPath,
  }) {
    return ConnectOptions(
      name: name ?? this.name,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      pingInterval: pingInterval ?? this.pingInterval,
      maxPingOut: maxPingOut ?? this.maxPingOut,
      noEcho: noEcho ?? this.noEcho,
      inboxPrefix: inboxPrefix ?? this.inboxPrefix,
      authToken: authToken ?? this.authToken,
      user: user ?? this.user,
      pass: pass ?? this.pass,
      jwt: jwt ?? this.jwt,
      nkeyPath: nkeyPath ?? this.nkeyPath,
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

  /// Connection error.
  error,
}
