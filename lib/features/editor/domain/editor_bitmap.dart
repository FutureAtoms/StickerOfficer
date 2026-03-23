import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

class SelectionMask {
  const SelectionMask({
    required this.width,
    required this.height,
    required this.values,
    required this.bounds,
    required this.polygon,
  });

  final int width;
  final int height;
  final Uint8List values;
  final Rect bounds;
  final List<Offset> polygon;

  bool contains(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return false;
    }
    return values[y * width + x] > 0;
  }

  bool get isEmpty => values.every((value) => value == 0);
}

class BackgroundRemovalResult {
  const BackgroundRemovalResult({
    required this.image,
    required this.removedPixels,
  });

  final img.Image image;
  final int removedPixels;
}

SelectionMask? buildSelectionMask({
  required int width,
  required int height,
  required List<Offset> polygon,
}) {
  if (polygon.length < 3 || width <= 0 || height <= 0) {
    return null;
  }

  final normalizedPolygon = polygon
      .map(
        (point) => Offset(
          point.dx.clamp(0.0, width - 1.0).toDouble(),
          point.dy.clamp(0.0, height - 1.0).toDouble(),
        ),
      )
      .toList(growable: false);

  double minX = normalizedPolygon.first.dx;
  double maxX = normalizedPolygon.first.dx;
  double minY = normalizedPolygon.first.dy;
  double maxY = normalizedPolygon.first.dy;
  for (final point in normalizedPolygon.skip(1)) {
    minX = math.min(minX, point.dx);
    maxX = math.max(maxX, point.dx);
    minY = math.min(minY, point.dy);
    maxY = math.max(maxY, point.dy);
  }

  final left = minX.floor().clamp(0, width - 1).toInt();
  final top = minY.floor().clamp(0, height - 1).toInt();
  final right = maxX.ceil().clamp(0, width - 1).toInt();
  final bottom = maxY.ceil().clamp(0, height - 1).toInt();

  final values = Uint8List(width * height);
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      final center = Offset(x + 0.5, y + 0.5);
      if (_isInsidePolygon(center, normalizedPolygon)) {
        values[y * width + x] = 255;
      }
    }
  }

  return SelectionMask(
    width: width,
    height: height,
    values: values,
    bounds: Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      (right + 1).toDouble(),
      (bottom + 1).toDouble(),
    ),
    polygon: normalizedPolygon,
  );
}

img.Image applyStrokeToBitmap({
  required img.Image source,
  required List<Offset> points,
  required double size,
  required img.Color color,
  required bool erase,
  SelectionMask? selectionMask,
}) {
  if (points.isEmpty) {
    return img.Image.from(source);
  }

  final output = img.Image.from(source);
  final smoothed = _smoothPoints(points);
  final step = math.max(0.75, size * 0.22);
  final radius = math.max(1.0, size / 2);

  for (var i = 0; i < smoothed.length - 1; i++) {
    final start = smoothed[i];
    final end = smoothed[i + 1];
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final segments = math.max(1, (distance / step).ceil());
    for (var segment = 0; segment <= segments; segment++) {
      final t = segment / segments;
      final sample = Offset(start.dx + dx * t, start.dy + dy * t);
      _stampCircle(
        output,
        center: sample,
        radius: radius,
        color: color,
        erase: erase,
        selectionMask: selectionMask,
      );
    }
  }

  if (smoothed.length == 1) {
    _stampCircle(
      output,
      center: smoothed.first,
      radius: radius,
      color: color,
      erase: erase,
      selectionMask: selectionMask,
    );
  }

  return output;
}

img.Image eraseSelection(img.Image source, SelectionMask selectionMask) {
  final output = img.Image.from(source);
  for (var y = 0; y < output.height; y++) {
    for (var x = 0; x < output.width; x++) {
      if (!selectionMask.contains(x, y)) {
        continue;
      }
      output.getPixel(x, y).setRgba(0, 0, 0, 0);
    }
  }
  return output;
}

img.Image keepSelection(img.Image source, SelectionMask selectionMask) {
  final output = img.Image.from(source);
  for (var y = 0; y < output.height; y++) {
    for (var x = 0; x < output.width; x++) {
      if (selectionMask.contains(x, y)) {
        continue;
      }
      output.getPixel(x, y).setRgba(0, 0, 0, 0);
    }
  }
  return output;
}

img.Image cropBitmap(img.Image source, Rect cropRect) {
  final x = cropRect.left.round().clamp(0, source.width - 1).toInt();
  final y = cropRect.top.round().clamp(0, source.height - 1).toInt();
  final width = cropRect.width.round().clamp(1, source.width - x).toInt();
  final height = cropRect.height.round().clamp(1, source.height - y).toInt();
  return img.copyCrop(source, x: x, y: y, width: width, height: height);
}

