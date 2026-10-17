class CopilotActionPreview {
  const CopilotActionPreview({
    required this.type,
    required this.title,
    required this.description,
    required this.payload,
  });

  final String type;
  final String title;
  final String description;
  final Map<String, Object?> payload;

  Map<String, Object?> toMap() => <String, Object?>{
    'type': type,
    'title': title,
    'description': description,
    'payload': payload,
  };

  factory CopilotActionPreview.fromMap(Map<String, dynamic> map) =>
      CopilotActionPreview(
        type: map['type'] as String? ?? '',
        title: map['title'] as String? ?? 'Action preview',
        description: map['description'] as String? ?? '',
        payload: _objectMap(map['payload']),
      );
}

/// Explainable output from one controlled Copilot tool invocation.
class CopilotToolResult {
  const CopilotToolResult({
    required this.queryId,
    required this.source,
    required this.summary,
    required this.filters,
    this.rows = const <Map<String, Object?>>[],
    this.calculation,
    this.actionPreview,
  });

  final String queryId;
  final String source;
  final String summary;
  final Map<String, Object?> filters;
  final List<Map<String, Object?>> rows;
  final String? calculation;
  final CopilotActionPreview? actionPreview;

  Map<String, Object?> toFunctionResponse() => <String, Object?>{
    'query_id': queryId,
    'source': source,
    'summary': summary,
    'filters': filters,
    'calculation': calculation,
    'rows': rows,
    if (actionPreview != null) 'action_preview': actionPreview!.toMap(),
  };

  Map<String, Object?> toFirestore() => <String, Object?>{
    'queryId': queryId,
    'source': source,
    'summary': summary,
    'filters': filters,
    'rows': rows,
    if (calculation != null) 'calculation': calculation,
    if (actionPreview != null) 'actionPreview': actionPreview!.toMap(),
  };

  factory CopilotToolResult.fromFirestore(Map<String, dynamic> map) =>
      CopilotToolResult(
        queryId: map['queryId'] as String? ?? 'unknown_query',
        source: map['source'] as String? ?? 'Unknown source',
        summary: map['summary'] as String? ?? '',
        filters: _objectMap(map['filters']),
        rows: _objectRows(map['rows']),
        calculation: map['calculation'] as String?,
        actionPreview: map['actionPreview'] is Map
            ? CopilotActionPreview.fromMap(
                Map<String, dynamic>.from(map['actionPreview'] as Map),
              )
            : null,
      );
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _objectRows(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value
      .whereType<Map>()
      .map((row) => _objectMap(row))
      .toList(growable: false);
}
