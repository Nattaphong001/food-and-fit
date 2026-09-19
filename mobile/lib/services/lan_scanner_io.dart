import 'dart:io';

/// คืนค่า prefix subnet /24 (เช่น "192.168.1") ของทุก network interface ที่เครื่องต่ออยู่
/// (ปกติมีแค่วง Wi-Fi เดียว) ใช้หาว่าจะสแกนหา backend ในช่วง IP ไหน — ไม่ใช้ค่า IP คงที่แล้ว
Future<List<String>> localSubnetPrefixes() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final prefixes = <String>{};
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final parts = addr.address.split('.');
        if (parts.length == 4) {
          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    }
    return prefixes.toList();
  } catch (_) {
    return const [];
  }
}
