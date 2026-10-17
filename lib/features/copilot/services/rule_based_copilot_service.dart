import '../models/copilot_tool_result.dart';
import 'copilot_tool_registry.dart';

/// A transparent fallback for common Copilot questions when the live AI
/// provider is unavailable. It never invents operational data: database facts
/// can only come from the same registered, role-scoped tools used by Gemini.
class RuleBasedCopilotResponse {
  const RuleBasedCopilotResponse({
    required this.text,
    this.toolResults = const <CopilotToolResult>[],
  });

  final String text;
  final List<CopilotToolResult> toolResults;
}

class RuleBasedCopilotService {
  RuleBasedCopilotService({required this.tools});

  final CopilotToolRegistry tools;

  Future<RuleBasedCopilotResponse> respond(String prompt) async {
    tools.clearResults();
    final question = prompt.trim().toLowerCase();

    if (_isGreeting(question)) {
      return const RuleBasedCopilotResponse(
        text: 'Hello. The live AI service is unavailable, so this is the built-in InstituteOS helper. I can still look up authorized students, attendance, batches, today\'s timetable, and risk alerts.',
      );
    }

    if (_containsAny(question, <String>['attendance', 'below'])) {
      return _runTool(
        'find_low_attendance',
        <String, Object?>{
          'threshold': _attendanceThreshold(question),
          if (question.contains('java')) 'batch': 'Java',
        },
        unavailable: 'Your role is not permitted to view attendance through this helper.',
      );
    }

    if (_containsAny(question, <String>['student', 'students'])) {
      return _runTool('search_students', <String, Object?>{
        if (question.contains('java')) 'batch': 'Java',
      });
    }

    if (_containsAny(question, <String>[
      'schedule',
      'timetable',
      'class today',
    ])) {
      return _runTool(
        'list_timetable',
        <String, Object?>{if (question.contains('java')) 'batch': 'Java'},
        unavailable: 'Your role is not permitted to view the timetable through this helper.',
      );
    }

    if (_containsAny(question, <String>['risk', 'follow-up', 'follow up'])) {
      return _runTool('list_risk_alerts', const <String, Object?>{});
    }

    if (_containsAny(question, <String>['batch', 'batches', 'course'])) {
      return _runTool('list_batches', <String, Object?>{
        if (question.contains('java')) 'query': 'Java',
      });
    }

    if (_containsAny(question, <String>[
      'fee',
      'fees',
      'payment',
      'overdue',
      'instalment',
      'installment',
    ])) {
      return _runTool(
        'list_overdue_instalments',
        <String, Object?>{if (question.contains('java')) 'batch': 'Java'},
        unavailable: 'Financial data is available only to Owner / Admin and Accounts Staff.',
      );
    }

    if (_containsAny(question, <String>['approval', 'approvals'])) {
      return _runTool(
        'list_approval_requests',
        const <String, Object?>{},
        unavailable: 'Approval requests are available only to the roles authorized to review them.',
      );
    }

    return const RuleBasedCopilotResponse(
      text: 'The live AI service is unavailable, so I can only answer built-in questions right now. Try: “Show students in the Java batch”, “Which students have attendance below 75%?”, “Show today\'s trainer schedule”, or “Find students who may need follow-up.”',
    );
  }

  Future<RuleBasedCopilotResponse> _runTool(
    String name,
    Map<String, Object?> arguments, {
    String? unavailable,
  }) async {
    final matches = tools.declarations
        .where((declaration) => declaration.name == name)
        .toList(growable: false);
    if (matches.isEmpty) {
      return RuleBasedCopilotResponse(
        text:
            unavailable ??
            'That information is not available through the built-in helper.',
      );
    }

    try {
      await matches.single.callable(arguments);
      final results = tools.takeResults();
      if (results.isEmpty) {
        return const RuleBasedCopilotResponse(
          text: 'The built-in lookup did not return a usable result.',
        );
      }
      final result = results.last;
      return RuleBasedCopilotResponse(
        text:
            'The live AI service is unavailable, so I used the built-in authorized lookup. ${result.summary}',
        toolResults: results,
      );
    } catch (_) {
      tools.clearResults();
      return const RuleBasedCopilotResponse(
        text: 'The live AI service is unavailable, and the built-in database lookup could not be completed. Check your connection and permissions, then try again.',
      );
    }
  }

  static bool _isGreeting(String value) =>
      RegExp(r'^(hi|hello|hey|help)[!.?\s]*$').hasMatch(value);

  static bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);

  static double _attendanceThreshold(String question) {
    final match = RegExp(r'below\s+(\d{1,3})').firstMatch(question);
    final parsed = double.tryParse(match?.group(1) ?? '');
    return (parsed ?? 75).clamp(0, 100);
  }
}
