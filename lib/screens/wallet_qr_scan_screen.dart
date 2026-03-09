import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

class WalletQrScanScreen extends StatefulWidget {
  const WalletQrScanScreen({super.key});

  @override
  State<WalletQrScanScreen> createState() => _WalletQrScanScreenState();
}

class _WalletQrScanScreenState extends State<WalletQrScanScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Scan Wallet QR'),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          final codes = capture.barcodes;
          if (codes.isEmpty) return;
          final raw = (codes.first.rawValue ?? '').trim();
          final address = _extractAddress(raw);
          if (address == null) return;
          _handled = true;
          Navigator.of(context).pop(address);
        },
      ),
    );
  }

  String? _extractAddress(String raw) {
    final lower = raw.toLowerCase();
    if (RegExp(r'^0x[a-f0-9]{40}$').hasMatch(lower)) return raw;

    if (lower.startsWith('ethereum:')) {
      var value = raw.substring('ethereum:'.length);
      final atIdx = value.indexOf('@');
      if (atIdx != -1) value = value.substring(0, atIdx);
      final qIdx = value.indexOf('?');
      if (qIdx != -1) value = value.substring(0, qIdx);
      if (RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(value)) return value;
    }
    return null;
  }
}
