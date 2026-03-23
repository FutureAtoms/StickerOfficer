import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  final root = Directory.current;
  final reportFile = File(
    '${root.path}/docs/release/readiness-2026-03-22.json',
  );

  if (!reportFile.existsSync()) {
    stderr.writeln('Missing report file: ${reportFile.path}');
    exitCode = 1;
    return;
  }

  final report =
      jsonDecode(await reportFile.readAsString()) as Map<String, dynamic>;
  final artifacts = _resolveArtifacts(root, report);

  final server = await HttpServer.bind(config.host, config.port);
  final lanUrls = await _lanUrls(config.host, config.port);

  stdout.writeln('StickerOfficer Local Release Hub');
  stdout.writeln('Dashboard: http://${config.host}:${config.port}/');
  if (lanUrls.isNotEmpty) {
    stdout.writeln('LAN URLs:');
    for (final url in lanUrls) {
      stdout.writeln('  $url');
    }
  }
  stdout.writeln('Android direct APK link (if present):');
  final preferredArtifact = artifacts.cast<_Artifact?>().firstWhere(
    (artifact) => artifact?.recommended == true,
    orElse: () => null,
  );
  if (preferredArtifact != null && preferredArtifact.exists) {
    stdout.writeln(
      '  http://${config.host}:${config.port}/downloads/${preferredArtifact.fileName}',
    );
  } else {
    stdout.writeln('  Preferred Android artifact not found yet.');
  }

  await for (final request in server) {
    try {
      await _handleRequest(
        request: request,
        report: report,
        artifacts: artifacts,
        lanUrls: lanUrls,
      );
    } catch (error, stackTrace) {
      stderr.writeln('Request failure: $error');
      stderr.writeln(stackTrace);
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.text
        ..write('Internal server error')
        ..close();
    }
  }
}

class _Config {
  const _Config({required this.host, required this.port});

  final String host;
  final int port;
}

class _Artifact {
  const _Artifact({
    required this.label,
    required this.relativePath,
    required this.platform,
    required this.installable,
    required this.recommended,
    required this.notes,
    required this.file,
    required this.exists,
    required this.sizeBytes,
  });

  final String label;
  final String relativePath;
  final String platform;
  final bool installable;
  final bool recommended;
  final String notes;
  final File file;
  final bool exists;
  final int? sizeBytes;

  String get fileName => file.uri.pathSegments.last;

  String get humanSize {
    final bytes = sizeBytes;
    if (bytes == null) return 'missing';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unitIndex]}';
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'relativePath': relativePath,
    'platform': platform,
    'installable': installable,
    'recommended': recommended,
    'notes': notes,
    'exists': exists,
    'sizeBytes': sizeBytes,
    'humanSize': humanSize,
    'downloadPath': exists ? '/downloads/$fileName' : null,
  };
}

_Config _parseArgs(List<String> args) {
  var host = '0.0.0.0';
  var port = 8787;

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == '--host' && index + 1 < args.length) {
      host = args[++index];
    } else if (arg == '--port' && index + 1 < args.length) {
      port = int.tryParse(args[++index]) ?? port;
    }
  }

  return _Config(host: host, port: port);
}

List<_Artifact> _resolveArtifacts(Directory root, Map<String, dynamic> report) {
  final rawArtifacts =
      (report['artifacts'] as List<dynamic>).cast<Map<String, dynamic>>();
  return rawArtifacts.map((raw) {
    final relativePath = raw['path'] as String;
    final file = File('${root.path}/$relativePath');
    final exists = file.existsSync();
    final sizeBytes = exists ? file.lengthSync() : null;

    return _Artifact(
      label: raw['label'] as String,
      relativePath: relativePath,
      platform: raw['platform'] as String,
      installable: raw['installable'] as bool? ?? false,
      recommended: raw['recommended'] as bool? ?? false,
      notes: raw['notes'] as String? ?? '',
      file: file,
      exists: exists,
      sizeBytes: sizeBytes,
    );
  }).toList();
}

Future<List<String>> _lanUrls(String host, int port) async {
  if (host != '0.0.0.0') {
    return ['http://$host:$port/'];
  }

  final interfaces = await NetworkInterface.list(
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  );

  final urls = <String>{};
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      final ip = address.address;
      if (ip.startsWith('127.')) continue;
      urls.add('http://$ip:$port/');
    }
  }

  return urls.toList()..sort();
}

