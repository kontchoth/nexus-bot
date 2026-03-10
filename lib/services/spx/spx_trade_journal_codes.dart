class SpxEntryReasonCodes {
  static const String manualBuy = 'manual_buy';
  static const String autoScannerSignal = 'auto_scanner_signal';

  static const Set<String> values = {
    manualBuy,
    autoScannerSignal,
  };

  static String label(String code) {
    switch (code) {
      case manualBuy:
        return 'Manual Buy';
      case autoScannerSignal:
        return 'Auto Scanner Signal';
      default:
        return code;
    }
  }
}

class SpxExitReasonCodes {
  static const String manualClose = 'manual_close';
  static const String stopLoss = 'stop_loss';
  static const String takeProfit = 'take_profit';
  static const String expired = 'expired';

  static const Set<String> values = {
    manualClose,
    stopLoss,
    takeProfit,
    expired,
  };

  static String label(String code) {
    switch (code) {
      case manualClose:
        return 'Manual Close';
      case stopLoss:
        return 'Stop Loss';
      case takeProfit:
        return 'Take Profit';
      case expired:
        return 'Expired';
      default:
        return code;
    }
  }
}

class SpxReviewVerdictCodes {
  static const String goodSetup = 'good_setup';
  static const String badSetup = 'bad_setup';
  static const String neutral = 'neutral';

  static const Set<String> values = {
    goodSetup,
    badSetup,
    neutral,
  };

  static String label(String code) {
    switch (code) {
      case goodSetup:
        return 'Good Setup';
      case badSetup:
        return 'Bad Setup';
      case neutral:
        return 'Neutral';
      default:
        return code;
    }
  }
}
