// Node naming, ported 1:1 from the Nova Proxy worker (the "core").
//
// The worker names every generated node `{flag} Nova-{id}`, where the flag is
// the exit datacenter's country and the id is 6 random lowercase-alphanumeric
// characters. See IRNova/Nova-Proxy `sourcecode.js`:
//
//   const novaName = coloFlag(request) + 'Nova-' +
//     Array.from(crypto.getRandomValues(new Uint8Array(6)),
//               b => 'abcdefghijklmnopqrstuvwxyz0123456789'[b % 36]).join('');
//
// Nova Client matches that convention so Radar-found nodes look and sort exactly
// like the ones the subscription hands out, then appends a small suffix so a
// scanned node is distinguishable from a server-issued one (the core uses the
// same idea with its ` ·S1` chain markers).

import 'dart:math';

/// The marker appended to Radar-found node names so they're distinguishable
/// from nodes issued directly by the worker. The core uses a similar ` ·S`
/// chain marker; ` ·R` reads as "Radar".
const String kRadarSuffix = ' ·R';

/// The 36-character alphabet the worker draws node ids from.
const String _kIdAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// Cloudflare colo (datacenter) code → ISO-3166 alpha-2 country.
/// Ported verbatim from the worker's `COLO_COUNTRY` table.
const Map<String, String> kColoCountry = <String, String>{
  // North America — US
  'IAD': 'US', 'EWR': 'US', 'JFK': 'US', 'LGA': 'US', 'BOS': 'US', 'ORD': 'US',
  'DFW': 'US', 'IAH': 'US', 'ATL': 'US', 'MIA': 'US', 'TPA': 'US', 'MCO': 'US',
  'LAX': 'US', 'SJC': 'US', 'SFO': 'US', 'SEA': 'US', 'PDX': 'US', 'DEN': 'US',
  'PHX': 'US', 'LAS': 'US', 'SLC': 'US', 'MCI': 'US', 'MSP': 'US', 'DTW': 'US',
  'PHL': 'US', 'PIT': 'US', 'CLT': 'US', 'BNA': 'US', 'IND': 'US', 'CMH': 'US',
  'STL': 'US', 'SAN': 'US', 'HNL': 'US', 'ABQ': 'US', 'OKC': 'US', 'BUF': 'US',
  'RIC': 'US', 'ORF': 'US',
  // Canada / Mexico
  'YYZ': 'CA', 'YUL': 'CA', 'YVR': 'CA', 'YYC': 'CA', 'YWG': 'CA', 'YOW': 'CA',
  'YHZ': 'CA', 'MEX': 'MX', 'GDL': 'MX', 'QRO': 'MX', 'MTY': 'MX',
  // Europe
  'AMS': 'NL', 'FRA': 'DE', 'DUS': 'DE', 'HAM': 'DE', 'MUC': 'DE', 'STR': 'DE',
  'TXL': 'DE', 'BER': 'DE', 'CDG': 'FR', 'MRS': 'FR', 'LYS': 'FR', 'LHR': 'GB',
  'MAN': 'GB', 'LON': 'GB', 'EDI': 'GB', 'DUB': 'IE', 'MAD': 'ES', 'BCN': 'ES',
  'LIS': 'PT', 'MXP': 'IT', 'FCO': 'IT', 'PMO': 'IT', 'VIE': 'AT', 'ZRH': 'CH',
  'GVA': 'CH', 'BRU': 'BE', 'CPH': 'DK', 'ARN': 'SE', 'GOT': 'SE', 'OSL': 'NO',
  'HEL': 'FI', 'WAW': 'PL', 'PRG': 'CZ', 'BUD': 'HU', 'OTP': 'RO', 'SOF': 'BG',
  'ATH': 'GR', 'SKG': 'GR', 'BEG': 'RS', 'ZAG': 'HR', 'LJU': 'SI', 'BTS': 'SK',
  'KBP': 'UA', 'RIX': 'LV', 'TLL': 'EE', 'VNO': 'LT', 'KEF': 'IS', 'LUX': 'LU',
  'MLA': 'MT',
  // Middle East
  'DXB': 'AE', 'AUH': 'AE', 'DOH': 'QA', 'KWI': 'KW', 'BAH': 'BH', 'RUH': 'SA',
  'JED': 'SA', 'MCT': 'OM', 'AMM': 'JO', 'BEY': 'LB', 'TLV': 'IL', 'BGW': 'IQ',
  'IST': 'TR', 'ADB': 'TR',
  // Caucasus / Central Asia
  'GYD': 'AZ', 'TBS': 'GE', 'EVN': 'AM', 'TAS': 'UZ', 'ALA': 'KZ',
  // Asia-Pacific
  'SIN': 'SG', 'HKG': 'HK', 'TPE': 'TW', 'KHH': 'TW', 'NRT': 'JP', 'KIX': 'JP',
  'ITM': 'JP', 'ICN': 'KR', 'BKK': 'TH', 'KUL': 'MY', 'CGK': 'ID', 'JKT': 'ID',
  'MNL': 'PH', 'HAN': 'VN', 'SGN': 'VN', 'BOM': 'IN', 'DEL': 'IN', 'MAA': 'IN',
  'BLR': 'IN', 'HYD': 'IN', 'CCU': 'IN', 'NAG': 'IN', 'CMB': 'LK', 'DAC': 'BD',
  'KTM': 'NP', 'ISB': 'PK', 'KHI': 'PK', 'LHE': 'PK',
  // Africa
  'JNB': 'ZA', 'CPT': 'ZA', 'DUR': 'ZA', 'NBO': 'KE', 'MBA': 'KE', 'LOS': 'NG',
  'CAI': 'EG', 'CMN': 'MA', 'TUN': 'TN', 'ALG': 'DZ', 'ACC': 'GH', 'DAR': 'TZ',
  // South America
  'GRU': 'BR', 'GIG': 'BR', 'FOR': 'BR', 'POA': 'BR', 'EZE': 'AR', 'SCL': 'CL',
  'LIM': 'PE', 'BOG': 'CO', 'UIO': 'EC',
  // Oceania
  'SYD': 'AU', 'MEL': 'AU', 'PER': 'AU', 'BNE': 'AU', 'ADL': 'AU', 'AKL': 'NZ',
};

