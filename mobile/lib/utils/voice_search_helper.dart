class VoiceSearchHelper {
  static final Map<String, String> _phoneticMap = {
    'doodh': 'milk',
    'dudh': 'milk',
    'दूध': 'milk',
    'amul doodh': 'amul milk',
    'aata': 'atta',
    'aatta': 'atta',
    'gehu': 'wheat',
    'आटा': 'atta',
    'tel': 'oil',
    'sarso tel': 'mustard oil',
    'refine': 'sunflower oil',
    'तेल': 'oil',
    'chawal': 'rice',
    'चावल': 'rice',
    'namak': 'salt',
    'नमक': 'salt',
    'chini': 'sugar',
    'cheeni': 'sugar',
    'चीनी': 'sugar',
    'chai': 'tea',
    'चाय': 'tea',
    'biskut': 'biscuits',
    'biscoot': 'biscuits',
    'बिस्कुट': 'biscuits',
    'sabun': 'soap',
    'साबुन': 'soap',
    'gadi': 'vehicle',
    'bike': 'bike',
    'auto': 'auto',
    'रिक्शा': 'rickshaw',
  };

  static String normalize(String input) {
    String query = input.toLowerCase().trim();
    if (_phoneticMap.containsKey(query)) {
      return _phoneticMap[query]!;
    }
    _phoneticMap.forEach((hindi, english) {
      if (query.contains(hindi)) {
        query = query.replaceAll(hindi, english);
      }
    });
    return query;
  }
}
