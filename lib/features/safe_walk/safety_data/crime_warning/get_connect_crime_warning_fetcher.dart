import 'package:town_pass/features/safe_walk/safety_data/violent_crime/get_connect_text_fetcher.dart';

/// Default transport for the primary UTF-8 dataset and JSON metadata.
/// No request contains a user position. Big5 secondary CSVs require an explicit
/// audited Unicode decoder upstream; this transport never guesses their bytes.
Future<String> getConnectCrimeWarningTextFetcher(Uri uri) =>
    getConnectTextFetcher(uri);
