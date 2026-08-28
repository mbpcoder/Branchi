/// Supported languages and their translation tables.
///
/// This mirrors the lightweight approach RustDesk uses for its own UI
/// strings: a simple `key -> translated string` map per language instead of
/// generated ARB/`intl` bindings, so new languages can be added by dropping
/// in another map.
library rustgit.l10n.translations;

class LangInfo {
  const LangInfo({required this.code, required this.name, required this.rtl});

  final String code;
  final String name;
  final bool rtl;
}

/// Languages available in the settings page, in display order.
const List<LangInfo> supportedLanguages = [
  LangInfo(code: 'en', name: 'English', rtl: false),
  LangInfo(code: 'ar', name: 'العربية', rtl: true),
  LangInfo(code: 'fa', name: 'فارسی', rtl: true),
];

const Set<String> rtlLanguageCodes = {'ar', 'fa'};

const Map<String, Map<String, String>> translations = {
  'en': {
    'app_title': 'RustGit',
    'new_tab': 'New tab',
    'welcome': 'Welcome to RustGit',
    'pin_window': 'Keep window on top',
    'unpin_window': 'Unpin window',
    'settings': 'Settings',
    'switch_to_dark_mode': 'Switch to dark mode',
    'switch_to_light_mode': 'Switch to light mode',
    'language': 'Language',
    'close': 'Close',
    'terminal': 'Terminal',
    'logs': 'Logs',
    'no_logged_actions': 'No git actions have run yet.',
    'clear_logs': 'Clear logs',
    'local_repositories': 'Local Repositories',
    'open_repository': 'Open Repository',
    'new_repository': 'New Repository',
    'recent_repositories': 'Recent Repositories',
    'no_recent_repositories': 'No recent repositories',
    'clone_repository': 'Clone Repository',
    'source_url': 'Source URL',
    'repository_name': 'Repository Name',
    'destination_path': 'Destination Path',
    'clone': 'Clone',
    'cloning': 'Cloning…',
    'not_a_git_repository': 'The selected folder is not a git repository.',
    'repository_no_longer_exists': 'This repository no longer exists.',
    'source_url_required': 'Enter a source URL to clone.',
    'destination_path_required': 'Choose a destination path.',
    'repository_created': 'Repository created.',
    'repository_cloned': 'Repository cloned.',
  },
  'ar': {
    'app_title': 'راست‌غيت',
    'new_tab': 'علامة تبويب جديدة',
    'welcome': 'مرحبًا بك في RustGit',
    'pin_window': 'إبقاء النافذة في المقدمة',
    'unpin_window': 'إلغاء التثبيت',
    'settings': 'الإعدادات',
    'switch_to_dark_mode': 'التبديل إلى الوضع الداكن',
    'switch_to_light_mode': 'التبديل إلى الوضع الفاتح',
    'language': 'اللغة',
    'close': 'إغلاق',
    'terminal': 'الطرفية',
    'logs': 'السجلات',
    'no_logged_actions': 'لم يتم تنفيذ أي إجراءات git بعد.',
    'clear_logs': 'مسح السجلات',
    'local_repositories': 'المستودعات المحلية',
    'open_repository': 'فتح مستودع',
    'new_repository': 'مستودع جديد',
    'recent_repositories': 'المستودعات الأخيرة',
    'no_recent_repositories': 'لا توجد مستودعات حديثة',
    'clone_repository': 'استنساخ مستودع',
    'source_url': 'رابط المصدر',
    'repository_name': 'اسم المستودع',
    'destination_path': 'مسار الوجهة',
    'clone': 'استنساخ',
    'cloning': 'جارٍ الاستنساخ…',
    'not_a_git_repository': 'المجلد المحدد ليس مستودع git.',
    'repository_no_longer_exists': 'هذا المستودع لم يعد موجودًا.',
    'source_url_required': 'أدخل رابط المصدر للاستنساخ.',
    'destination_path_required': 'اختر مسار الوجهة.',
    'repository_created': 'تم إنشاء المستودع.',
    'repository_cloned': 'تم استنساخ المستودع.',
  },
  'fa': {
    'app_title': 'راست‌گیت',
    'new_tab': 'برگه جدید',
    'welcome': 'به RustGit خوش آمدید',
    'pin_window': 'نگه‌داشتن پنجره در بالا',
    'unpin_window': 'برداشتن سنجاق',
    'settings': 'تنظیمات',
    'switch_to_dark_mode': 'تغییر به حالت تیره',
    'switch_to_light_mode': 'تغییر به حالت روشن',
    'language': 'زبان',
    'close': 'بستن',
    'terminal': 'ترمینال',
    'logs': 'گزارش‌ها',
    'no_logged_actions': 'هنوز هیچ عملیات gitای اجرا نشده است.',
    'clear_logs': 'پاک کردن گزارش‌ها',
    'local_repositories': 'مخزن‌های محلی',
    'open_repository': 'باز کردن مخزن',
    'new_repository': 'مخزن جدید',
    'recent_repositories': 'مخزن‌های اخیر',
    'no_recent_repositories': 'مخزن اخیری وجود ندارد',
    'clone_repository': 'کلون مخزن',
    'source_url': 'آدرس منبع',
    'repository_name': 'نام مخزن',
    'destination_path': 'مسیر مقصد',
    'clone': 'کلون',
    'cloning': 'در حال کلون…',
    'not_a_git_repository': 'پوشه انتخاب‌شده یک مخزن git نیست.',
    'repository_no_longer_exists': 'این مخزن دیگر وجود ندارد.',
    'source_url_required': 'برای کلون کردن یک آدرس منبع وارد کنید.',
    'destination_path_required': 'یک مسیر مقصد انتخاب کنید.',
    'repository_created': 'مخزن ایجاد شد.',
    'repository_cloned': 'مخزن کلون شد.',
  },
};
