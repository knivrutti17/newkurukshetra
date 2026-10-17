class CopilotConversation {
  const CopilotConversation({
    required this.id,
    required this.userId,
    required this.instituteId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessagePreview = '',
  });

  final String id;
  final String userId;
  final String instituteId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastMessagePreview;

  CopilotConversation copyWith({
    String? title,
    DateTime? updatedAt,
    String? lastMessagePreview,
  }) => CopilotConversation(
    id: id,
    userId: userId,
    instituteId: instituteId,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
  );
}
