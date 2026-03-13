import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../blocs/auth_bloc.dart';
import '../services/wallet_repository.dart';
import '../services/wallet_service.dart';
import 'wallet_qr_scan_screen.dart';
import '../theme/app_theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final Map<String, double> _ethBalances = {};
  final Map<String, double> _usdBalances = {};
  List<WalletProfile> _wallets = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  String _key(String address) => address.toLowerCase();

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final wallets = await context.read<WalletRepository>().loadAll(user.id);
    if (!mounted) return;
    setState(() {
      _wallets = wallets;
      _loading = false;
    });
    if (wallets.isNotEmpty) {
      await _refreshAll();
    }
  }

  Future<void> _refreshAll() async {
    if (_wallets.isEmpty) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final service = WalletService();
      double? price;
      try {
        price = await service.fetchEthUsdPrice();
      } catch (_) {}

      for (final wallet in _wallets) {
        final bal = await service.fetchEthBalance(wallet.address);
        _ethBalances[_key(wallet.address)] = bal;
        if (price != null) {
          _usdBalances[_key(wallet.address)] = bal * price;
        } else {
          _usdBalances.remove(_key(wallet.address));
        }
      }
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Balance refresh failed: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _addWallet() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    final address = await _promptAddress();
    if (address == null || address.isEmpty) return;
    if (!_isValidEvmAddress(address)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid wallet address format.')),
      );
      return;
    }
    if (!mounted) return;
    final profile = WalletProfile(address: address);
    await context.read<WalletRepository>().upsert(user.id, profile);
    if (!mounted) return;
    await _loadWallets();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wallet added.')),
    );
  }

  Future<void> _addWalletFromQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const WalletQrScanScreen(),
      ),
    );
    if (scanned == null || scanned.isEmpty) return;
    if (!mounted) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    if (!_isValidEvmAddress(scanned)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR does not contain a valid address.')),
      );
      return;
    }
    if (!mounted) return;
    final profile = WalletProfile(address: scanned);
    await context.read<WalletRepository>().upsert(user.id, profile);
    if (!mounted) return;
    await _loadWallets();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wallet added from QR.')),
    );
  }

  Future<void> _removeWallet(WalletProfile wallet) async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    await context.read<WalletRepository>().remove(user.id, wallet.address);
    _ethBalances.remove(_key(wallet.address));
    _usdBalances.remove(_key(wallet.address));
    if (!mounted) return;
    await _loadWallets();
  }

  Future<String?> _promptAddress() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Wallet'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Wallet address',
            hintText: '0x...',
          ),
          autocorrect: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  bool _isValidEvmAddress(String value) =>
      RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(value);

  @override
  Widget build(BuildContext context) {
    final totalUsd = _usdBalances.values.fold<double>(0.0, (a, b) => a + b);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(
          'Wallets',
          style: GoogleFonts.syne(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              primary: false,
              padding: const EdgeInsets.all(14),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Portfolio',
                        style: GoogleFonts.syne(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _usdBalances.isEmpty
                            ? 'USD Total: --'
                            : 'USD Total: \$${totalUsd.toStringAsFixed(2)}',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.green,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.red,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_wallets.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.bg2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      'No wallets linked yet. Tap Add Wallet.',
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  ..._wallets.map((wallet) {
                    final eth = _ethBalances[_key(wallet.address)];
                    final usd = _usdBalances[_key(wallet.address)];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bg2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wallet.network,
                            style: GoogleFonts.spaceGrotesk(
                              color: AppTheme.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            wallet.address,
                            style: GoogleFonts.spaceGrotesk(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            eth == null
                                ? 'ETH: --'
                                : 'ETH: ${eth.toStringAsFixed(6)}',
                            style: GoogleFonts.spaceGrotesk(
                              color: AppTheme.green,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            usd == null
                                ? 'USD: --'
                                : 'USD: \$${usd.toStringAsFixed(2)}',
                            style: GoogleFonts.spaceGrotesk(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _removeWallet(wallet),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Remove'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _addWallet,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Manually'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addWalletFromQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}
