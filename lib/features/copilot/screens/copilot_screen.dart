import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/firebase_app_check_initializer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../models/chat_message.dart';
import '../models/copilot_conversation.dart';
import '../models/copilot_tool_result.dart';
import '../repositories/copilot_conversation_repository.dart';
import '../services/firebase_copilot_service.dart';

class CopilotScreen extends StatefulWidget {
  const CopilotScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<CopilotScreen> createState() => _CopilotScreenState();
}

class _CopilotScreenState extends State<CopilotScreen> {
  static const _suggestions = <String>[
    'Show students in the Java batch.',
    'Which students have attendance below 75%?',
    'Show today\'s trainer schedule.',
    'Find students who may need follow-up.',
  ];

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  late final CopilotConversationRepository _repository;
  late final FirebaseCopilotService _service;
  CopilotConversation? _activeConversation;
  List<ChatMessage> _messages = <ChatMessage>[];
  bool _isResponding = false;
  bool _isLoadingConversation = false;

  @override
  void initState() {
    super.initState();
    _repository = CopilotConversationRepository();
    _service = FirebaseCopilotService(user: widget.user);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestion]) async {
    final question = (suggestion ?? _inputController.text).trim();
    if (question.isEmpty || _isResponding || _isLoadingConversation) return;
    _inputController.clear();

    CopilotConversation conversation;
    try {
      conversation =
          _activeConversation ??
          await _repository.create(
            user: widget.user,
            title: _conversationTitle(question),
          );
    } catch (error) {
      _showError('Unable to start a saved conversation: $error');
      return;
    }
    if (!mounted) return;

    final message = ChatMessage(
      author: ChatAuthor.user,
      text: question,
      conversationId: conversation.id,
      createdAt: DateTime.now(),
    );
    setState(() {
      _activeConversation = conversation;
      _messages = <ChatMessage>[..._messages, message];
    });
    _scrollToLatest();

    try {
      final saved = await _repository.saveMessage(
        user: widget.user,
        conversationId: conversation.id,
        message: message,
      );
      if (!mounted) return;
      setState(() => _replaceLast(message, saved));
    } catch (error) {
      _showError('The question was not saved: $error');
      return;
    }
    await _requestResponse(question);
  }

  Future<void> _requestResponse(String question) async {
    final conversation = _activeConversation;
    if (conversation == null || _isResponding) return;
    final history = List<ChatMessage>.from(_messages);
    if (history.isNotEmpty &&
        history.last.author == ChatAuthor.user &&
        history.last.text == question) {
      history.removeLast();
    }
    final pending = ChatMessage(
      author: ChatAuthor.copilot,
      text: '',
      conversationId: conversation.id,
      createdAt: DateTime.now(),
    );
    setState(() {
      _isResponding = true;
      _messages = <ChatMessage>[..._messages, pending];
    });
    _scrollToLatest();

    try {
      ChatMessage completed = pending;
      await for (final update in _service.reply(
        history: history,
        prompt: question,
      )) {
        if (!mounted) return;
        completed = completed.copyWith(
          text: update.text,
          toolResults: update.isComplete
              ? update.toolResults
              : completed.toolResults,
        );
        setState(() => _replaceLast(pending, completed));
        _scrollToLatest();
      }
      final saved = await _repository.saveMessage(
        user: widget.user,
        conversationId: conversation.id,
        message: completed,
      );
      if (!mounted) return;
      setState(() => _replaceLast(pending, saved));
    } catch (error) {
      if (!mounted) return;
      final failed = pending.copyWith(
        text: error is CopilotRequestException
            ? error.message
            : 'The Copilot could not complete that request. Please try again.',
        isError: true,
        retryPrompt: question,
      );
      setState(() => _replaceLast(pending, failed));
    } finally {
      if (mounted) setState(() => _isResponding = false);
      _scrollToLatest();
    }
  }

  Future<void> _retry(ChatMessage failed) async {
    final prompt = failed.retryPrompt;
    if (prompt == null || _isResponding) return;
    setState(() {
      _messages = _messages.where((message) => message != failed).toList();
    });
    await _requestResponse(prompt);
  }

  Future<void> _openConversation(CopilotConversation conversation) async {
    if (_isResponding || conversation.id == _activeConversation?.id) return;
    setState(() => _isLoadingConversation = true);
    try {
      final messages = await _repository.loadMessages(
        user: widget.user,
        conversationId: conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _activeConversation = conversation;
        _messages = messages;
      });
      _scrollToLatest();
    } catch (error) {
      _showError('Unable to open this conversation: $error');
    } finally {
      if (mounted) setState(() => _isLoadingConversation = false);
    }
  }

  void _newChat() {
    if (_isResponding) return;
    setState(() {
      _activeConversation = null;
      _messages = <ChatMessage>[];
    });
    _inputController.clear();
  }

  Future<void> _renameConversation(CopilotConversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 72,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    try {
      await _repository.rename(
        user: widget.user,
        conversationId: conversation.id,
        title: title,
      );
      if (mounted && _activeConversation?.id == conversation.id) {
        setState(
          () => _activeConversation = _activeConversation!.copyWith(
            title: title.trim(),
          ),
        );
      }
    } catch (error) {
      _showError('Unable to rename conversation: $error');
    }
  }

  Future<void> _confirmAction(CopilotActionPreview preview) async {
    if (_isResponding || _activeConversation == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${preview.title}?'),
        content: Text(
          '${preview.description}\n\nThis writes a reminder draft only. No message will be sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create draft'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isResponding = true);
    try {
      final result = await _service.tools.executeConfirmedAction(preview);
      final message = ChatMessage(
        author: ChatAuthor.copilot,
        text: result.summary,
        conversationId: _activeConversation!.id,
        createdAt: DateTime.now(),
        toolResults: <CopilotToolResult>[result],
      );
      final saved = await _repository.saveMessage(
        user: widget.user,
        conversationId: _activeConversation!.id,
        message: message,
      );
      if (!mounted) return;
      setState(() => _messages = <ChatMessage>[..._messages, saved]);
      _scrollToLatest();
    } catch (error) {
      _showError('The reminder draft was not created: $error');
    } finally {
      if (mounted) setState(() => _isResponding = false);
    }
  }

  void _replaceLast(ChatMessage original, ChatMessage replacement) {
    final index = _messages.lastIndexWhere(
      (item) =>
          identical(item, original) ||
          (item.id == null &&
              original.id == null &&
              item.conversationId == original.conversationId &&
              item.author == original.author),
    );
    if (index == -1) return;
    _messages = List<ChatMessage>.from(_messages)..[index] = replacement;
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 980;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) ...[
              SizedBox(width: 270, child: _historyPanel()),
              const SizedBox(width: 18),
            ],
            Expanded(child: _chatPanel(showHistoryButton: !wide)),
          ],
        ),
      );
    },
  );

  Widget _historyPanel({bool compact = false}) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            onPressed: _isResponding ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('New chat'),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<CopilotConversation>>(
            stream: _repository.watchForUser(widget.user),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Conversation history is unavailable.'),
                );
              }
              final conversations =
                  snapshot.data ?? const <CopilotConversation>[];
              if (conversations.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Your saved conversations will appear here.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                );
              }
              return ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  final selected = conversation.id == _activeConversation?.id;
                  return ListTile(
                    selected: selected,
                    selectedTileColor: const Color(0xFFE8F0FF),
                    leading: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 19,
                    ),
                    title: Text(
                      conversation.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: conversation.lastMessagePreview.isEmpty
                        ? null
                        : Text(
                            conversation.lastMessagePreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Rename conversation',
                      onPressed: () => _renameConversation(conversation),
                    ),
                    onTap: () => _openConversation(conversation),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _chatPanel({required bool showHistoryButton}) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        _header(showHistoryButton: showHistoryButton),
        if (FirebaseAppCheckInitializer.statusMessage case final notice?)
          _ConfigurationNotice(message: notice),
        const Divider(height: 1),
        Expanded(child: _conversation()),
        _composer(),
      ],
    ),
  );

  Widget _header({required bool showHistoryButton}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
    child: Row(
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F0FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _activeConversation?.title ?? 'AI Copilot',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                'Gemini + authorized InstituteOS data',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
              ),
            ],
          ),
        ),
        if (showHistoryButton)
          IconButton(
            tooltip: 'Conversation history',
            onPressed: _openHistorySheet,
            icon: const Icon(Icons.history_rounded),
          ),
        IconButton(
          tooltip: 'New chat',
          onPressed: _isResponding ? null : _newChat,
          icon: const Icon(Icons.edit_note_rounded),
        ),
      ],
    ),
  );

  Widget _conversation() {
    if (_isLoadingConversation) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) return _welcome();
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _messages.length + (_isResponding ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index == _messages.length) return const _TypingBubble();
        final message = _messages[index];
        return _MessageGroup(
          message: message,
          onCopy: message.author == ChatAuthor.copilot
              ? () => Clipboard.setData(ClipboardData(text: message.text))
              : null,
          onRetry: message.isError ? () => _retry(message) : null,
          onConfirmAction: _confirmAction,
        );
      },
    );
  }

  Widget _welcome() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F0FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppTheme.brand,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Hi ${_firstName(widget.user.name)}, how can I help?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'I can use your authorized InstituteOS records for operational questions and keep the source and filters with every result.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _composer() => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFFE6EAF2))),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map(
                  (question) => ActionChip(
                    label: Text(question),
                    onPressed: _isResponding ? null : () => _send(question),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): _send,
                  },
                  child: TextField(
                    controller: _inputController,
                    enabled: !_isResponding && !_isLoadingConversation,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Ask about your institute data…',
                      helperText: 'Ctrl + Enter to send',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isResponding || _isLoadingConversation
                    ? null
                    : _send,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  void _openHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: _historyPanel(compact: true),
        ),
      ),
    );
  }

  static String _conversationTitle(String question) {
    final normalized = question.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 56
        ? normalized
        : '${normalized.substring(0, 53)}...';
  }

  static String _firstName(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'there' : trimmed.split(RegExp(r'\s+')).first;
  }
}

