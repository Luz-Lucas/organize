import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/update/update_downloader.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('upd-dl-'));
  tearDown(() => dir.deleteSync(recursive: true));

  final bytes = List<int>.generate(300 * 1024, (i) => i % 251);
  final good = sha256.convert(bytes).toString();

  HttpUpdateDownloader downloaderFor(Stream<List<int>> Function() body, {int status = 200, int? length}) =>
      HttpUpdateDownloader(
        client: MockClient.streaming((req, _) async =>
            http.StreamedResponse(body(), status, contentLength: length ?? bytes.length)),
      );

  Stream<List<int>> chunks([List<int>? data]) async* {
    final d = data ?? bytes;
    for (var i = 0; i < d.length; i += 64 * 1024) {
      yield d.sublist(i, i + 64 * 1024 > d.length ? d.length : i + 64 * 1024);
    }
  }

  test('baixa em streaming, informa o progresso e entrega o arquivo conferido', () async {
    final progress = <(int, int)>[];
    final file = File('${dir.path}/pacote.apk');
    final out = await downloaderFor(chunks).download(
      url: Uri.parse('https://x.test/a'),
      target: file,
      sha256: good,
      size: bytes.length,
      onProgress: (r, t) => progress.add((r, t)),
    );
    expect(out.path, file.path);
    expect(await file.readAsBytes(), bytes);
    expect(progress.length, greaterThan(1));
    expect(progress.last, (bytes.length, bytes.length));
    expect(File('${file.path}.part').existsSync(), isFalse);
  });

  test('SHA-256 diferente: apaga o arquivo e explica o erro', () async {
    final file = File('${dir.path}/pacote.apk');
    await expectLater(
      downloaderFor(chunks).download(
          url: Uri.parse('https://x.test/a'), target: file, sha256: 'f' * 64, size: bytes.length),
      throwsA(isA<UpdateIntegrityException>().having((e) => e.message, 'message', contains('não confere'))),
    );
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.part').existsSync(), isFalse);
  });

  test('tamanho diferente do registrado: apaga e recusa', () async {
    final file = File('${dir.path}/pacote.apk');
    await expectLater(
      downloaderFor(() => chunks(bytes.sublist(0, 1000)), length: 1000).download(
          url: Uri.parse('https://x.test/a'), target: file, sha256: good, size: bytes.length),
      throwsA(isA<UpdateIntegrityException>()),
    );
    expect(file.existsSync(), isFalse);
  });

  test('para de ler quando passa do tamanho esperado (não baixa sem limite)', () async {
    final file = File('${dir.path}/pacote.apk');
    var pulled = 0;
    Stream<List<int>> endless() async* {
      while (pulled < 100 * 1024 * 1024) {
        pulled += 64 * 1024;
        yield List<int>.filled(64 * 1024, 7);
      }
    }

    await expectLater(
      downloaderFor(endless, length: 0).download(
          url: Uri.parse('https://x.test/a'), target: file, sha256: good, size: bytes.length),
      throwsA(isA<UpdateIntegrityException>()),
    );
    expect(pulled, lessThan(5 * 1024 * 1024));
    expect(file.existsSync(), isFalse);
  });

  test('HTTP diferente de 200 vira UpdateDownloadException', () async {
    await expectLater(
      downloaderFor(chunks, status: 403).download(
          url: Uri.parse('https://x.test/a'),
          target: File('${dir.path}/p.apk'),
          sha256: good,
          size: bytes.length),
      throwsA(isA<UpdateDownloadException>().having((e) => e.message, 'message', contains('403'))),
    );
  });

  test('cancelar no meio apaga o parcial e lança UpdateCancelled', () async {
    final gate = Completer<void>();
    Stream<List<int>> slow() async* {
      yield bytes.sublist(0, 64 * 1024);
      await gate.future; // trava aqui, como uma rede que parou
      yield bytes.sublist(64 * 1024);
    }

    final token = DownloadCancelToken();
    final file = File('${dir.path}/pacote.apk');
    final first = Completer<void>();
    final run = downloaderFor(slow).download(
      url: Uri.parse('https://x.test/a'),
      target: file,
      sha256: good,
      size: bytes.length,
      cancel: token,
      onProgress: (r, t) {
        if (!first.isCompleted) first.complete();
      },
    );
    final expectation = expectLater(run, throwsA(isA<UpdateCancelled>()));
    await first.future;
    token.cancel();
    await expectation;
    gate.complete();
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.part').existsSync(), isFalse);
  });

  test('falha de conexão no meio vira UpdateDownloadException e não deixa parcial', () async {
    Stream<List<int>> broken() async* {
      yield bytes.sublist(0, 64 * 1024);
      throw const SocketException('caiu');
    }

    final file = File('${dir.path}/pacote.apk');
    await expectLater(
      downloaderFor(broken).download(
          url: Uri.parse('https://x.test/a'), target: file, sha256: good, size: bytes.length),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(File('${file.path}.part').existsSync(), isFalse);
  });
}
