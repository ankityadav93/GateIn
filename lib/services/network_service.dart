import 'dart:io';
import '../utils/constants.dart';

class NetworkService {
  Future<String?> detectLoginPortal() async {
    for (final url in AppConstants.commonPortalIPs) {
      if (await _isValidPortal(url)) return url;
    }
    
    final gateway = await _findGatewayIp();
    if (gateway != null) {
      final url = "http://$gateway:1000/login?";
      if (await _isValidPortal(url)) return url;
    }
    
    return null;
  }

  Future<bool> _isValidPortal(String url) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = AppConstants.connectionTimeout;
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      return (res.statusCode == 200 && 
              res.headers.contentType?.mimeType == "text/html");
    } catch (_) {
      return false;
    }
  }

  Future<String?> _findGatewayIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            parts[3] = '1';
            return parts.join('.');
          }
        }
      }
    } catch (_) {}
    return null;
  }
}