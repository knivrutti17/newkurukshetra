import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_message.dart';
import '../services/demo_copilot_service.dart';

class CopilotScreen extends StatefulWidget {
  const CopilotScreen({super.key});

  @override
  State<CopilotScreen> createState() => _CopilotScreenState();
}

class _CopilotScreenState extends State<CopilotScreen> {
  static const _suggestions = [
    'Which students have low attendance?',
    'Which fees are due this week?',
    'Show today\'s trainer schedule.',
    'Find students who may need follow-up.',
  ];

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _service = const DemoCopilotService();
  final List<ChatMessage> _messages = [];
  bool _isResponding = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestedQuestion]) async {
    final question = (suggestedQuestion ?? _inputController.text).trim();
    if (question.isEmpty || _isResponding) {
      return;
    }

    _inputController.clear();
    setState(() {
      _messages.add(ChatMessage(author: ChatAuthor.user, text: question));
      _isResponding = true;
    });
    _scrollToLatest();

    final response = await _service.respondTo(question);
    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(ChatMessage(author: ChatAuthor.copilot, text: response));
      _isResponding = false;
    });
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 18),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(child: _conversation(context)),
                  _composer(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F0FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.brand),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Copilot',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              Text(
                'Ask a question and preview the future Copilot experience.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Colors.blueGrey.shade600),
              ),
            ],
          ),
        ),
        const _CopilotDemoLabel(),
      ],
    );
  }

  Widget _conversation(BuildContext context) {
    if (_messages.isEmpty) {
      return _emptyState(context);
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _messages.length + (_isResponding ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const _TypingBubble();
        }
        return _MessageBubble(message: _messages[index]);
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
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
                'Welcome to the AI Copilot',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start with a suggested question. Responses are clearly marked '
                'as demo-only and do not use institute data.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    return DecoratedBox(
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
                      avatar: const Icon(Icons.add_comment_outlined, size: 16),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: !_isResponding,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask a demo question…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isResponding ? null : _send,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(50, 50),
                    padding: EdgeInsets.zero,
                  ),
                  child: _isResponding
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.author == ChatAuthor.user;
    final color = isUser ? AppTheme.brand : const Color(0xFFF0F4FA);
    final textColor = isUser ? Colors.white : AppTheme.ink;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(message.text, style: TextStyle(color: textColor)),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
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
              Text('Preparing a demo response…'),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopilotDemoLabel extends StatelessWidget {
  const _CopilotDemoLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB9CDFB)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'DEMO RESPONSES',
        style: TextStyle(
          color: AppTheme.brand,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
        ),
      ),
    );
  }
}
