/// Traduz o link de toque nos widgets (`organizacional://agenda`) em rota.
String? routeForWidgetUri(Uri uri) {
  if (uri.scheme != 'organizacional') return null;
  switch (uri.host) {
    case 'agenda':
      return '/agenda';
    case 'tarefas':
      return '/tarefas';
  }
  return null;
}