BackgroundRemovalResult removeBackgroundFromEdges(
  img.Image source, {
  required int tolerance,
}) {
  final output = img.Image.from(source);
  final width = output.width;
  final height = output.height;
  final visited = Uint8List(width * height);
  final removed = Uint8List(width * height);
  final queue = Queue<_PixelRef>();
  final borderSamples = _borderSamples(source);
  if (borderSamples.isEmpty) {
    return BackgroundRemovalResult(image: output, removedPixels: 0);
  }

  final borderMedian = _medianRgb(borderSamples);
  final globalTolerance = tolerance * 2.2;
  final localTolerance = tolerance * 1.1;

  void addSeed(int x, int y) {
    final index = y * width + x;
    if (visited[index] == 1) {
      return;
    }
    final pixel = source.getPixel(x, y);
    if (pixel.a <= 8) {
      visited[index] = 1;
      removed[index] = 1;
      queue.add(
        _PixelRef(x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()),
      );
      return;
    }
    if (_rgbDistance(
          pixel.r,
          pixel.g,
          pixel.b,
          borderMedian.$1,
          borderMedian.$2,
          borderMedian.$3,
        ) <=
        globalTolerance) {
      visited[index] = 1;
      removed[index] = 1;
      queue.add(
        _PixelRef(x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()),
      );
    }
  }

  for (var x = 0; x < width; x++) {
    addSeed(x, 0);
    addSeed(x, height - 1);
  }
  for (var y = 0; y < height; y++) {
    addSeed(0, y);
    addSeed(width - 1, y);
  }

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    for (final (dx, dy) in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
      final nx = current.x + dx;
      final ny = current.y + dy;
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
        continue;
      }
      final index = ny * width + nx;
      if (visited[index] == 1) {
        continue;
      }
      visited[index] = 1;
      final pixel = source.getPixel(nx, ny);
      if (pixel.a <= 8) {
        removed[index] = 1;
        queue.add(
          _PixelRef(nx, ny, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()),
        );
        continue;
      }

      final globalMatch =
          _rgbDistance(
            pixel.r,
            pixel.g,
            pixel.b,
            borderMedian.$1,
            borderMedian.$2,
            borderMedian.$3,
          ) <=
          globalTolerance;
      final localMatch =
          _rgbDistance(
            pixel.r,
            pixel.g,
            pixel.b,
            current.r,
            current.g,
            current.b,
          ) <=
          localTolerance;

      if (globalMatch ||
          (localMatch &&
              _pixelTouchesRemoved(removed, width, height, nx, ny))) {
        removed[index] = 1;
        queue.add(
          _PixelRef(nx, ny, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()),
        );
      }
    }
  }

  final refined = _refineBackgroundMask(removed, width: width, height: height);

  var removedPixels = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      final pixel = output.getPixel(x, y);
      if (refined[index] == 1) {
        pixel.setRgba(0, 0, 0, 0);
        removedPixels++;
        continue;
      }

      final softNeighbors = _removedNeighborCount(refined, width, height, x, y);
      if (softNeighbors == 0) {
        continue;
      }

      final fade = switch (softNeighbors) {
        <= 2 => 0.92,
        <= 4 => 0.74,
        _ => 0.58,
      };
      pixel.a = (pixel.a * fade).round();
    }
  }

  return BackgroundRemovalResult(image: output, removedPixels: removedPixels);
}

bool _isInsidePolygon(Offset point, List<Offset> polygon) {
  var intersections = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final pi = polygon[i];
    final pj = polygon[j];
    final intersects =
        ((pi.dy > point.dy) != (pj.dy > point.dy)) &&
        (point.dx <
            (pj.dx - pi.dx) * (point.dy - pi.dy) / ((pj.dy - pi.dy) + 1e-6) +
                pi.dx);
    if (intersects) {
      intersections = !intersections;
    }
  }
  return intersections;
}

List<Offset> _smoothPoints(List<Offset> points) {
  if (points.length < 3) {
    return List<Offset>.from(points, growable: false);
  }

  final smoothed = <Offset>[points.first];
  for (var index = 1; index < points.length - 1; index++) {
    final previous = points[index - 1];
    final current = points[index];
    final next = points[index + 1];
    smoothed.add(
      Offset(
        (previous.dx + current.dx * 2 + next.dx) / 4,
        (previous.dy + current.dy * 2 + next.dy) / 4,
      ),
    );
  }
  smoothed.add(points.last);
  return smoothed;
}