Future<void> _handleRequest({
  required HttpRequest request,
  required Map<String, dynamic> report,
  required List<_Artifact> artifacts,
  required List<String> lanUrls,
}) async {
  final path = request.uri.path;

  if (path == '/' || path == '/index.html') {
    final html = _buildHtml(
      report: report,
      artifacts: artifacts,
      lanUrls: lanUrls,
    );
    request.response.headers.contentType = ContentType.html;
    request.response.write(html);
    await request.response.close();
    return;
  }

  if (path == '/api/report.json') {
    final merged =
        Map<String, dynamic>.from(report)
          ..['servedAt'] = DateTime.now().toIso8601String()
          ..['artifactsResolved'] =
              artifacts.map((artifact) => artifact.toJson()).toList()
          ..['lanUrls'] = lanUrls;
    request.response.headers.contentType = ContentType.json;
    request.response.write(const JsonEncoder.withIndent('  ').convert(merged));
    await request.response.close();
    return;
  }

  if (path.startsWith('/downloads/')) {
    final requestedName = path.substring('/downloads/'.length);
    final artifact = artifacts.cast<_Artifact?>().firstWhere(
      (candidate) => candidate?.fileName == requestedName,
      orElse: () => null,
    );

    if (artifact == null || !artifact.exists) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.text
        ..write('Artifact not found')
        ..close();
      return;
    }

    request.response.headers
      ..contentType = _contentTypeForFile(artifact.fileName)
      ..set(
        'content-disposition',
        'attachment; filename="${artifact.fileName}"',
      );
    await artifact.file.openRead().pipe(request.response);
    return;
  }

  request.response
    ..statusCode = HttpStatus.notFound
    ..headers.contentType = ContentType.text
    ..write('Not found')
    ..close();
}

ContentType _contentTypeForFile(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.apk')) {
    return ContentType('application', 'vnd.android.package-archive');
  }
  if (lower.endsWith('.aab')) {
    return ContentType('application', 'octet-stream');
  }
  if (lower.endsWith('.ipa')) {
    return ContentType('application', 'octet-stream');
  }
  return ContentType.binary;
}

