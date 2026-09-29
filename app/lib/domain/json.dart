DateTime? parseDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();

String? encodeDate(DateTime? value) => value?.toUtc().toIso8601String();
