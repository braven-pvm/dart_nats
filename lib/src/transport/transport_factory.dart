// Conditional imports based on platform
export 'transport_factory_stub.dart'
    if (dart.library.io) 'transport_factory_io.dart'
    if (dart.library.html) 'transport_factory_web.dart';

import 'transport.dart';

/// Factory for creating transport implementations based on platform.
Transport createTransport(Uri uri);