void _stampCircle(
  img.Image image, {
  required Offset center,
  required double radius,
  required img.Color color,
  required bool erase,
  SelectionMask? selectionMask,
}) {
  final feather = math.max(1.0, radius * 0.22);
  final left =
      (center.dx - radius - 1).floor().clamp(0, image.width - 1).toInt();
  final right =
      (center.dx + radius + 1).ceil().clamp(0, image.width - 1).toInt();
  final top =
      (center.dy - radius - 1).floor().clamp(0, image.height - 1).toInt();
  final bottom =
      (center.dy + radius + 1).ceil().clamp(0, image.height - 1).toInt();

  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      if (selectionMask != null && !selectionMask.contains(x, y)) {
        continue;
      }

      final distance = math.sqrt(
        math.pow(x + 0.5 - center.dx, 2) + math.pow(y + 0.5 - center.dy, 2),
      );
      if (distance > radius + feather) {
        continue;
      }

      final coverage = _falloff(distance, radius, feather);
      if (coverage <= 0) {
        continue;
      }

      final pixel = image.getPixel(x, y);
      if (erase) {
        pixel.a = (pixel.a * (1 - coverage)).round();
        if (pixel.a == 0) {
          pixel.setRgba(0, 0, 0, 0);
        }
        continue;
      }

      final overlayAlpha = color.aNormalized * coverage;
      final baseAlpha = pixel.aNormalized;
      final outAlpha = overlayAlpha + baseAlpha * (1 - overlayAlpha);
      if (outAlpha == 0) {
        continue;
      }

      final outR =
          (color.rNormalized * overlayAlpha +
              pixel.rNormalized * baseAlpha * (1 - overlayAlpha)) /
          outAlpha;
      final outG =
          (color.gNormalized * overlayAlpha +
              pixel.gNormalized * baseAlpha * (1 - overlayAlpha)) /
          outAlpha;
      final outB =
          (color.bNormalized * overlayAlpha +
              pixel.bNormalized * baseAlpha * (1 - overlayAlpha)) /
          outAlpha;

      pixel
        ..rNormalized = outR
        ..gNormalized = outG
        ..bNormalized = outB
        ..aNormalized = outAlpha;
    }
  }
}

double _falloff(double distance, double radius, double feather) {
  final hardRadius = math.max(0.0, radius - feather);
  if (distance <= hardRadius) {
    return 1;
  }
  if (distance >= radius + feather) {
    return 0;
  }
  final progress = (distance - hardRadius) / ((radius + feather) - hardRadius);
  return 1 - (progress * progress * (3 - 2 * progress));
}

List<(int, int, int)> _borderSamples(img.Image image) {
  final samples = <(int, int, int)>[];
  final step = math.max(1, math.min(image.width, image.height) ~/ 48);

  void maybeAdd(int x, int y) {
    final pixel = image.getPixel(x, y);
    if (pixel.a <= 8) {
      return;
    }
    samples.add((pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()));
  }

  for (var x = 0; x < image.width; x += step) {
    maybeAdd(x, 0);
    maybeAdd(x, image.height - 1);
  }
  for (var y = 0; y < image.height; y += step) {
    maybeAdd(0, y);
    maybeAdd(image.width - 1, y);
  }

  return samples;
}

(int, int, int) _medianRgb(List<(int, int, int)> samples) {
  final reds = samples.map((sample) => sample.$1).toList()..sort();
  final greens = samples.map((sample) => sample.$2).toList()..sort();
  final blues = samples.map((sample) => sample.$3).toList()..sort();
  final middle = samples.length ~/ 2;
  return (reds[middle], greens[middle], blues[middle]);
}

double _rgbDistance(num r1, num g1, num b1, num r2, num g2, num b2) {
  final dr = r1 - r2;
  final dg = g1 - g2;
  final db = b1 - b2;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

bool _pixelTouchesRemoved(
  Uint8List removed,
  int width,
  int height,
  int x,
  int y,
) {
  for (final (dx, dy) in const [
    (-1, -1),
    (0, -1),
    (1, -1),
    (-1, 0),
    (1, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
  ]) {
    final nx = x + dx;
    final ny = y + dy;
    if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
      continue;
    }
    if (removed[ny * width + nx] == 1) {
      return true;
    }
  }
  return false;
}

Uint8List _refineBackgroundMask(
  Uint8List removed, {
  required int width,
  required int height,
}) {
  final refined = Uint8List.fromList(removed);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final index = y * width + x;
      final neighbors = _removedNeighborCount(removed, width, height, x, y);
      if (removed[index] == 1 && neighbors <= 1) {
        refined[index] = 0;
      } else if (removed[index] == 0 && neighbors >= 6) {
        refined[index] = 1;
      }
    }
  }
  return refined;
}

int _removedNeighborCount(
  Uint8List removed,
  int width,
  int height,
  int x,
  int y,
) {
  var count = 0;
  for (final (dx, dy) in const [
    (-1, -1),
    (0, -1),
    (1, -1),
    (-1, 0),
    (1, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
  ]) {
    final nx = x + dx;
    final ny = y + dy;
    if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
      continue;
    }
    if (removed[ny * width + nx] == 1) {
      count++;
    }
  }
  return count;
}

class _PixelRef {
  const _PixelRef(this.x, this.y, this.r, this.g, this.b);

  final int x;
  final int y;
  final int r;
  final int g;
  final int b;
}
