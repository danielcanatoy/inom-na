// Generates the IMedsU Android launcher icons (teal background, two-tone
// capsule) without extra dependencies. Run from the project root:
//   dart run tool/generate_launcher_icon.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _teal = [0x08, 0x7F, 0x8C];
const _white = [0xFF, 0xFF, 0xFF];
const _mint = [0xA7, 0xE3, 0xD5];
const _seam = [0x06, 0x5E, 0x68];

const _res = 'android/app/src/main/res';
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void main() {
  _densities.forEach((name, scale) {
    // Legacy icon (48dp): rounded teal square with the capsule.
    final legacy = (48 * scale).round();
    _write('$_res/mipmap-$name/ic_launcher.png',
        _render(legacy, background: true, capsuleLength: 0.62));
    // Adaptive foreground (108dp): capsule only, inside the 66dp safe zone.
    final adaptive = (108 * scale).round();
    _write('$_res/mipmap-$name/ic_launcher_foreground.png',
        _render(adaptive, background: false, capsuleLength: 0.50));
  });
  Directory('$_res/mipmap-anydpi-v26').createSync(recursive: true);
  File('$_res/mipmap-anydpi-v26/ic_launcher.xml')
      .writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');
  File('$_res/values/ic_launcher_background.xml')
      .writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#087F8C</color>
</resources>
''');
  stdout.writeln('Launcher icons generated.');
}

void _write(String path, Uint8List png) {
  File(path).writeAsBytesSync(png);
  stdout.writeln('  $path');
}

/// Renders an RGBA icon with 4x4 supersampling for smooth edges.
Uint8List _render(int size,
    {required bool background, required double capsuleLength}) {
  final rgba = Uint8List(size * size * 4);
  const samples = 4;
  final length = size * capsuleLength;
  final radius = length * 0.42 / 2; // Same proportions as the in-app mark.
  final halfSegment = length / 2 - radius;
  final seamHalfWidth = size * 0.012;
  final cornerRadius = size * 0.22;
  final margin = size * 0.04;
  const cos45 = math.sqrt1_2;

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          final px = x + (sx + 0.5) / samples - size / 2;
          final py = y + (sy + 0.5) / samples - size / 2;
          List<int>? color;
          if (background &&
              _insideRoundedSquare(px, py, size / 2 - margin, cornerRadius)) {
            color = _teal;
          }
          // Rotate into capsule space (capsule tilted 45° up to the right).
          final u = (px - py) * cos45;
          final v = (px + py) * cos45;
          final dx = math.max(u.abs() - halfSegment, 0.0);
          if (dx * dx + v * v <= radius * radius) {
            color = u.abs() <= seamHalfWidth ? _seam : (u < 0 ? _white : _mint);
          }
          if (color != null) {
            r += color[0];
            g += color[1];
            b += color[2];
            a += 1;
          }
        }
      }
      final i = (y * size + x) * 4;
      if (a > 0) {
        // Un-premultiplied average of covered samples.
        rgba[i] = (r / a).round();
        rgba[i + 1] = (g / a).round();
        rgba[i + 2] = (b / a).round();
        rgba[i + 3] = (a / (samples * samples) * 255).round();
      }
    }
  }
  return _encodePng(size, size, rgba);
}

bool _insideRoundedSquare(double x, double y, double half, double corner) {
  final qx = x.abs() - (half - corner);
  final qy = y.abs() - (half - corner);
  if (qx <= 0 || qy <= 0) return x.abs() <= half && y.abs() <= half;
  return qx * qx + qy * qy <= corner * corner;
}

Uint8List _encodePng(int width, int height, Uint8List rgba) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // Filter: none.
    raw.add(rgba.sublist(y * width * 4, (y + 1) * width * 4));
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // Bit depth.
    ..setUint8(9, 6) // Color type: RGBA.
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', header.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(ZLibCodec().encode(raw.toBytes())));
  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = type.codeUnits;
  out.add(_uint32(data.length));
  out.add(typeBytes);
  out.add(data);
  out.add(_uint32(_crc32([...typeBytes, ...data])));
}

Uint8List _uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
