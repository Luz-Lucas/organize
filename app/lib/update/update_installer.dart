import 'dart:io';

/// O que aconteceu ao pedir a instalação do pacote já baixado e conferido.
enum InstallResult {
  /// Android: o instalador do sistema foi aberto; quem confirma é o usuário.
  started,

  /// Linux/Windows: a nova pasta está pronta e o script de troca foi disparado; o app precisa sair agora.
  restarting,

  /// Android: falta liberar "instalar apps desconhecidos" para o Organize.
  needsPermission,

  /// Não deu para instalar ([InstallOutcome.message] explica).
  failed,
}

class InstallOutcome {
  const InstallOutcome(this.result, [this.message]);

  final InstallResult result;

  /// Texto para o usuário (falha ou instrução de permissão).
  final String? message;
}

/// A parte da atualização que depende do sistema: onde guardar o pacote e como instalá-lo.
abstract interface class UpdateInstaller {
  /// Este aparelho sabe se atualizar? (Android, Linux e Windows)
  bool get supported;

  /// Plataforma na tabela `app_releases`: `android`, `linux` ou `windows` (vazio quando não há suporte).
  String get platform;

  /// Pasta onde o pacote baixado deve ficar.
  Future<Directory> downloadDir();

  /// Instala [package] (já conferido por SHA-256). [promptForPermission] false evita abrir os ajustes do
  /// sistema de novo (usado ao retomar o app depois de o usuário voltar dos ajustes).
  Future<InstallOutcome> install(File package, {bool promptForPermission = true});
}

/// Sem atualização (testes, web, iOS...).
class NoopUpdateInstaller implements UpdateInstaller {
  const NoopUpdateInstaller();

  @override
  bool get supported => false;
  @override
  String get platform => '';
  @override
  Future<Directory> downloadDir() async => Directory.systemTemp;
  @override
  Future<InstallOutcome> install(File package, {bool promptForPermission = true}) async =>
      const InstallOutcome(InstallResult.failed, 'Atualização não disponível neste aparelho.');
}

typedef RunProcess = Future<ProcessResult> Function(String executable, List<String> arguments);
typedef StartDetached = Future<void> Function(String executable, List<String> arguments);

Future<ProcessResult> runProcess(String executable, List<String> arguments) =>
    Process.run(executable, arguments);

Future<void> startDetached(String executable, List<String> arguments) async {
  await Process.start(executable, arguments, mode: ProcessStartMode.detached);
}

/// Nome do arquivo de [path] (aceita `/` e `\`).
String baseName(String path) => path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

/// Pasta que contém [path] (sem barra no fim).
String parentOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i <= 0 ? path.substring(0, i < 0 ? 0 : 1) : path.substring(0, i);
}

const unsafePackageMessage = 'O pacote de atualização tem um caminho inseguro e foi recusado. Nada foi instalado.';
const corruptPackageMessage = 'O pacote de atualização está corrompido. Nada foi instalado.';
