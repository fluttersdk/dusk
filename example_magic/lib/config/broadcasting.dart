import 'package:magic/magic.dart';

/// Broadcasting Configuration.
Map<String, dynamic> get broadcastingConfig => {
  'broadcasting': {
    'default': env('BROADCAST_CONNECTION', 'null'),
    'connections': {
      'reverb': {
        'driver': 'reverb',
        'host': env('REVERB_HOST', 'localhost'),
        'port': int.tryParse(env('REVERB_PORT', '8080')) ?? 8080,
        'scheme': env('REVERB_SCHEME', 'ws'),
        'app_key': env('REVERB_APP_KEY', ''),
        'auth_endpoint': '/broadcasting/auth',
        'reconnect': true,
        'max_reconnect_delay': 30000,
        'activity_timeout': 120,
        'dedup_buffer_size': 100,
      },
      'null': {'driver': 'null'},
    },
  },
};
