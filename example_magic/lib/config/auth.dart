/// Authentication Configuration.
final Map<String, dynamic> authConfig = {
  'auth': {
    'defaults': {'guard': 'api'},
    'guards': {
      'api': {'driver': 'bearer'},
    },
    'endpoints': {'user': '/auth/user', 'refresh': '/auth/refresh'},
    'token': {
      'key': 'auth_token',
      'refresh_key': 'refresh_token',
      'header': 'Authorization',
      'prefix': 'Bearer',
    },
    'cache': {'user_key': 'auth_user'},
    'auto_refresh': true,
  },
};
