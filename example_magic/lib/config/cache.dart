import 'package:magic/magic.dart';

/// Cache Configuration.
Map<String, dynamic> get cacheConfig => {
  'cache': {'driver': FileStore(), 'ttl': 3600},
};
