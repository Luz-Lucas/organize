import 'dart:io';

/// Trava simples: só uma sincronização por vez.
abstract interface class SyncLock {
  /// true se conseguiu a trava; false se outra execução a tem.
  Future<bool> tryAcquire();

  /// Solta a trava (só se esta instância a tinha).
  Future<void> release();
}

class MemorySyncLock implements SyncLock {
  bool _held = false;

  @override
  Future<bool> tryAcquire() async {
    if (_held) return false;
    return _held = true;
  }

  @override
  Future<void> release() async => _held = false;
}

/// Trava em arquivo: vale entre o app e a tarefa em segundo plano (isolates diferentes). Criar o arquivo é
/// atômico (`exclusive`). Uma trava mais velha que [staleAfter] é de um processo que morreu e pode ser retomada.
class FileSyncLock implements SyncLock {
  FileSyncLock(this._file, {DateTime Function()? now, this.staleAfter = const Duration(minutes: 15)}) : _now = now ?? DateTime.now;

  final File _file;
  final DateTime Function() _now;
  final Duration staleAfter;
  bool _held = false;

  bool _create() {
    try {
      _file.createSync(exclusive: true, recursive: true);
      _file.writeAsStringSync('${_now().millisecondsSinceEpoch}');
      return true;
    } on FileSystemException {
      return false;
    }
  }

  bool _isStale() {
    try {
      final at = int.tryParse(_file.readAsStringSync().trim());
      if (at == null) return true;
      return _now().difference(DateTime.fromMillisecondsSinceEpoch(at)) > staleAfter;
    } on FileSystemException {
      return false; // sumiu agora: a próxima tentativa decide
    }
  }

  @override
  Future<bool> tryAcquire() async {
    if (_held) return false;
    if (_create()) return _held = true;
    if (!_isStale()) return false;
    try {
      _file.deleteSync();
    } on FileSystemException {
      return false;
    }
    return _held = _create();
  }

  @override
  Future<void> release() async {
    if (!_held) return;
    _held = false;
    try {
      _file.deleteSync();
    } on FileSystemException {
      // já removida
    }
  }
}
