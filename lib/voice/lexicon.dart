// Pure Dart (no Flutter imports) so the voice brain can be tested anywhere.

/// Normalizes a raw speech transcript: lowercase, strips tashkeel/tatweel,
/// unifies Arabic letter variants, converts Arabic digits, removes punctuation,
/// and splits letter/digit joins ("f6" -> "f 6").
String normalize(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp('[\u064B-\u065F\u0670\u0640]'), '');
  s = s
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  const arDigits = '٠١٢٣٤٥٦٧٨٩', faDigits = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(arDigits[i], '$i').replaceAll(faDigits[i], '$i');
  }
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
  s = s.replaceAllMapped(RegExp(r'(\p{L})(\p{N})', unicode: true), (m) => '${m[1]} ${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\p{N})(\p{L})', unicode: true), (m) => '${m[1]} ${m[2]}');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Piece synonyms (Arabic, English, and common mis-hearings).
const Map<String, List<String>> kPieces = {
  'k': ['ملك', 'كينج', 'كينغ', 'كنج', 'كنغ', 'king'],
  'q': ['وزير', 'ملكة', 'كوين', 'كوئين', 'قوين', 'queen'],
  'r': ['قلعة', 'رخ', 'طابية', 'روك', 'ورك', 'rook'],
  'b': ['فيل', 'بيشوب', 'بشوب', 'بيشب', 'اسقف', 'bishop'],
  'n': ['حصان', 'حسان', 'خيل', 'فارس', 'نايت', 'نايط', 'knight', 'night', 'horse'],
  'p': ['جندي', 'بيدق', 'بون', 'بوان', 'عسكري', 'pawn'],
};

/// File (column) letters as spoken in English and Arabic.
const Map<String, List<String>> kFiles = {
  'a': ['a', 'ay', 'ei', 'ey', 'ايه', 'الف', 'الفا', 'alpha'],
  'b': ['b', 'bee', 'be', 'بي', 'بيه', 'باء', 'با', 'برافو', 'bravo'],
  'c': ['c', 'see', 'sea', 'si', 'سي', 'جيم', 'تشارلي', 'شارلي', 'charlie'],
  'd': ['d', 'dee', 'di', 'دي', 'دال', 'دلتا', 'ديلتا', 'delta'],
  'e': ['e', 'ee', 'اي', 'ايي', 'ايكو', 'echo'],
  'f': ['f', 'ef', 'eff', 'اف', 'فاء', 'فا', 'foxtrot'],
  'g': ['g', 'gee', 'جي', 'جيه', 'golf', 'جولف', 'غولف'],
  'h': ['h', 'aitch', 'اتش', 'هاء', 'ها', 'hotel', 'هوتيل'],
};

/// Rank (row) numbers as spoken.
const Map<String, List<String>> kRanks = {
  '1': ['1', 'one', 'واحد', 'واحدة', 'وان', 'ون', 'وحدة'],
  '2': ['2', 'two', 'too', 'تو', 'اثنين', 'اتنين', 'اثنان', 'اثنتين', 'ثنتين'],
  '3': ['3', 'three', 'ثري', 'ثلاثة', 'ثلاث', 'تلاتة', 'تلات'],
  '4': ['4', 'four', 'for', 'فور', 'اربعة', 'اربع'],
  '5': ['5', 'five', 'فايف', 'خمسة', 'خمس'],
  '6': ['6', 'six', 'سيكس', 'ستة', 'ست', 'سكس'],
  '7': ['7', 'seven', 'سفن', 'سيفن', 'سبعة', 'سبع'],
  '8': ['8', 'eight', 'ate', 'ايت', 'ثمانية', 'تمانية', 'ثماني', 'ثمان'],
};