String _buildHtml({
  required Map<String, dynamic> report,
  required List<_Artifact> artifacts,
  required List<String> lanUrls,
}) {
  final app = report['app'] as Map<String, dynamic>;
  final verification =
      (report['verification'] as List<dynamic>).cast<Map<String, dynamic>>();
  final features =
      (report['features'] as List<dynamic>).cast<Map<String, dynamic>>();
  final blockers =
      (report['blockers'] as List<dynamic>).cast<Map<String, dynamic>>();
  final launchPlan =
      (report['launchPlan'] as List<dynamic>).cast<Map<String, dynamic>>();

  String statusChip(String status) {
    final normalized = status.toLowerCase();
    final color = switch (normalized) {
      'passed' || 'verified' => '#14532d',
      'warning' ||
      'partially_ready' ||
      'verified_in_tests' ||
      'build_verified_needs_device' ||
      'limited' => '#854d0e',
      _ => '#7f1d1d',
    };
    return '<span class="chip" style="border-color:$color;color:$color;">${_escape(status)}</span>';
  }

  final executiveSummary =
      (report['executiveSummary'] as List<dynamic>)
          .map((item) => '<li>${_escape(item.toString())}</li>')
          .join();

  final artifactCards =
      artifacts.map((artifact) {
        final action =
            artifact.exists
                ? '<a class="button" href="/downloads/${artifact.fileName}">Download</a>'
                : '<span class="muted">Missing</span>';
        final recommended =
            artifact.recommended
                ? '<span class="chip" style="border-color:#1d4ed8;color:#1d4ed8;">recommended</span>'
                : '';
        return '''
      <article class="card">
        <div class="row">
          <h3>${_escape(artifact.label)}</h3>
          <div class="row">$recommended ${statusChip(artifact.exists ? 'ready' : 'missing')}</div>
        </div>
        <p class="meta">${_escape(artifact.relativePath)}</p>
        <p>${_escape(artifact.notes)}</p>
        <p class="meta">Size: ${_escape(artifact.humanSize)} | Platform: ${_escape(artifact.platform)} | Installable: ${artifact.installable ? 'yes' : 'no'}</p>
        <div class="row">$action</div>
      </article>
    ''';
      }).join();

  final verificationRows =
      verification.map((item) {
        return '''
      <tr>
        <td>${_escape(item['name'].toString())}</td>
        <td>${statusChip(item['status'].toString())}</td>
        <td>${_escape(item['details'].toString())}</td>
      </tr>
    ''';
      }).join();

  final featureRows =
      features.map((item) {
        return '''
      <tr>
        <td>${_escape(item['name'].toString())}</td>
        <td>${statusChip(item['status'].toString())}</td>
        <td>${_escape(item['evidence'].toString())}</td>
      </tr>
    ''';
      }).join();

  final blockerCards =
      blockers.map((item) {
        final severity = item['severity'].toString();
        return '''
      <article class="card">
        <div class="row">
          <h3>${_escape(item['title'].toString())}</h3>
          ${statusChip(severity)}
        </div>
        <p>${_escape(item['details'].toString())}</p>
      </article>
    ''';
      }).join();

  final planCards =
      launchPlan.map((phase) {
        final items =
            (phase['items'] as List<dynamic>)
                .map((item) => '<li>${_escape(item.toString())}</li>')
                .join();
        return '''
      <article class="card">
        <h3>${_escape(phase['phase'].toString())}</h3>
        <ul>$items</ul>
      </article>
    ''';
      }).join();

  final lanLinks =
      lanUrls.isEmpty
          ? '<li>LAN address not detected. Use the host and port you started the server with.</li>'
          : lanUrls.map((url) => '<li><a href="$url">$url</a></li>').join();

  final overallStatus = report['overallStatus'].toString();

  return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_escape(app['name'].toString())} Local Release Hub</title>
  <style>
    :root {
      --bg: #f5efe6;
      --paper: #fffdf9;
      --ink: #1f2937;
      --muted: #6b7280;
      --line: #e5dccf;
      --accent: #0f766e;
      --accent-2: #b45309;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Avenir Next", "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at top left, rgba(15,118,110,0.10), transparent 28%),
        radial-gradient(circle at top right, rgba(180,83,9,0.12), transparent 24%),
        linear-gradient(180deg, #f9f5ef 0%, var(--bg) 100%);
    }
    .wrap {
      max-width: 1180px;
      margin: 0 auto;
      padding: 32px 20px 56px;
    }
    .hero {
      background: linear-gradient(135deg, rgba(255,255,255,0.94), rgba(255,248,240,0.96));
      border: 1px solid var(--line);
      border-radius: 28px;
      padding: 28px;
      box-shadow: 0 18px 40px rgba(31,41,55,0.08);
    }
    h1, h2, h3 { margin: 0 0 10px; }
    h1 { font-size: clamp(2rem, 3vw, 3.1rem); line-height: 1; }
    h2 { font-size: 1.35rem; margin-top: 28px; }
    h3 { font-size: 1rem; }
    p, li, td, th { line-height: 1.5; }
    .meta, .muted { color: var(--muted); }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 16px;
      margin-top: 16px;
    }
    .card {
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 22px;
      padding: 18px;
      box-shadow: 0 12px 28px rgba(31,41,55,0.05);
    }
    .row {
      display: flex;
      gap: 10px;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
    }
    .chip {
      display: inline-flex;
      align-items: center;
      border: 1px solid currentColor;
      border-radius: 999px;
      padding: 4px 10px;
      font-size: 0.82rem;
      text-transform: lowercase;
      background: rgba(255,255,255,0.8);
    }
    .button {
      display: inline-block;
      text-decoration: none;
      color: white;
      background: linear-gradient(135deg, var(--accent), #115e59);
      border-radius: 999px;
      padding: 10px 16px;
      font-weight: 700;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 22px;
      overflow: hidden;
      box-shadow: 0 12px 28px rgba(31,41,55,0.05);
    }
    th, td {
      text-align: left;
      padding: 14px 16px;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
    }
    th {
      background: rgba(15,118,110,0.08);
      font-size: 0.9rem;
    }
    tr:last-child td { border-bottom: none; }
    ul { margin: 10px 0 0 18px; padding: 0; }
    a { color: var(--accent); }
    .pillbar {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin: 14px 0 0;
    }
    .band {
      margin-top: 20px;
      padding: 14px 16px;
      border-radius: 18px;
      background: rgba(180,83,9,0.08);
      border: 1px solid rgba(180,83,9,0.18);
    }
  </style>
</head>
<body>
  <div class="wrap">
    <section class="hero">
      <div class="row">
        <div>
          <p class="meta">${_escape(app['name'].toString())} ${_escape(app['version'].toString())}</p>
          <h1>Local Release Hub</h1>
          <p>Assessment date: ${_escape(report['assessedOn'].toString())}</p>
        </div>
        ${statusChip(overallStatus)}
      </div>
      <div class="band">
        <strong>Current verdict:</strong>
        this repo builds and tests well enough to continue hardening, but it is not yet ready for Play Store or App Store submission.
      </div>
      <div class="pillbar">
        <span class="chip" style="border-color:#1d4ed8;color:#1d4ed8;">Android local install ready</span>
        <span class="chip" style="border-color:#854d0e;color:#854d0e;">iOS signing still required</span>
        <span class="chip" style="border-color:#7f1d1d;color:#7f1d1d;">Backend wiring incomplete</span>
      </div>
      <h2>Executive Summary</h2>
      <ul>$executiveSummary</ul>
    </section>

    <h2>Same-Wi-Fi Access</h2>
    <div class="card">
      <p>Open this dashboard from another device on the same Wi-Fi using one of these URLs:</p>
      <ul>$lanLinks</ul>
      <p class="muted">For Android, download the recommended arm64 APK below. For iPhone, this dashboard will only become install-ready after a signed IPA and OTA manifest are added.</p>
    </div>

    <h2>Artifacts</h2>
    <div class="grid">$artifactCards</div>

    <h2>Verification</h2>
    <table>
      <thead>
        <tr>
          <th>Check</th>
          <th>Status</th>
          <th>Details</th>
        </tr>
      </thead>
      <tbody>$verificationRows</tbody>
    </table>

    <h2>Feature Status</h2>
    <table>
      <thead>
        <tr>
          <th>Feature</th>
          <th>Status</th>
          <th>Evidence</th>
        </tr>
      </thead>
      <tbody>$featureRows</tbody>
    </table>

    <h2>Blockers</h2>
    <div class="grid">$blockerCards</div>

    <h2>Launch Plan</h2>
    <div class="grid">$planCards</div>

    <h2>Machine-readable Report</h2>
    <div class="card">
      <p>JSON report: <a href="/api/report.json">/api/report.json</a></p>
    </div>
  </div>
</body>
</html>
''';
}

String _escape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
