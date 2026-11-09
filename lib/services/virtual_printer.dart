import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The "PDF Desk" printer: Windows' built-in "Microsoft Print To PDF" driver
/// on a local port that is a file path, so printing writes a PDF straight
/// into the print inbox without a save dialog. No driver of our own is
/// needed, so it works the same on x64 and ARM64.
class VirtualPrinter {
  static const printerName = 'PDF Desk';
  static const driverName = 'Microsoft Print To PDF';

  static bool get supported => Platform.isWindows;

  static Future<bool> isInstalled() async {
    if (!supported) return false;
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "if (Get-Printer -Name '${_q(printerName)}' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }",
    ]);
    return r.exitCode == 0;
  }

  /// Adds the printer writing to [outputFile]. Asks for administrator rights
  /// (UAC). Returns an error message, or null on success.
  static Future<String?> install(String outputFile) async {
    await Directory(p.dirname(outputFile)).create(recursive: true);
    return _runElevated('''
if (-not (Get-PrinterDriver -Name '${_q(driverName)}' -ErrorAction SilentlyContinue)) {
  Write-Error 'NO_DRIVER'; exit 2
}
\$port = '${_q(outputFile)}'
if (Get-Printer -Name '${_q(printerName)}' -ErrorAction SilentlyContinue) {
  Remove-Printer -Name '${_q(printerName)}'
}
if (-not (Get-PrinterPort -Name \$port -ErrorAction SilentlyContinue)) {
  Add-PrinterPort -Name \$port
}
Add-Printer -Name '${_q(printerName)}' -DriverName '${_q(driverName)}' -PortName \$port
''');
  }

  /// Removes the printer and its port. Returns an error message, or null.
  static Future<String?> uninstall(String outputFile) => _runElevated('''
if (Get-Printer -Name '${_q(printerName)}' -ErrorAction SilentlyContinue) {
  Remove-Printer -Name '${_q(printerName)}'
}
\$port = '${_q(outputFile)}'
if (Get-PrinterPort -Name \$port -ErrorAction SilentlyContinue) {
  Remove-PrinterPort -Name \$port
}
''');

  /// Single quotes are escaped by doubling inside a PowerShell '…' string.
  static String _q(String s) => s.replaceAll("'", "''");

  static Future<String?> _runElevated(String body) async {
    if (!supported) return 'Windows에서만 사용할 수 있습니다.';
    final dir = await Directory.systemTemp.createTemp('pdfdesk_printer');
    try {
      final script = File(p.join(dir.path, 'setup.ps1'));
      final log = p.join(dir.path, 'log.txt');
      // A BOM makes Windows PowerShell 5 read non-ASCII paths (e.g. a Korean
      // user name) correctly.
      await script.writeAsBytes([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('''
\$ErrorActionPreference = 'Stop'
try {
$body
  exit 0
} catch {
  \$_.ToString() | Out-File -FilePath '${_q(log)}' -Encoding utf8
  exit 1
}
'''),
      ]);
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "\$p = Start-Process powershell -Verb RunAs -Wait -PassThru -WindowStyle Hidden "
            "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"${_q(script.path)}\"'; "
            'exit \$p.ExitCode',
      ]);
      if (r.exitCode == 0) return null;
      final detail = File(log).existsSync() ? File(log).readAsStringSync().trim() : '';
      if (detail.contains('NO_DRIVER') || r.exitCode == 2) {
        return "'Microsoft Print to PDF'가 꺼져 있습니다. Windows 기능 켜기/끄기에서 켜 주세요.";
      }
      if (detail.isEmpty) return '관리자 권한이 필요합니다. (취소되었거나 실행하지 못했습니다)';
      return detail;
    } finally {
      await dir.delete(recursive: true);
    }
  }
}
