/// View Configuration.
Map<String, dynamic> get viewConfig => {
  'view': {
    'dialog': {
      'class': 'bg-white dark:bg-gray-800 rounded-xl p-6 shadow-2xl max-w-lg',
    },
    'confirm': {
      'container_class':
          'bg-white dark:bg-gray-800 rounded-xl p-6 shadow-2xl w-80',
      'title_class': 'text-lg font-bold text-gray-900 dark:text-white',
      'message_class': 'text-gray-600 dark:text-gray-400 mt-2',
      'button_cancel_class': 'px-4 py-2 text-gray-600 dark:text-gray-300',
      'button_confirm_class': 'px-4 py-2 bg-primary text-white rounded-lg',
      'button_danger_class': 'px-4 py-2 bg-red-500 text-white rounded-lg',
    },
  },
};
