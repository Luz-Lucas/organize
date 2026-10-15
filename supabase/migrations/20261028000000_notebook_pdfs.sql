-- O caderno guarda o PDF original (para ler como livro e selecionar texto), no mesmo
-- bucket das imagens: mesmo caminho <user_id>/<note_id>/…, mesmas policies, e some
-- junto quando o caderno é excluído. Imagens continuam limitadas a 10 MB pelo app.
update storage.buckets
set file_size_limit = 52428800,
    allowed_mime_types = array[
      'image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/heic', 'image/heif', 'application/pdf'
    ]
where id = 'notebook-images';
