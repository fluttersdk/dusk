/// Logging Configuration.
Map<String, dynamic> get loggingConfig => {
  'logging': {
    'default': 'stack',
    'channels': {
      'stack': {
        'driver': 'stack',
        'channels': ['console'],
      },
      'console': {'driver': 'console', 'level': 'debug'},
    },
  },
};
