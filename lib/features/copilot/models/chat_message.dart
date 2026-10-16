enum ChatAuthor { user, copilot }

class ChatMessage {
  const ChatMessage({required this.author, required this.text});

  final ChatAuthor author;
  final String text;
}
