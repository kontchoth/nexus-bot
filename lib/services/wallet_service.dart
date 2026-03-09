import 'dart:async';
import 'dart:convert';

import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;

class WalletService {
  static const _rpcEndpoints = <String>[
    'https://cloudflare-eth.com',
    'https://ethereum.publicnode.com',
    'https://rpc.ankr.com/eth',
  ];

  Future<double> fetchEthBalance(String address) async {
    final ethAddress = EthereumAddress.fromHex(address);
    final errors = <String>[];

    for (final rpc in _rpcEndpoints) {
      final client = Web3Client(rpc, http.Client());
      try {
        final wei = await client
            .getBalance(ethAddress)
            .timeout(const Duration(seconds: 10));
        return wei.getValueInUnit(EtherUnit.ether);
      } catch (e) {
        errors.add('$rpc => $e');
      } finally {
        client.dispose();
      }
    }

    throw Exception(
      'All RPC providers failed. ${errors.join(' | ')}',
    );
  }

  Future<double> fetchEthUsdPrice() async {
    final uri = Uri.parse(
      'https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Price API failed (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final eth = body['ethereum'] as Map<String, dynamic>?;
    final usd = eth?['usd'];
    if (usd is num) return usd.toDouble();
    throw Exception('Invalid ETH price payload');
  }
}
