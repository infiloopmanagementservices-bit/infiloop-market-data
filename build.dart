// Builds the two public files the Infiloop app downloads (CR-15):
//   companies.csv  ISIN,NSE,BSE,Name   (all listed shares)
//   prices.csv     date,YYYY-MM-DD then ISIN,close
// from the NSE and BSE end-of-day "bhavcopy" files (UDiFF CSV format).
//
// Usage: dart run build.dart <nse.csv> <bse.csv> <out-dir>
// Either input may be missing (e.g. one exchange's file not out yet).
import 'dart:io';

class Row {
  Row(this.isin, this.name);
  final String isin;
  String name;
  String? nse, bse;
  double? nseClose, bseClose;
}

// Columns in the UDiFF bhavcopy.
const _id = 5, _isin = 6, _sym = 7, _series = 8, _name = 13, _close = 17, _date = 0;

List<List<String>> _read(String path) {
  final f = File(path);
  if (!f.existsSync()) return const [];
  final lines = f.readAsLinesSync();
  return [for (final l in lines.skip(1)) l.split(',')].where((p) => p.length > _close).toList();
}

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('Usage: dart run build.dart <nse.csv> <bse.csv> <out-dir>');
    exit(64);
  }
  final rows = <String, Row>{};
  String? date;
  // NSE: equity-like series only (EQ, BE, BZ, SM, ST, plus ETFs which use EQ).
  for (final p in _read(args[0])) {
    if (!{'EQ', 'BE', 'BZ', 'SM', 'ST'}.contains(p[_series].trim())) continue;
    final isin = p[_isin].trim();
    if (isin.length != 12) continue;
    final r = rows.putIfAbsent(isin, () => Row(isin, p[_name].trim()));
    r.nse = p[_sym].trim();
    r.nseClose = double.tryParse(p[_close]);
    date ??= p[_date].trim();
  }
  for (final p in _read(args[1])) {
    final isin = p[_isin].trim();
    if (isin.length != 12) continue;
    final r = rows.putIfAbsent(isin, () => Row(isin, p[_name].trim()));
    r.bse = p[_id].trim();
    r.bseClose = double.tryParse(p[_close]);
    // BSE names are usually the full company name.
    if (p[_name].trim().length > r.name.length) r.name = p[_name].trim();
    date ??= p[_date].trim();
  }
  if (rows.isEmpty || date == null) {
    stderr.writeln('No rows read — files missing or format changed.');
    exit(1);
  }
  final out = Directory(args[2])..createSync(recursive: true);
  final sorted = rows.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final companies = StringBuffer('ISIN,NSE,BSE,Name\n');
  final prices = StringBuffer('date,$date\n');
  for (final r in sorted) {
    companies.writeln('${r.isin},${r.nse ?? ''},${r.bse ?? ''},${r.name.replaceAll('\n', ' ')}');
    final close = r.nseClose ?? r.bseClose;
    if (close != null && close > 0) prices.writeln('${r.isin},$close');
  }
  File('${out.path}/companies.csv').writeAsStringSync(companies.toString());
  File('${out.path}/prices.csv').writeAsStringSync(prices.toString());
  stdout.writeln('${sorted.length} companies, price date $date');
}