class _ConfigurationNotice extends StatelessWidget {
  const _ConfigurationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xFFFFF7E5),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    child: Row(
      children: [
        const Icon(Icons.security_outlined, color: Color(0xFFB45309), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
          ),
        ),
      ],
    ),
  );
}

class _MessageGroup extends StatelessWidget {
  const _MessageGroup({
    required this.message,
    this.onCopy,
    this.onRetry,
    required this.onConfirmAction,
  });

  final ChatMessage message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final ValueChanged<CopilotActionPreview> onConfirmAction;

  @override
  Widget build(BuildContext context) {
    final isUser = message.author == ChatAuthor.user;
    final bubbleColor = message.isError
        ? const Color(0xFFFEF2F2)
        : isUser
        ? AppTheme.brand
        : const Color(0xFFF0F4FA);
    final textColor = isUser ? Colors.white : AppTheme.ink;
    return Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: SelectableText(
                        message.text.isEmpty ? '…' : message.text,
                        style: TextStyle(color: textColor, height: 1.35),
                      ),
                    ),
                    if (onCopy != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: onCopy,
                        tooltip: 'Copy response',
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        color: AppTheme.ink,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onRetry != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ),
        for (final result in message.toolResults) ...[
          const SizedBox(height: 9),
          _ToolResultCard(result: result, onConfirmAction: onConfirmAction),
        ],
      ],
    );
  }
}