/// Turns an ISO-3166 alpha-2 country code into its flag emoji (two regional
/// indicator symbols). Returns `''` for anything that isn't two A-Z letters.
/// Ported from the worker's `flagFromCountry`.
String flagFromCountry(String cc) {
  if (cc.length != 2) return '';
  final String up = cc.toUpperCase();
  final int a = up.codeUnitAt(0);
  final int b = up.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCodes(<int>[0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

/// Flag prefix (emoji + trailing space) for a Cloudflare colo code, e.g.
/// `'YYZ'` → `'🇨🇦 '`. Unknown/empty colos return `''`. Ported from the
/// worker's `coloFlag`.
String coloToFlag(String? colo) {
  if (colo == null || colo.isEmpty) return '';
  final String? cc = kColoCountry[colo.toUpperCase()];
  if (cc == null) return '';
  final String flag = flagFromCountry(cc);
  return flag.isEmpty ? '' : '$flag ';
}

/// A random 6-character node id from the worker's alphabet.
String novaNodeId([Random? rng]) {
  final Random r = rng ?? Random.secure();
  final StringBuffer sb = StringBuffer();
  for (int i = 0; i < 6; i++) {
    sb.write(_kIdAlphabet[r.nextInt(_kIdAlphabet.length)]);
  }
  return sb.toString();
}

/// Builds a node name in the core's convention: `{flag} Nova-{id}{suffix}`.
///
/// [colo] is the exit datacenter code (from a `/cdn-cgi/trace` lookup against
/// the clean IP); when unknown the flag is simply omitted, exactly as the
/// worker does. [suffix] defaults to [kRadarSuffix].
String novaNodeName({String? colo, String suffix = kRadarSuffix, Random? rng}) {
  return '${coloToFlag(colo)}Nova-${novaNodeId(rng)}$suffix';
}
