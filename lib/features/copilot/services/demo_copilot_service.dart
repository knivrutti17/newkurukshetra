/// A presentation-only response provider used until an AI integration exists.
class DemoCopilotService {
  const DemoCopilotService({
    this.responseDelay = const Duration(milliseconds: 650),
  });

  final Duration responseDelay;

  Future<String> respondTo(String question) async {
    await Future<void>.delayed(responseDelay);
    return 'Demo response: I received “$question”. The AI Copilot is not '
        'connected to institute records or an AI API in this demo, so no '
        'operational conclusion has been made.';
  }
}
