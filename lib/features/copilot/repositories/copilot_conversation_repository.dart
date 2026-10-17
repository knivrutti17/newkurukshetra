import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/models/app_user.dart';
import '../models/chat_message.dart';
import '../models/copilot_conversation.dart';
import '../models/copilot_tool_result.dart';

/// Firestore persistence for Copilot conversations.
///
/// Every read and write rechecks the conversation owner and institute in the
/// document. Firestore rules must mirror these checks in production; client
/// checks alone are not a security boundary.
class CopilotConversationRepository {
  CopilotConversationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('copilotConversations');

  Stream<List<CopilotConversation>> watchForUser(AppUser user) => _conversations
      .where('userId', isEqualTo: user.id)
      .limit(100)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs
                .map(_conversationFromDocument)
                .where((item) => item.instituteId == user.instituteId)
                .toList()
              ..sort(
                (left, right) => right.updatedAt.compareTo(left.updatedAt),
              ),
      );

  Future<CopilotConversation> create({
    required AppUser user,
    required String title,
  }) async {
    final now = DateTime.now();
    final doc = _conversations.doc();
    final conversation = CopilotConversation(
      id: doc.id,
      userId: user.id,
      instituteId: user.instituteId,
      title: _safeTitle(title),
      createdAt: now,
      updatedAt: now,
    );
    await doc.set(_conversationToFirestore(conversation));
    return conversation;
  }

  Future<void> rename({
    required AppUser user,
    required String conversationId,
    required String title,
  }) async {
    await _ensureOwner(user, conversationId);
    await _conversations.doc(conversationId).update(<String, Object?>{
      'title': _safeTitle(title),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<List<ChatMessage>> loadMessages({
    required AppUser user,
    required String conversationId,
    int limit = 80,
  }) async {
    await _ensureOwner(user, conversationId);
    final snapshot = await _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((document) => _messageFromDocument(document, conversationId))
        .toList()
        .reversed
        .toList(growable: false);
  }

  Future<ChatMessage> saveMessage({
    required AppUser user,
    required String conversationId,
    required ChatMessage message,
  }) async {
    await _ensureOwner(user, conversationId);
    final now = message.createdAt ?? DateTime.now();
    final doc = _conversations.doc(conversationId).collection('messages').doc();
    final saved = ChatMessage(
      id: doc.id,
      conversationId: conversationId,
      author: message.author,
      text: message.text.trim(),
      createdAt: now,
      toolResults: message.toolResults,
      isError: message.isError,
      retryPrompt: message.retryPrompt,
    );
    await _firestore.runTransaction((transaction) async {
      transaction.set(doc, _messageToFirestore(saved, user));
      transaction.update(_conversations.doc(conversationId), <String, Object?>{
        'updatedAt': Timestamp.fromDate(now),
        'lastMessagePreview': _preview(saved.text),
      });
    });
    return saved;
  }

  Future<void> _ensureOwner(AppUser user, String conversationId) async {
    final document = await _conversations.doc(conversationId).get();
    final data = document.data();
    if (!document.exists ||
        data == null ||
        data['userId'] != user.id ||
        data['instituteId'] != user.instituteId) {
      throw StateError('This Copilot conversation is not available to you.');
    }
  }

  CopilotConversation _conversationFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return CopilotConversation(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      instituteId: data['instituteId'] as String? ?? '',
      title: data['title'] as String? ?? 'New conversation',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      lastMessagePreview: data['lastMessagePreview'] as String? ?? '',
    );
  }

  ChatMessage _messageFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
    String conversationId,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawResults = data['toolResults'];
    final results = rawResults is List
        ? rawResults
              .whereType<Map>()
              .map(
                (item) => CopilotToolResult.fromFirestore(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
        : const <CopilotToolResult>[];
    return ChatMessage(
      id: document.id,
      conversationId: conversationId,
      author: data['author'] == 'user' ? ChatAuthor.user : ChatAuthor.copilot,
      text: data['text'] as String? ?? '',
      createdAt: _asDate(data['createdAt']),
      toolResults: results,
      isError: data['isError'] as bool? ?? false,
      retryPrompt: data['retryPrompt'] as String?,
    );
  }

  Map<String, Object?> _conversationToFirestore(CopilotConversation item) =>
      <String, Object?>{
        'userId': item.userId,
        'instituteId': item.instituteId,
        'title': item.title,
        'lastMessagePreview': item.lastMessagePreview,
        'createdAt': Timestamp.fromDate(item.createdAt),
        'updatedAt': Timestamp.fromDate(item.updatedAt),
      };

  Map<String, Object?> _messageToFirestore(ChatMessage item, AppUser user) =>
      <String, Object?>{
        'conversationId': item.conversationId,
        'userId': user.id,
        'instituteId': user.instituteId,
        'author': item.author == ChatAuthor.user ? 'user' : 'copilot',
        'text': item.text,
        'createdAt': Timestamp.fromDate(item.createdAt!),
        'toolResults': item.toolResults
            .map((result) => result.toFirestore())
            .toList(growable: false),
        'isError': item.isError,
        if (item.retryPrompt != null) 'retryPrompt': item.retryPrompt,
      };

  static DateTime _asDate(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.fromMillisecondsSinceEpoch(0);

  static String _safeTitle(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'New conversation';
    return normalized.length <= 72
        ? normalized
        : '${normalized.substring(0, 69)}...';
  }

  static String _preview(String value) =>
      value.length <= 180 ? value : '${value.substring(0, 177)}...';
}
