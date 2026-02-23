// Conditional imports based on platform — each target file defines createTransport().
export 'transport_factory_stub.dart'
    if (dart.library.io) 'transport_factory_io.dart'
    if (dart.library.html) 'transport_factory_web.dart';
