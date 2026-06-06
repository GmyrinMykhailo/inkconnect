import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_transport.dart';
import '../models.dart';

typedef UnauthorizedSessionCallback = void Function();

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class InkConnectApiClient {
  InkConnectApiClient({HttpTransport? transport, this.onUnauthorized})
    : _transport = transport ?? createTransport(),
      baseUrl = _resolveBaseUrl();

  final HttpTransport _transport;
  final UnauthorizedSessionCallback? onUnauthorized;
  final String baseUrl;

  static String _resolveBaseUrl() {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) {
      return override;
    }

    if (kIsWeb) {
      return '';
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:18080';
    }

    return 'http://127.0.0.1:18080';
  }

  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/auth/login',
      headers: _jsonHeaders(),
      body: jsonEncode({'email': email, 'password': password}),
    );

    return _decodeJson(
      response,
      (json) => LoginResponse.fromJson(json),
      notifyUnauthorized: false,
    );
  }

  Future<RegistrationResponse> register(Map<String, dynamic> payload) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/auth/register',
      headers: _jsonHeaders(),
      body: jsonEncode(payload),
    );

    return _decodeJson(response, (json) => RegistrationResponse.fromJson(json));
  }

  Future<AuthUser> currentUser(String sessionToken) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/auth/me',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final userJson = json['user'] as Map<String, dynamic>? ?? {};
      return AuthUser.fromJson(userJson);
    });
  }

  Future<void> logout(String sessionToken) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/auth/logout',
      headers: _authHeaders(sessionToken),
    );

    _throwIfError(response);
  }

  Future<UserProfile> currentProfile(String sessionToken) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/profile/me',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final profileJson = json['profile'] as Map<String, dynamic>? ?? {};
      return UserProfile.fromJson(_withResolvedAvatarUrl(profileJson));
    });
  }

  Future<UserProfile> updateProfile({
    required String sessionToken,
    required ProfileUpdatePayload payload,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/profile/me',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJson(response, (json) {
      final profileJson = json['profile'] as Map<String, dynamic>? ?? {};
      return UserProfile.fromJson(_withResolvedAvatarUrl(profileJson));
    });
  }

  Future<UserProfile> uploadProfileAvatar({
    required String sessionToken,
    required List<int> bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/profile/avatar'),
    );
    request.headers.addAll(_authMultipartHeaders(sessionToken));
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

    final streamedResponse = await request.send();
    final body = await streamedResponse.stream.bytesToString();
    return _decodeProfileResponse(
      TransportResponse(statusCode: streamedResponse.statusCode, body: body),
    );
  }

  Future<UserProfile> deleteProfileAvatar({
    required String sessionToken,
  }) async {
    final response = await _transport.delete(
      '$baseUrl/api/v1/profile/avatar',
      headers: _authHeaders(sessionToken),
    );

    return _decodeProfileResponse(response);
  }

  Future<PublicUserProfile> publicUserProfile({
    required String sessionToken,
    required String username,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/profiles/${Uri.encodeComponent(username)}',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final profileJson = json['profile'] as Map<String, dynamic>? ?? {};
      return PublicUserProfile.fromJson(_withResolvedAvatarUrl(profileJson));
    });
  }

  Future<void> changePassword({
    required String sessionToken,
    required PasswordChangePayload payload,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/security/password',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    _throwIfError(response);
  }

  Future<SecurityContact> securityContact(String sessionToken) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/security/contact',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final contactJson = json['contact'] as Map<String, dynamic>? ?? {};
      return SecurityContact.fromJson(contactJson);
    });
  }

  Future<SecurityContact> updateSecurityEmail({
    required String sessionToken,
    required EmailUpdatePayload payload,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/security/email',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJson(response, (json) {
      final contactJson = json['contact'] as Map<String, dynamic>? ?? {};
      return SecurityContact.fromJson(contactJson);
    });
  }

  Future<SecurityContact> updateSecurityPhone({
    required String sessionToken,
    required PhoneUpdatePayload payload,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/security/phone',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJson(response, (json) {
      final contactJson = json['contact'] as Map<String, dynamic>? ?? {};
      return SecurityContact.fromJson(contactJson);
    });
  }

  Future<void> deleteAccount({
    required String sessionToken,
    required AccountDeletePayload payload,
  }) async {
    final response = await _transport.delete(
      '$baseUrl/api/v1/security/account',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    _throwIfError(response);
  }

  Future<bool> isUsernameAvailable(String username) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/auth/check-username?username=${Uri.encodeQueryComponent(username)}',
      headers: const {'Accept': 'application/json'},
    );

    return _decodeJson(response, (json) => json['available'] as bool? ?? false);
  }

  Future<bool> isEmailAvailable(String email) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/auth/check-email?email=${Uri.encodeQueryComponent(email)}',
      headers: const {'Accept': 'application/json'},
    );

    return _decodeJson(response, (json) => json['available'] as bool? ?? false);
  }

  Future<bool> isPhoneAvailable(String phone) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/auth/check-phone?phone=${Uri.encodeQueryComponent(phone)}',
      headers: const {'Accept': 'application/json'},
    );

    return _decodeJson(response, (json) => json['available'] as bool? ?? false);
  }

  Future<MasterSearchResponse> searchMasters({
    required String query,
    int? limit,
    String? sessionToken,
  }) async {
    final params = <String, String>{
      'q': query,
      if (limit != null) 'limit': limit.toString(),
    };
    final uri = Uri.parse(
      '$baseUrl/api/v1/masters/search',
    ).replace(queryParameters: params);
    final response = await _transport.get(
      uri.toString(),
      headers: sessionToken == null || sessionToken.isEmpty
          ? const {'Accept': 'application/json'}
          : _authHeaders(sessionToken),
    );

    return _decodeJson(response, _masterSearchResponseFromJson);
  }

  Future<MasterProfile> publicMasterProfile(String username) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/masters/${Uri.encodeComponent(username)}',
      headers: const {'Accept': 'application/json'},
    );

    return _decodeJson(response, (json) {
      final profileJson = json['profile'] as Map<String, dynamic>? ?? {};
      return MasterProfile.fromJson(_withResolvedAvatarUrl(profileJson));
    });
  }

  Future<List<MasterProfile>> getFavoriteMasters({
    required String sessionToken,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/favorites/masters',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final rawItems = json['items'] as List<dynamic>? ?? const [];
      return rawItems
          .map(
            (item) => MasterProfile.fromJson(
              _withResolvedAvatarUrl(
                item as Map<String, dynamic>? ?? const <String, dynamic>{},
              ),
            ),
          )
          .toList();
    });
  }

  Future<void> addFavoriteMaster({
    required String sessionToken,
    required String masterId,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/favorites/masters/${Uri.encodeComponent(masterId)}',
      headers: _authHeaders(sessionToken),
    );

    _throwIfError(response);
  }

  Future<void> removeFavoriteMaster({
    required String sessionToken,
    required String masterId,
  }) async {
    final response = await _transport.delete(
      '$baseUrl/api/v1/favorites/masters/${Uri.encodeComponent(masterId)}',
      headers: _authHeaders(sessionToken),
    );

    _throwIfError(response);
  }

  Future<List<ChatThreadSummary>> getChatThreads({
    required String sessionToken,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/chats',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(
      response,
      (json) => ChatThreadListResponse.fromJson(json).items,
    );
  }

  Future<ChatThreadSummary> getOrCreateChatWithUser({
    required String sessionToken,
    required String userId,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/chats/with/${Uri.encodeComponent(userId)}',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final threadJson = json['thread'] as Map<String, dynamic>? ?? {};
      return ChatThreadSummary.fromJson(threadJson);
    });
  }

  Future<List<ChatMessage>> getChatMessages({
    required String sessionToken,
    required String threadId,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/chats/${Uri.encodeComponent(threadId)}/messages',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(
      response,
      (json) => ChatMessageListResponse.fromJson(json).items,
    );
  }

  Future<ChatMessage> sendChatMessage({
    required String sessionToken,
    required String threadId,
    required String text,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/chats/${Uri.encodeComponent(threadId)}/messages',
      headers: _authHeaders(sessionToken),
      body: jsonEncode({'body': text}),
    );

    return _decodeJson(response, (json) {
      final messageJson = json['message'] as Map<String, dynamic>? ?? {};
      return ChatMessage.fromJson(messageJson);
    });
  }

  Future<ChatMessage> editChatMessage({
    required String sessionToken,
    required String threadId,
    required String messageId,
    required String text,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/chats/${Uri.encodeComponent(threadId)}/messages/${Uri.encodeComponent(messageId)}',
      headers: _authHeaders(sessionToken),
      body: jsonEncode({'body': text}),
    );

    return _decodeJson(response, (json) {
      final messageJson = json['message'] as Map<String, dynamic>? ?? {};
      return ChatMessage.fromJson(messageJson);
    });
  }

  Future<ChatMessage> deleteChatMessage({
    required String sessionToken,
    required String threadId,
    required String messageId,
  }) async {
    final response = await _transport.delete(
      '$baseUrl/api/v1/chats/${Uri.encodeComponent(threadId)}/messages/${Uri.encodeComponent(messageId)}',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final messageJson = json['message'] as Map<String, dynamic>? ?? {};
      return ChatMessage.fromJson(messageJson);
    });
  }

  Future<MasterPublication> createMasterPublication({
    required String sessionToken,
    required List<PublicationPhotoUploadPayload> photos,
    String description = '',
    List<String> styles = const [],
    bool commentsDisabled = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/master/publications'),
    );
    request.headers.addAll(_authMultipartHeaders(sessionToken));
    request.fields['description'] = description;
    request.fields['styles_json'] = jsonEncode(styles);
    request.fields['comments_disabled'] = commentsDisabled.toString();
    for (final photo in photos) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photos',
          photo.bytes,
          filename: photo.filename,
        ),
      );
    }

    final streamedResponse = await request.send();
    final body = await streamedResponse.stream.bytesToString();
    return _decodePublicationResponse(
      TransportResponse(statusCode: streamedResponse.statusCode, body: body),
    );
  }

  Future<List<MasterPublication>> masterPublications(String username) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/masters/${Uri.encodeComponent(username)}/publications',
      headers: const {'Accept': 'application/json'},
    );

    return _decodeJson(response, (json) {
      final rawItems = json['items'] as List<dynamic>? ?? const [];
      return rawItems
          .map(
            (item) => MasterPublication.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList();
    });
  }

  Future<MasterPublication> publication(String publicationId) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/publications/${Uri.encodeComponent(publicationId)}',
      headers: const {'Accept': 'application/json'},
    );

    return _decodePublicationResponse(response);
  }

  Future<void> deleteMasterPublication({
    required String sessionToken,
    required String publicationId,
  }) async {
    final response = await _transport.delete(
      '$baseUrl/api/v1/master/publications/${Uri.encodeComponent(publicationId)}',
      headers: _authHeaders(sessionToken),
    );

    _throwIfError(response);
  }

  Future<List<AvailabilitySlot>> masterAvailability({
    required String username,
    required String date,
    String? serviceId,
  }) async {
    final params = <String, String>{'date': date};
    if (serviceId != null && serviceId.isNotEmpty) {
      params['service_id'] = serviceId;
    }
    final query = params.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    final response = await _transport.get(
      '$baseUrl/api/v1/masters/${Uri.encodeComponent(username)}/availability?$query',
      headers: const {'Accept': 'application/json'},
    );

    return _decodeJson(response, (json) {
      final availability =
          json['availability'] as Map<String, dynamic>? ?? const {};
      final rawSlots = availability['slots'] as List<dynamic>? ?? const [];
      return rawSlots
          .map(
            (slot) => AvailabilitySlot.fromJson(
              slot as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList();
    });
  }

  Future<AppointmentRecord> createAppointment({
    required String sessionToken,
    required AppointmentCreatePayload payload,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/appointments',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJson(response, (json) {
      final appointmentJson =
          json['appointment'] as Map<String, dynamic>? ?? {};
      return AppointmentRecord.fromJson(appointmentJson);
    });
  }

  Future<AppointmentListResponse> clientAppointments(
    String sessionToken,
  ) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/appointments/me',
      headers: _authHeaders(sessionToken),
    );

    return _decodeAppointmentList(response);
  }

  Future<AppointmentListResponse> masterAppointments(
    String sessionToken,
  ) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/master/appointments',
      headers: _authHeaders(sessionToken),
    );

    return _decodeAppointmentList(response);
  }

  Future<AppointmentRecord> updateMasterAppointmentStatus({
    required String sessionToken,
    required String appointmentId,
    required String status,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/master/appointments/${Uri.encodeComponent(appointmentId)}',
      headers: _authHeaders(sessionToken),
      body: jsonEncode({'status': status}),
    );

    return _decodeJson(response, (json) {
      final appointmentJson =
          json['appointment'] as Map<String, dynamic>? ?? {};
      return AppointmentRecord.fromJson(appointmentJson);
    });
  }

  Future<AppointmentDurationUpdateResponse> updateMasterAppointmentDuration({
    required String sessionToken,
    required String appointmentId,
    required int durationMinutes,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/master/appointments/${Uri.encodeComponent(appointmentId)}/duration',
      headers: _authHeaders(sessionToken),
      body: jsonEncode({'duration_minutes': durationMinutes}),
    );

    return _decodeJson(
      response,
      (json) => AppointmentDurationUpdateResponse.fromJson(json),
    );
  }

  Future<RecommendationsResponse> masterAppointmentRecommendations({
    required String sessionToken,
    required String appointmentId,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/master/appointments/${Uri.encodeComponent(appointmentId)}/recommendations',
      headers: _authHeaders(sessionToken),
    );

    return _decodeRecommendationsResponse(response);
  }

  Future<RecommendationsResponse> saveMasterAppointmentRecommendations({
    required String sessionToken,
    required String appointmentId,
    required RecommendationsSavePayload payload,
  }) async {
    final response = await _transport.put(
      '$baseUrl/api/v1/master/appointments/${Uri.encodeComponent(appointmentId)}/recommendations',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeRecommendationsResponse(response);
  }

  Future<RecommendationsResponse> sendMasterAppointmentRecommendations({
    required String sessionToken,
    required String appointmentId,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/master/appointments/${Uri.encodeComponent(appointmentId)}/recommendations/send',
      headers: _authHeaders(sessionToken),
    );

    return _decodeRecommendationsResponse(response);
  }

  Future<RecommendationsResponse> clientAppointmentRecommendations({
    required String sessionToken,
    required String appointmentId,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/appointments/${Uri.encodeComponent(appointmentId)}/recommendations',
      headers: _authHeaders(sessionToken),
    );

    return _decodeRecommendationsResponse(response);
  }

  Future<RecommendationsResponse> approveAppointmentRecommendations({
    required String sessionToken,
    required String appointmentId,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/appointments/${Uri.encodeComponent(appointmentId)}/recommendations/approve',
      headers: _authHeaders(sessionToken),
    );

    return _decodeRecommendationsResponse(response);
  }

  Future<CareJournalDetail> createAppointmentJournal({
    required String sessionToken,
    required String appointmentId,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/appointments/${Uri.encodeComponent(appointmentId)}/journal',
      headers: _authHeaders(sessionToken),
    );

    return _decodeCareJournalDetail(response);
  }

  Future<List<AppointmentJournalSummary>> getAppointmentJournals({
    required String sessionToken,
    required String appointmentId,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/appointments/${Uri.encodeComponent(appointmentId)}/journals',
      headers: _authHeaders(sessionToken),
    );

    return _decodeAppointmentJournals(response);
  }

  Future<CareJournalListResponse> clientCareJournals(
    String sessionToken,
  ) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/journals/me',
      headers: _authHeaders(sessionToken),
    );

    return _decodeCareJournalList(response);
  }

  Future<CareJournalListResponse> masterCareJournals(
    String sessionToken,
  ) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/master/journals',
      headers: _authHeaders(sessionToken),
    );

    return _decodeCareJournalList(response);
  }

  Future<CareJournalDetail> careJournal({
    required String sessionToken,
    required String journalId,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}',
      headers: _authHeaders(sessionToken),
    );

    return _decodeCareJournalDetail(response);
  }

  Future<JournalIntegrityReport> getJournalIntegrity({
    required String sessionToken,
    required String journalId,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}/integrity',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJournalIntegrity(response);
  }

  Future<JournalEventListResponse> getJournalEvents({
    required String sessionToken,
    required String journalId,
  }) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}/events',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJournalEvents(response);
  }

  Future<CareJournalDetail> confirmCareJournalStep({
    required String sessionToken,
    required String journalId,
    required String stepId,
  }) async {
    if (journalId.trim().isEmpty || stepId.trim().isEmpty) {
      throw const ApiException('Журнал ухода не готов к подтверждению шага.');
    }
    final response = await _transport.post(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}/steps/${Uri.encodeComponent(stepId)}/confirm',
      headers: _authHeaders(sessionToken),
    );

    return _decodeCareJournalDetail(response);
  }

  Future<JournalEventResult> createJournalUnavailabilityNotice({
    required String sessionToken,
    required String journalId,
    required JournalUnavailabilityPayload payload,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}/unavailability',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJournalEventResult(response);
  }

  Future<JournalEventResult> createJournalClientProblemReport({
    required String sessionToken,
    required String journalId,
    required JournalClientProblemPayload payload,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}/client-problem',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJournalEventResult(response);
  }

  Future<JournalEventResult> extendJournalStepDeadline({
    required String sessionToken,
    required String journalId,
    required String stepId,
    required JournalDeadlineExtensionPayload payload,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}/steps/${Uri.encodeComponent(stepId)}/deadline-extension',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJournalEventResult(response);
  }

  Future<JournalEventResult> stopJournal({
    required String sessionToken,
    required String journalId,
    required JournalStopPayload payload,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}/stop',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJournalEventResult(response);
  }

  Future<ReplacementJournalResult> createReplacementJournal({
    required String sessionToken,
    required String journalId,
    required ReplacementJournalPayload payload,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/journals/${Uri.encodeComponent(journalId)}/replacement',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeReplacementJournalResult(response);
  }

  Future<List<MasterServiceSettings>> currentMasterServices(
    String sessionToken,
  ) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/masters/me/services',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final rawItems = json['items'] as List<dynamic>? ?? const [];
      return rawItems
          .map(
            (item) => MasterServiceSettings.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList();
    });
  }

  Future<MasterSettings> currentMasterSettings(String sessionToken) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/masters/me/profile',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final settingsJson = json['settings'] as Map<String, dynamic>? ?? {};
      return MasterSettings.fromJson(settingsJson);
    });
  }

  Future<MasterSettings> updateMasterSettings({
    required String sessionToken,
    required MasterSettingsPayload payload,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/masters/me/profile',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJson(response, (json) {
      final settingsJson = json['settings'] as Map<String, dynamic>? ?? {};
      return MasterSettings.fromJson(settingsJson);
    });
  }

  Future<MasterSchedule> currentMasterSchedule(String sessionToken) async {
    final response = await _transport.get(
      '$baseUrl/api/v1/masters/me/schedule',
      headers: _authHeaders(sessionToken),
    );

    return _decodeJson(response, (json) {
      final scheduleJson = json['schedule'] as Map<String, dynamic>? ?? {};
      return MasterSchedule.fromJson(scheduleJson);
    });
  }

  Future<MasterSchedule> updateMasterSchedule({
    required String sessionToken,
    required MasterSchedule payload,
  }) async {
    final response = await _transport.put(
      '$baseUrl/api/v1/masters/me/schedule',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJson(response, (json) {
      final scheduleJson = json['schedule'] as Map<String, dynamic>? ?? {};
      return MasterSchedule.fromJson(scheduleJson);
    });
  }

  Future<MasterServiceSettings> createMasterService({
    required String sessionToken,
    required MasterServicePayload payload,
  }) async {
    final response = await _transport.post(
      '$baseUrl/api/v1/masters/me/services',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJson(response, (json) {
      final serviceJson = json['service'] as Map<String, dynamic>? ?? {};
      return MasterServiceSettings.fromJson(serviceJson);
    });
  }

  Future<MasterServiceSettings> updateMasterService({
    required String sessionToken,
    required String serviceId,
    required MasterServicePayload payload,
  }) async {
    final response = await _transport.patch(
      '$baseUrl/api/v1/masters/me/services/${Uri.encodeComponent(serviceId)}',
      headers: _authHeaders(sessionToken),
      body: jsonEncode(payload.toJson()),
    );

    return _decodeJson(response, (json) {
      final serviceJson = json['service'] as Map<String, dynamic>? ?? {};
      return MasterServiceSettings.fromJson(serviceJson);
    });
  }

  Future<void> deleteMasterService({
    required String sessionToken,
    required String serviceId,
  }) async {
    final response = await _transport.delete(
      '$baseUrl/api/v1/masters/me/services/${Uri.encodeComponent(serviceId)}',
      headers: _authHeaders(sessionToken),
    );

    _throwIfError(response);
  }

  T _decodeJson<T>(
    TransportResponse response,
    T Function(Map<String, dynamic> json) parser, {
    bool notifyUnauthorized = true,
  }) {
    _throwIfError(response, notifyUnauthorized: notifyUnauthorized);

    final body = response.body.trim();
    if (body.isEmpty) {
      throw const ApiException('Пустой ответ сервера.');
    }

    final decoded = _withResolvedAvatarUrls(
      jsonDecode(body) as Map<String, dynamic>,
    );
    return parser(decoded);
  }

  MasterSearchResponse _masterSearchResponseFromJson(
    Map<String, dynamic> json,
  ) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return MasterSearchResponse(
      items: rawItems
          .map(
            (item) => MasterProfile.fromJson(
              _withResolvedAvatarUrl(
                item as Map<String, dynamic>? ?? const <String, dynamic>{},
              ),
            ),
          )
          .toList(),
      query: json['query'] as String? ?? '',
    );
  }

  Map<String, dynamic> _withResolvedAvatarUrl(Map<String, dynamic> json) {
    final avatarUrl = json['avatar_url'] as String? ?? '';
    final resolvedAvatarUrl = _resolveMediaUrl(avatarUrl);
    if (avatarUrl == resolvedAvatarUrl) {
      return json;
    }

    return {...json, 'avatar_url': resolvedAvatarUrl};
  }

  Map<String, dynamic> _withResolvedAvatarUrls(Map<String, dynamic> json) {
    return json.map<String, dynamic>((key, value) {
      if ((key == 'avatar_url' ||
              key == 'image_url' ||
              key == 'cover_image_url') &&
          value is String) {
        return MapEntry(key, _resolveMediaUrl(value));
      }
      return MapEntry(key, _withResolvedAvatarValue(value));
    });
  }

  Object? _withResolvedAvatarValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return _withResolvedAvatarUrls(value);
    }
    if (value is List) {
      return value.map(_withResolvedAvatarValue).toList();
    }
    return value;
  }

  String _resolveMediaUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('blob:')) {
      return trimmed;
    }

    final normalizedBase = baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (trimmed.startsWith('/')) {
      return '$normalizedBase$trimmed';
    }
    if (normalizedBase.isEmpty) {
      return '/$trimmed';
    }
    return '$normalizedBase/$trimmed';
  }

  AppointmentListResponse _decodeAppointmentList(TransportResponse response) {
    return _decodeJson(response, (json) {
      final rawItems = json['items'] as List<dynamic>? ?? const [];
      final items = rawItems
          .map(
            (item) => AppointmentRecord.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList();
      final countsJson = json['counts'] as Map<String, dynamic>?;
      return AppointmentListResponse(
        items: items,
        counts: countsJson == null
            ? AppointmentCounts.fromRecords(items)
            : AppointmentCounts.fromJson(countsJson),
      );
    });
  }

  RecommendationsResponse _decodeRecommendationsResponse(
    TransportResponse response,
  ) {
    return _decodeJson(response, (json) {
      return RecommendationsResponse.fromJson(json);
    });
  }

  CareJournalDetail _decodeCareJournalDetail(TransportResponse response) {
    return _decodeJson(response, (json) {
      return CareJournalDetail.fromJson(json);
    });
  }

  JournalIntegrityReport _decodeJournalIntegrity(TransportResponse response) {
    return _decodeJson(response, (json) {
      return JournalIntegrityReport.fromJson(json);
    });
  }

  JournalEventListResponse _decodeJournalEvents(TransportResponse response) {
    return _decodeJson(response, (json) {
      return JournalEventListResponse.fromJson(json);
    });
  }

  JournalEventResult _decodeJournalEventResult(TransportResponse response) {
    return _decodeJson(response, (json) {
      return JournalEventResult.fromJson(json);
    });
  }

  ReplacementJournalResult _decodeReplacementJournalResult(
    TransportResponse response,
  ) {
    return _decodeJson(response, (json) {
      return ReplacementJournalResult.fromJson(json);
    });
  }

  CareJournalListResponse _decodeCareJournalList(TransportResponse response) {
    return _decodeJson(response, (json) {
      return CareJournalListResponse.fromJson(json);
    });
  }

  List<AppointmentJournalSummary> _decodeAppointmentJournals(
    TransportResponse response,
  ) {
    _throwIfError(response);

    final body = response.body.trim();
    if (body.isEmpty) {
      return const <AppointmentJournalSummary>[];
    }

    final decoded = jsonDecode(body);
    final rawItems = switch (decoded) {
      final List<dynamic> items => items,
      final Map<String, dynamic> json =>
        json['items'] as List<dynamic>? ?? const <dynamic>[],
      _ => const <dynamic>[],
    };
    return rawItems
        .map(
          (item) => AppointmentJournalSummary.fromJson(
            _withResolvedAvatarUrls(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          ),
        )
        .toList();
  }

  Map<String, String> _jsonHeaders() {
    return const {
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
  }

  Map<String, String> _authHeaders(String sessionToken) {
    return {..._jsonHeaders(), 'Authorization': 'Bearer $sessionToken'};
  }

  Map<String, String> _authMultipartHeaders(String sessionToken) {
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $sessionToken',
    };
  }

  UserProfile _decodeProfileResponse(TransportResponse response) {
    return _decodeJson(response, (json) {
      final profileJson = json['profile'] as Map<String, dynamic>? ?? {};
      return UserProfile.fromJson(_withResolvedAvatarUrl(profileJson));
    });
  }

  MasterPublication _decodePublicationResponse(TransportResponse response) {
    return _decodeJson(response, (json) {
      final publicationJson =
          json['publication'] as Map<String, dynamic>? ?? {};
      return MasterPublication.fromJson(publicationJson);
    });
  }

  String _errorMessage(
    TransportResponse response, {
    bool sessionExpiredText = true,
  }) {
    if (response.statusCode == 401 && sessionExpiredText) {
      return 'Сессия истекла. Войдите снова.';
    }

    final body = response.body.trim();
    if (body.isEmpty) {
      return 'Ошибка ${response.statusCode}.';
    }
    return body;
  }

  void _throwIfError(
    TransportResponse response, {
    bool notifyUnauthorized = true,
  }) {
    if (response.statusCode < 400) {
      return;
    }
    if (response.statusCode == 401 && notifyUnauthorized) {
      onUnauthorized?.call();
    }
    throw ApiException(
      _errorMessage(response, sessionExpiredText: notifyUnauthorized),
      statusCode: response.statusCode,
    );
  }
}
