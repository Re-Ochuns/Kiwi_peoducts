final _receivingLotRoute = RegExp(
  r'^/sorting/([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$',
  caseSensitive: false,
);

String? sortingLotIdFromRoute(String? route) {
  if (route == null) return null;
  return _receivingLotRoute.firstMatch(route)?.group(1);
}

String receivingSortingLink(Uri base, String receivingLotId) {
  if (_receivingLotRoute.firstMatch('/sorting/$receivingLotId') == null) {
    throw ArgumentError.value(receivingLotId, 'receivingLotId');
  }
  return '${base.origin}/sorting/$receivingLotId';
}

String? appInitialRoute(Uri uri) {
  final route = uri.fragment.startsWith('/') ? uri.fragment : uri.path;
  if (RegExp(r'^/work-tasks/[^/?#]+$').hasMatch(route) ||
      sortingLotIdFromRoute(route) != null) {
    return route;
  }
  return null;
}
