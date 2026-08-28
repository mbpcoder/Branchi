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
    'language': 'Language',
    'close': 'Close',
    'terminal': 'Terminal',
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
  },
  'ar': {
    'app_title': 'راست‌غيت',
    'new_tab': 'علامة تبويب جديدة',
    'welcome': 'مرحبًا بك في RustGit',
    'pin_window': 'إبقاء النافذة في المقدمة',
    'unpin_window': 'إلغاء التثبيت',
    'settings': 'الإعدادات',
    'language': 'اللغة',
    'close': 'إغلاق',
    'terminal': 'الطرفية',
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
  },
  'fa': {
    'app_title': 'راست‌گیت',
    'new_tab': 'برگه جدید',
    'welcome': 'به RustGit خوش آمدید',
    'pin_window': 'نگه‌داشتن پنجره در بالا',
    'unpin_window': 'برداشتن سنجاق',
    'settings': 'تنظیمات',
    'language': 'زبان',
    'close': 'بستن',
    'terminal': 'ترمینال',
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
  },
};
