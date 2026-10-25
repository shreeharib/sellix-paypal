import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'models.dart';

/// The merchant API used by every screen (backend/app/api/v1).
abstract interface class SellixApi {
  Future<Me> me();
  Future<Merchant> updateMerchant({String? name, bool? agentEnabled});
  Future<Today> today();
  Future<Today> setOpeningStock(List<StockLine> lines);
  Future<List<Order>> orders({String? status});
  Future<List<Question>> questions({required String status});
  Future<Question> answerQuestion(String id, String answer);
  Future<Question> dismissQuestion(String id);
  Future<List<Conversation>> conversations();
  Future<List<ChatMessage>> messages(String conversationId);
  Future<void> switchAgent(String conversationId, {required bool active});
  Future<ShopProfile?> shopProfile();
  Future<ShopProfile> saveShopProfile(String contentMd);
  Future<Onboarding> onboarding();
  Future<Onboarding> saveOnboarding({
    required String shopName,
    required OnboardingAnswers answers,
    bool complete = false,
  });
  Future<void> logout();
}

class HttpSellixApi implements SellixApi {
  HttpSellixApi(this._dio);

  final Dio _dio;

  @override
  Future<Me> me() async => Me.fromJson(await _get('/v1/me'));

  @override
  Future<Merchant> updateMerchant({String? name, bool? agentEnabled}) async =>
      Merchant.fromJson(await _send('PATCH', '/v1/merchant', {
        'name': ?name,
        'agent_enabled': ?agentEnabled,
      }));

  @override
  Future<Today> today() async => Today.fromJson(await _get('/v1/today'));

  @override
  Future<Today> setOpeningStock(List<StockLine> lines) async => Today.fromJson(
        await _send('PUT', '/v1/today/stock', {'lines': [for (final line in lines) line.toJson()]}),
      );

  @override
  Future<List<Order>> orders({String? status}) async => [
        for (final order in await _getList('/v1/orders', {'status': ?status}))
          Order.fromJson(order as Map<String, dynamic>),
      ];

  @override
  Future<List<Question>> questions({required String status}) async => [
        for (final question in await _getList('/v1/questions', {'status': status}))
          Question.fromJson(question as Map<String, dynamic>),
      ];

  @override
  Future<Question> answerQuestion(String id, String answer) async =>
      Question.fromJson(await _send('POST', '/v1/questions/$id/answer', {'answer': answer}));

  @override
  Future<Question> dismissQuestion(String id) async =>
      Question.fromJson(await _send('POST', '/v1/questions/$id/close', null));

  @override
  Future<List<Conversation>> conversations() async => [
        for (final chat in await _getList('/v1/conversations'))
          Conversation.fromJson(chat as Map<String, dynamic>),
      ];

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
        for (final message in await _getList('/v1/conversations/$conversationId/messages'))
          ChatMessage.fromJson(message as Map<String, dynamic>),
      ];

  @override
  Future<void> switchAgent(String conversationId, {required bool active}) async {
    await _send('PUT', '/v1/conversations/$conversationId/agent', {'active': active});
  }

  @override
  Future<ShopProfile?> shopProfile() async {
    final data = await _request<Object?>('GET', '/v1/shop-profile');
    return data == null ? null : ShopProfile.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<ShopProfile> saveShopProfile(String contentMd) async =>
      ShopProfile.fromJson(await _send('PUT', '/v1/shop-profile', {'content_md': contentMd}));

  @override
  Future<Onboarding> onboarding() async => Onboarding.fromJson(await _get('/v1/onboarding'));

  @override
  Future<Onboarding> saveOnboarding({
    required String shopName,
    required OnboardingAnswers answers,
    bool complete = false,
  }) async =>
      Onboarding.fromJson(await _send('PUT', '/v1/onboarding', {
        'shop_name': shopName,
        'answers': answers.toJson(),
        'complete': complete,
      }));

  @override
  Future<void> logout() async {
    await _request<Object?>('POST', '/v1/auth/logout');
  }

  Future<Map<String, dynamic>> _get(String path) async =>
      await _request<Map<String, dynamic>>('GET', path) ?? const {};

  Future<List<dynamic>> _getList(String path, [Map<String, Object>? query]) async =>
      await _request<List<dynamic>>('GET', path, query: query) ?? const [];

  Future<Map<String, dynamic>> _send(String method, String path, Object? body) async =>
      await _request<Map<String, dynamic>>(method, path, body: body) ?? const {};

  Future<T?> _request<T>(String method, String path, {Object? body, Map<String, Object>? query}) async {
    try {
      final response = await _dio.request<T>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
      return response.data;
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
