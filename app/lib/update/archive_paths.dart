/// Validação dos nomes de entrada de pacotes de atualização (`.tar.gz` e `.zip`) antes de extrair:
/// nada de caminho absoluto, de `..` nem de nomes que o Windows trata de forma especial.
/// Mesmo com o SHA-256 conferido, extrair é o ponto em que um pacote ruim poderia escrever fora da pasta.
bool isSafeArchivePath(String name) {
  if (name.isEmpty || name.contains('\u0000')) return false;
  // Absoluto: começa com separador (inclui UNC `//servidor/...`) ou com letra de unidade (`C:`, `c:x`).
  if (name.startsWith('/') || name.startsWith(r'\')) return false;
  // Letra de unidade ou fluxo alternativo de dados do NTFS (`a.txt:stream`): dois-pontos nunca é aceito.
  if (name.contains(':')) return false;
  for (final part in name.split(RegExp(r'[\\/]'))) {
    if (part == '..') return false;
  }
  return true;
}

/// A primeira entrada insegura de [names], ou null se todas passam em [isSafeArchivePath].
String? validateArchiveEntries(Iterable<String> names) {
  for (final n in names) {
    if (!isSafeArchivePath(n)) return n;
  }
  return null;
}
