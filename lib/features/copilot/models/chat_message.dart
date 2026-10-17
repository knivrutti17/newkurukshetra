import 'copilot_tool_result.dart';

enum ChatAuthor { user, copilot }

/// A persisted (or in-flight) chat message.
///
/// Tool results contain only the role-authorized data returned for this
/// request. They are kept alongside the response so a reopened conversation
/// can show the exact source, filters, and calculation that informed it.
class ChatMessage {
  const ChatMessage({
    required this.author,
    required this.text,
    this.id,
    this.conversationId,
    this.createdAt,
    this.toolResults = const <CopilotToolResult>[],
    this.isError = false,
    this.retryPrompt,
  });

  final String? id;
  final String? conversationId;
  final ChatAuthor author;
  final String text;
  final DateTime? createdAt;
  final List<CopilotToolResult> toolResults;
  final bool isError;
  final String? retryPrompt;

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? text,
    DateTime? createdAt,
    List<CopilotToolResult>? toolResults,
    bool? isError,
    String? retryPrompt,
  }) => ChatMessage(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    author: author,
    text: text ?? this.text,
    createdAt: createdAt ?? this.createdAt,
    toolResults: toolResults ?? this.toolResults,
    isError: isError ?? this.isError,
    retryPrompt: retryPrompt ?? this.retryPrompt,
  );
}
