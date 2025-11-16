import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:rising_roots/models/ag_models.dart';

abstract class GeminiService {
  Future<ChatMessage> sendMessage({
    required List<ChatMessage> history,
    required String prompt,
    required String fieldId,
  });

  Future<List<double>> embedDocument(String text);

  Future<void> indexDocument({
    required String documentId,
    required String text,
    required List<String> tags,
  });

  Stream<List<ChatMessage>> watchConversation(String fieldId);
}

class GoogleGeminiService implements GeminiService {
  GoogleGeminiService({
    String? apiKey,
    String model = 'models/gemini-2.5-flash',
  })  : _apiKey = apiKey ?? dotenv.env['GOOGLE_GEMINI_API_KEY'],
        _modelName = model {
    if ((_apiKey ?? '').isEmpty) {
      throw StateError('GOOGLE_GEMINI_API_KEY is missing. Please configure it in your environment.');
    }
    _model = GenerativeModel(model: _modelName, apiKey: _apiKey!);
    _embeddingModel = GenerativeModel(model: 'text-embedding-004', apiKey: _apiKey!);
  }

  final String? _apiKey;
  final String _modelName;
  late final GenerativeModel _model;
  late final GenerativeModel _embeddingModel;

  @override
  Future<ChatMessage> sendMessage({
    required List<ChatMessage> history,
    required String prompt,
    required String fieldId,
  }) async {
    final chat = _model.startChat(
      history: history
          .map(
            (message) => Content(
              message.role == 'user' ? 'user' : 'model',
              [TextPart(message.content)],
            ),
          )
          .toList(),
    );

    final response = await chat.sendMessage(
      Content.multi([
        TextPart(prompt),
        TextPart('\n\nField context: $fieldId'),
      ]),
    );

    final reply = response.text?.trim();

    return ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'assistant',
      content: reply?.isNotEmpty == true ? reply! : 'I was unable to generate a response.',
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<List<double>> embedDocument(String text) async {
    final result = await _embeddingModel.embedContent(Content.text(text));
    return result.embedding.values;
  }

  @override
  Future<void> indexDocument({
    required String documentId,
    required String text,
    required List<String> tags,
  }) async {
    // Placeholder for future vector-store indexing.
  }

  @override
  Stream<List<ChatMessage>> watchConversation(String fieldId) {
    return const Stream.empty();
  }
}

