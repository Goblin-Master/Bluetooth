import 'dart:convert';

const defaultSppUuid = '00001101-0000-1000-8000-00805F9B34FB';
const defaultRfcommChannel = 1;

class PairedBluetoothDevice {
  const PairedBluetoothDevice({required this.address, required this.name});

  factory PairedBluetoothDevice.fromMap(Map<dynamic, dynamic> map) {
    final address = (map['address'] ?? '').toString().trim();
    final name = map['name']?.toString();
    return PairedBluetoothDevice(address: address, name: name ?? '');
  }

  final String address;
  final String name;

  String get label => displayBluetoothName(name, address);
}

class OutboundMessage {
  const OutboundMessage._({required this.text, required this.byteLength});

  factory OutboundMessage.fromInput(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      throw ArgumentError('message is empty');
    }
    return OutboundMessage._(text: text, byteLength: utf8.encode(text).length);
  }

  final String text;
  final int byteLength;
}

String displayBluetoothName(String? name, String address) {
  final normalizedName = name?.trim() ?? '';
  if (normalizedName.isNotEmpty) {
    return normalizedName;
  }
  return address.trim();
}

int comparePairedDevices(PairedBluetoothDevice a, PairedBluetoothDevice b) {
  final byName = a.label.toLowerCase().compareTo(b.label.toLowerCase());
  if (byName != 0) {
    return byName;
  }
  return a.address.compareTo(b.address);
}
