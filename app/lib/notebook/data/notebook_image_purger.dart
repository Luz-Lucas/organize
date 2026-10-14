/// Implementado pelos stores de imagem que sabem apagar todas as imagens de um
/// caderno (ao excluí-lo). O banco apaga as páginas em cascata, mas os arquivos do
/// Storage só saem pela API do Storage.
abstract interface class NotebookImagePurger {
  Future<void> purgeAll();
}
