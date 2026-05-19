import 'package:magic/magic.dart';

/// Network Configuration.
Map<String, dynamic> get networkConfig => {
  'network': {
    'default': 'api',
    'drivers': {
      'api': {
        'base_url': env('API_URL', 'http://localhost:8000/api/v1'),
        'timeout': 10000,
        'headers': {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      },
    },
  },
};