class _ToolResultCard extends StatelessWidget {
  const _ToolResultCard({required this.result, required this.onConfirmAction});

  final CopilotToolResult result;
  final ValueChanged<CopilotActionPreview> onConfirmAction;

  @override
  Widget build(BuildContext context) {
    final columns = <String>{for (final row in result.rows) ...row.keys}
        .take(7)
        .toList(growable: false);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 840),
      child: Card(
        margin: EdgeInsets.zero,
        color: const Color(0xFFFBFCFE),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.verified_outlined,
                    color: AppTheme.brand,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      result.source,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(result.summary),
              if (result.filters.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Filters: ${result.filters.entries.map((item) => '${item.key}: ${item.value}').join(' • ')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
              if (result.calculation != null) ...[
                const SizedBox(height: 6),
                Text(
                  result.calculation!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
              if (columns.isNotEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 34,
                    dataRowMinHeight: 38,
                    dataRowMaxHeight: 64,
                    columnSpacing: 18,
                    columns: columns
                        .map(
                          (column) =>
                              DataColumn(label: Text(column.toUpperCase())),
                        )
                        .toList(growable: false),
                    rows: result.rows
                        .take(12)
                        .map(
                          (row) => DataRow(
                            cells: columns
                                .map(
                                  (column) => DataCell(
                                    SizedBox(
                                      width: column == 'Message preview'
                                          ? 270
                                          : null,
                                      child: Text(
                                        row[column]?.toString() ?? '—',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
              if (result.actionPreview case final preview?) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FF),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.preview_outlined,
                        color: AppTheme.brand,
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          preview.description,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => onConfirmAction(preview),
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Query: ${result.queryId}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFFF0F4FA),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 9),
            Text('Thinking and checking authorized records…'),
          ],
        ),
      ),
    ),
  );
}
