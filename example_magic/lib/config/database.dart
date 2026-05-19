/// Database Configuration.
Map<String, dynamic> get databaseConfig => {
  'database': {
    'default': 'sqlite',
    'connections': {
      'sqlite': {'driver': 'sqlite', 'database': 'database.sqlite'},
    },
  },
};
