class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.studioName,
    required this.email,
    required this.role,
    required this.publicKey,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      studioName: json['studio_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? '',
      publicKey: json['public_key'] as String? ?? '',
    );
  }

  final String id;
  final String username;
  final String studioName;
  final String email;
  final String role;
  final String publicKey;
}

class LoginResponse {
  const LoginResponse({
    required this.user,
    required this.sessionToken,
    required this.expiresAt,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      sessionToken: json['session_token'] as String? ?? '',
      expiresAt: json['expires_at'] as String? ?? '',
    );
  }

  final AuthUser user;
  final String sessionToken;
  final String expiresAt;
}

class RegistrationResponse {
  const RegistrationResponse({
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    required this.publicKey,
    this.privateKey,
  });

  factory RegistrationResponse.fromJson(Map<String, dynamic> json) {
    return RegistrationResponse(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? '',
      publicKey: json['public_key'] as String? ?? '',
      privateKey: json['private_key'] as String?,
    );
  }

  final String userId;
  final String username;
  final String email;
  final String role;
  final String publicKey;
  final String? privateKey;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.role,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    required this.studioName,
    required this.city,
    required this.bio,
    required this.avatarUrl,
    required this.showFullNameInProfile,
    required this.showCityInProfile,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      role: json['role'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      middleName: json['middle_name'] as String? ?? '',
      studioName: json['studio_name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      showFullNameInProfile:
          json['show_full_name_in_profile'] as bool? ?? false,
      showCityInProfile: json['show_city_in_profile'] as bool? ?? false,
    );
  }

  final String id;
  final String username;
  final String role;
  final String lastName;
  final String firstName;
  final String middleName;
  final String studioName;
  final String city;
  final String bio;
  final String avatarUrl;
  final bool showFullNameInProfile;
  final bool showCityInProfile;
}

class PublicUserProfile {
  const PublicUserProfile({
    required this.id,
    required this.username,
    required this.role,
    required this.displayName,
    required this.fullName,
    required this.city,
    required this.bio,
    required this.avatarUrl,
  });

  factory PublicUserProfile.fromJson(Map<String, dynamic> json) {
    return PublicUserProfile(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      role: json['role'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      fullName: '',
      city: json['city'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
    );
  }

  final String id;
  final String username;
  final String role;
  final String displayName;
  final String fullName;
  final String city;
  final String bio;
  final String avatarUrl;
}

class ProfileUpdatePayload {
  const ProfileUpdatePayload({
    required this.lastName,
    required this.firstName,
    required this.middleName,
    required this.studioName,
    required this.city,
    required this.bio,
    required this.showFullNameInProfile,
    required this.showCityInProfile,
  });

  final String lastName;
  final String firstName;
  final String middleName;
  final String studioName;
  final String city;
  final String bio;
  final bool showFullNameInProfile;
  final bool showCityInProfile;

  Map<String, dynamic> toJson() {
    return {
      'last_name': lastName,
      'first_name': firstName,
      'middle_name': middleName,
      'studio_name': studioName,
      'city': city,
      'bio': bio,
      'show_full_name_in_profile': showFullNameInProfile,
      'show_city_in_profile': showCityInProfile,
    };
  }
}

class PasswordChangePayload {
  const PasswordChangePayload({
    required this.currentPassword,
    required this.newPassword,
    required this.passwordConfirm,
  });

  final String currentPassword;
  final String newPassword;
  final String passwordConfirm;

  Map<String, dynamic> toJson() {
    return {
      'current_password': currentPassword,
      'new_password': newPassword,
      'password_confirm': passwordConfirm,
    };
  }
}

class SecurityContact {
  const SecurityContact({required this.email, required this.phone});

  factory SecurityContact.fromJson(Map<String, dynamic> json) {
    return SecurityContact(
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
    );
  }

  final String email;
  final String phone;
}

class EmailUpdatePayload {
  const EmailUpdatePayload({
    required this.currentPassword,
    required this.email,
  });

  final String currentPassword;
  final String email;

  Map<String, dynamic> toJson() {
    return {'current_password': currentPassword, 'email': email};
  }
}

class PhoneUpdatePayload {
  const PhoneUpdatePayload({
    required this.currentPassword,
    required this.phone,
  });

  final String currentPassword;
  final String phone;

  Map<String, dynamic> toJson() {
    return {'current_password': currentPassword, 'phone': phone};
  }
}

class AccountDeletePayload {
  const AccountDeletePayload({required this.currentPassword});

  final String currentPassword;

  Map<String, dynamic> toJson() {
    return {'current_password': currentPassword};
  }
}

class MasterProfile {
  const MasterProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.fullName,
    required this.studioName,
    required this.role,
    required this.city,
    required this.bio,
    required this.avatarUrl,
    required this.category,
    required this.styles,
    required this.minSessionPrice,
    required this.hourlyRate,
    required this.rating,
    required this.reviewCount,
    required this.isVerified,
    required this.isFavorite,
    required this.services,
    required this.schedule,
  });

  factory MasterProfile.fromJson(Map<String, dynamic> json) {
    final rawStyles = json['styles'] as List<dynamic>? ?? const [];
    final rawServices = json['services'] as List<dynamic>? ?? const [];
    final rawSchedule = json['schedule'] as List<dynamic>? ?? const [];
    return MasterProfile(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      fullName: '',
      studioName: json['studio_name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      city: json['city'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      category: json['category'] as String? ?? '',
      styles: rawStyles.map((style) => style.toString()).toList(),
      minSessionPrice: (json['min_session_price'] as num?)?.round() ?? 0,
      hourlyRate: (json['hourly_rate'] as num?)?.round() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.round() ?? 0,
      isVerified: json['is_verified'] as bool? ?? false,
      isFavorite: json['is_favorite'] as bool? ?? false,
      services: rawServices
          .map(
            (service) => MasterServiceSettings.fromJson(
              service as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
      schedule: rawSchedule
          .map(
            (day) => MasterScheduleDay.fromJson(
              day as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String fullName;
  final String studioName;
  final String role;
  final String city;
  final String bio;
  final String avatarUrl;
  final String category;
  final List<String> styles;
  final int minSessionPrice;
  final int hourlyRate;
  final double rating;
  final int reviewCount;
  final bool isVerified;
  final bool isFavorite;
  final List<MasterServiceSettings> services;
  final List<MasterScheduleDay> schedule;

  MasterSettings toMasterSettingsFallback() {
    return MasterSettings(
      category: category,
      styles: styles,
      minSessionPrice: minSessionPrice,
      hourlyRate: hourlyRate,
      breakBetweenClients: '',
    );
  }
}

class MasterPublication {
  const MasterPublication({
    required this.id,
    required this.masterId,
    required this.description,
    required this.styles,
    required this.commentsDisabled,
    required this.media,
    required this.coverImageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MasterPublication.fromJson(Map<String, dynamic> json) {
    final rawStyles = json['styles'] as List<dynamic>? ?? const [];
    final rawMedia = json['media'] as List<dynamic>? ?? const [];
    return MasterPublication(
      id: json['id'] as String? ?? '',
      masterId: json['master_id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      styles: rawStyles.map((style) => style.toString()).toList(),
      commentsDisabled: json['comments_disabled'] as bool? ?? false,
      media: rawMedia
          .map(
            (item) => MasterPublicationMedia.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
      coverImageUrl: json['cover_image_url'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  final String id;
  final String masterId;
  final String description;
  final List<String> styles;
  final bool commentsDisabled;
  final List<MasterPublicationMedia> media;
  final String coverImageUrl;
  final String createdAt;
  final String updatedAt;

  MasterPublicationMedia? get coverMedia {
    for (final item in media) {
      if (item.isCover) {
        return item;
      }
    }
    return media.isEmpty ? null : media.first;
  }
}

class MasterPublicationMedia {
  const MasterPublicationMedia({
    required this.id,
    required this.imageUrl,
    required this.sortOrder,
    required this.isCover,
  });

  factory MasterPublicationMedia.fromJson(Map<String, dynamic> json) {
    return MasterPublicationMedia(
      id: json['id'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      sortOrder: (json['sort_order'] as num?)?.round() ?? 0,
      isCover: json['is_cover'] as bool? ?? false,
    );
  }

  final String id;
  final String imageUrl;
  final int sortOrder;
  final bool isCover;
}

class PublicationPhotoUploadPayload {
  const PublicationPhotoUploadPayload({
    required this.filename,
    required this.bytes,
  });

  final String filename;
  final List<int> bytes;
}

class MasterSearchResponse {
  const MasterSearchResponse({required this.items, required this.query});

  factory MasterSearchResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return MasterSearchResponse(
      items: rawItems
          .map(
            (item) => MasterProfile.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
      query: json['query'] as String? ?? '',
    );
  }

  final List<MasterProfile> items;
  final String query;
}

class MasterServiceSettings {
  const MasterServiceSettings({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.category = '',
    this.style = '',
    this.durationMinutes = 0,
    required this.durationHours,
    required this.price,
    required this.useAutoPrice,
    required this.fromPrice,
  });

  factory MasterServiceSettings.fromJson(Map<String, dynamic> json) {
    final rawDuration = json['duration_hours'];
    return MasterServiceSettings(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'session',
      category: json['category'] as String? ?? '',
      style: json['style'] as String? ?? '',
      durationMinutes: (json['duration_minutes'] as num?)?.round() ?? 0,
      durationHours: rawDuration is num ? rawDuration.toDouble() : null,
      price: (json['price'] as num?)?.round() ?? 0,
      useAutoPrice: json['use_auto_price'] as bool? ?? false,
      fromPrice: json['from_price'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String description;
  final String type;
  final String category;
  final String style;
  final int durationMinutes;
  final double? durationHours;
  final int price;
  final bool useAutoPrice;
  final bool fromPrice;
}

class MasterServicePayload {
  const MasterServicePayload({
    required this.name,
    required this.description,
    required this.type,
    required this.durationHours,
    required this.price,
    required this.useAutoPrice,
    required this.fromPrice,
  });

  final String name;
  final String description;
  final String type;
  final double? durationHours;
  final int price;
  final bool useAutoPrice;
  final bool fromPrice;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'type': type,
      'duration_hours': durationHours,
      'price': price,
      'use_auto_price': useAutoPrice,
      'from_price': fromPrice,
    };
  }
}

class MasterSettings {
  const MasterSettings({
    required this.category,
    required this.styles,
    required this.minSessionPrice,
    required this.hourlyRate,
    required this.breakBetweenClients,
  });

  factory MasterSettings.fromJson(Map<String, dynamic> json) {
    final rawStyles = json['styles'] as List<dynamic>? ?? const [];
    return MasterSettings(
      category: json['category'] as String? ?? 'Тату-мастер',
      styles: rawStyles.map((style) => style.toString()).toList(),
      minSessionPrice: (json['min_session_price'] as num?)?.round() ?? 5000,
      hourlyRate: (json['hourly_rate'] as num?)?.round() ?? 2500,
      breakBetweenClients:
          json['break_between_clients'] as String? ?? '30 минут',
    );
  }

  final String category;
  final List<String> styles;
  final int minSessionPrice;
  final int hourlyRate;
  final String breakBetweenClients;
}

class MasterSettingsPayload {
  const MasterSettingsPayload({
    required this.category,
    required this.styles,
    required this.minSessionPrice,
    required this.hourlyRate,
    required this.breakBetweenClients,
  });

  final String category;
  final List<String> styles;
  final int minSessionPrice;
  final int hourlyRate;
  final String breakBetweenClients;

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'styles': styles,
      'min_session_price': minSessionPrice,
      'hourly_rate': hourlyRate,
      'break_between_clients': breakBetweenClients,
    };
  }
}

class MasterSchedule {
  const MasterSchedule({required this.days});

  factory MasterSchedule.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List<dynamic>? ?? const [];
    return MasterSchedule(
      days: rawDays
          .map(
            (day) => MasterScheduleDay.fromJson(
              day as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
    );
  }

  final List<MasterScheduleDay> days;

  Map<String, dynamic> toJson() {
    return {'days': days.map((day) => day.toJson()).toList()};
  }
}

class MasterScheduleDay {
  const MasterScheduleDay({
    required this.dayIndex,
    required this.enabled,
    required this.intervals,
  });

  factory MasterScheduleDay.fromJson(Map<String, dynamic> json) {
    final rawIntervals = json['intervals'] as List<dynamic>? ?? const [];
    return MasterScheduleDay(
      dayIndex: (json['day_index'] as num?)?.round() ?? 0,
      enabled: json['enabled'] as bool? ?? false,
      intervals: rawIntervals
          .map(
            (interval) => MasterScheduleInterval.fromJson(
              interval as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
    );
  }

  final int dayIndex;
  final bool enabled;
  final List<MasterScheduleInterval> intervals;

  Map<String, dynamic> toJson() {
    return {
      'day_index': dayIndex,
      'enabled': enabled,
      'intervals': intervals.map((interval) => interval.toJson()).toList(),
    };
  }
}

class MasterScheduleInterval {
  const MasterScheduleInterval({
    required this.type,
    required this.startMinute,
    required this.endMinute,
  });

  factory MasterScheduleInterval.fromJson(Map<String, dynamic> json) {
    return MasterScheduleInterval(
      type: json['type'] as String? ?? 'work',
      startMinute: (json['start_minute'] as num?)?.round() ?? 0,
      endMinute: (json['end_minute'] as num?)?.round() ?? 0,
    );
  }

  final String type;
  final int startMinute;
  final int endMinute;

  Map<String, dynamic> toJson() {
    return {'type': type, 'start_minute': startMinute, 'end_minute': endMinute};
  }
}

class AppointmentPerson {
  const AppointmentPerson({
    required this.id,
    required this.username,
    required this.accountRole,
    required this.isMaster,
    required this.displayName,
    required this.city,
    required this.avatarUrl,
  });

  factory AppointmentPerson.fromJson(Map<String, dynamic> json) {
    return AppointmentPerson(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      accountRole: json['account_role'] as String? ?? '',
      isMaster:
          json['is_master'] as bool? ??
          ((json['account_role'] as String? ?? '') == 'master'),
      displayName: json['display_name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
    );
  }

  final String id;
  final String username;
  final String accountRole;
  final bool isMaster;
  final String displayName;
  final String city;
  final String avatarUrl;
}

class AppointmentRecord {
  const AppointmentRecord({
    required this.id,
    required this.status,
    required this.scheduledAt,
    required this.scheduledEndAt,
    required this.durationMinutes,
    required this.clientNote,
    required this.masterNote,
    required this.createdAt,
    required this.client,
    required this.master,
    required this.service,
    required this.recommendationStatus,
    required this.recommendationStepsCount,
    required this.journalId,
    required this.journalStepsDone,
    required this.journalStepsTotal,
  });

  factory AppointmentRecord.fromJson(Map<String, dynamic> json) {
    return AppointmentRecord(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      scheduledAt: json['scheduled_at'] as String? ?? '',
      scheduledEndAt: json['scheduled_end_at'] as String? ?? '',
      durationMinutes: (json['duration_minutes'] as num?)?.round() ?? 0,
      clientNote: json['client_note'] as String? ?? '',
      masterNote: json['master_note'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      client: AppointmentPerson.fromJson(
        json['client'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      master: AppointmentPerson.fromJson(
        json['master'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      service: MasterServiceSettings.fromJson(
        json['service'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      recommendationStatus: json['recommendation_status'] as String? ?? '',
      recommendationStepsCount:
          (json['recommendation_steps_count'] as num?)?.round() ?? 0,
      journalId: json['journal_id'] as String? ?? '',
      journalStepsDone: (json['journal_steps_done'] as num?)?.round() ?? 0,
      journalStepsTotal: (json['journal_steps_total'] as num?)?.round() ?? 0,
    );
  }

  final String id;
  final String status;
  final String scheduledAt;
  final String scheduledEndAt;
  final int durationMinutes;
  final String clientNote;
  final String masterNote;
  final String createdAt;
  final AppointmentPerson client;
  final AppointmentPerson master;
  final MasterServiceSettings service;
  final String recommendationStatus;
  final int recommendationStepsCount;
  final String journalId;
  final int journalStepsDone;
  final int journalStepsTotal;
}

class AppointmentCounts {
  const AppointmentCounts({
    required this.all,
    required this.pending,
    required this.confirmed,
    required this.cancelled,
    required this.rejected,
    required this.completed,
  });

  factory AppointmentCounts.empty() {
    return const AppointmentCounts(
      all: 0,
      pending: 0,
      confirmed: 0,
      cancelled: 0,
      rejected: 0,
      completed: 0,
    );
  }

  factory AppointmentCounts.fromJson(Map<String, dynamic> json) {
    return AppointmentCounts(
      all: (json['all'] as num?)?.round() ?? 0,
      pending: (json['pending'] as num?)?.round() ?? 0,
      confirmed: (json['confirmed'] as num?)?.round() ?? 0,
      cancelled: (json['cancelled'] as num?)?.round() ?? 0,
      rejected: (json['rejected'] as num?)?.round() ?? 0,
      completed: (json['completed'] as num?)?.round() ?? 0,
    );
  }

  factory AppointmentCounts.fromRecords(List<AppointmentRecord> records) {
    var pending = 0;
    var confirmed = 0;
    var cancelled = 0;
    var rejected = 0;
    var completed = 0;
    for (final record in records) {
      switch (record.status) {
        case 'pending':
          pending++;
          break;
        case 'confirmed':
          confirmed++;
          break;
        case 'cancelled':
          cancelled++;
          break;
        case 'rejected':
          rejected++;
          break;
        case 'completed':
          completed++;
          break;
      }
    }
    return AppointmentCounts(
      all: records.length,
      pending: pending,
      confirmed: confirmed,
      cancelled: cancelled,
      rejected: rejected,
      completed: completed,
    );
  }

  final int all;
  final int pending;
  final int confirmed;
  final int cancelled;
  final int rejected;
  final int completed;

  int get inactive => cancelled + rejected;
}

class AppointmentListResponse {
  const AppointmentListResponse({required this.items, required this.counts});

  final List<AppointmentRecord> items;
  final AppointmentCounts counts;
}

class AppointmentDurationUpdateResponse {
  const AppointmentDurationUpdateResponse({
    required this.appointment,
    required this.warnings,
  });

  factory AppointmentDurationUpdateResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawWarnings = json['warnings'] as List<dynamic>? ?? const [];
    return AppointmentDurationUpdateResponse(
      appointment: AppointmentRecord.fromJson(
        json['appointment'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      warnings: rawWarnings.map((warning) => warning.toString()).toList(),
    );
  }

  final AppointmentRecord appointment;
  final List<String> warnings;
}

class ChatParticipant {
  const ChatParticipant({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.avatarUrl,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String role;
  final String avatarUrl;

  String get title {
    final handle = username.trim();
    if (handle.isEmpty) {
      return 'Собеседник';
    }
    return handle.startsWith('@') ? handle : '@$handle';
  }
}

class ChatThreadSummary {
  const ChatThreadSummary({
    required this.id,
    required this.participant,
    required this.lastMessagePreview,
    required this.lastMessageAt,
    required this.updatedAt,
  });

  factory ChatThreadSummary.fromJson(Map<String, dynamic> json) {
    return ChatThreadSummary(
      id: json['id'] as String? ?? '',
      participant: ChatParticipant.fromJson(
        json['participant'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      lastMessagePreview: json['last_message_preview'] as String? ?? '',
      lastMessageAt: json['last_message_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  final String id;
  final ChatParticipant participant;
  final String lastMessagePreview;
  final String lastMessageAt;
  final String updatedAt;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.editedAt,
    required this.isDeleted,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      threadId: json['thread_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      body: json['body'] as String? ?? '',
      status: json['status'] as String? ?? 'delivered',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      editedAt: json['edited_at'] as String? ?? '',
      isDeleted: json['is_deleted'] as bool? ?? false,
    );
  }

  final String id;
  final String threadId;
  final String senderId;
  final String body;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String editedAt;
  final bool isDeleted;

  bool get isEdited => editedAt.trim().isNotEmpty;
}

class ChatThreadListResponse {
  const ChatThreadListResponse({required this.items});

  factory ChatThreadListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return ChatThreadListResponse(
      items: rawItems
          .map(
            (item) => ChatThreadSummary.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
    );
  }

  final List<ChatThreadSummary> items;
}

class ChatMessageListResponse {
  const ChatMessageListResponse({required this.items});

  factory ChatMessageListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return ChatMessageListResponse(
      items: rawItems
          .map(
            (item) => ChatMessage.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
    );
  }

  final List<ChatMessage> items;
}

class AvailabilitySlot {
  const AvailabilitySlot({
    required this.time,
    required this.available,
    required this.reason,
  });

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) {
    return AvailabilitySlot(
      time: json['time'] as String? ?? '',
      available: json['available'] as bool? ?? false,
      reason: json['reason'] as String? ?? 'outside_schedule',
    );
  }

  final String time;
  final bool available;
  final String reason;
}

class AppointmentCreatePayload {
  const AppointmentCreatePayload({
    required this.masterUsername,
    required this.serviceId,
    required this.scheduledAt,
    required this.clientNote,
  });

  final String masterUsername;
  final String serviceId;
  final String scheduledAt;
  final String clientNote;

  Map<String, dynamic> toJson() {
    return {
      'master_username': masterUsername,
      'service_id': serviceId,
      'scheduled_at': scheduledAt,
      'client_note': clientNote,
    };
  }
}

class RecommendationStep {
  const RecommendationStep({
    required this.id,
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.dueOffsetDays,
    required this.dueAt,
  });

  factory RecommendationStep.fromJson(Map<String, dynamic> json) {
    return RecommendationStep(
      id: json['id'] as String? ?? '',
      stepNumber: (json['step_number'] as num?)?.round() ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      dueOffsetDays: (json['due_offset_days'] as num?)?.round(),
      dueAt: json['due_at'] as String? ?? '',
    );
  }

  final String id;
  final int stepNumber;
  final String title;
  final String description;
  final int? dueOffsetDays;
  final String dueAt;

  Map<String, dynamic> toJson() {
    return {
      'step_number': stepNumber,
      'title': title,
      'description': description,
      if (dueOffsetDays != null) 'due_offset_days': dueOffsetDays,
      if (dueAt.isNotEmpty) 'due_at': dueAt,
    };
  }
}

class RecommendationsPlan {
  const RecommendationsPlan({
    required this.appointmentId,
    required this.journalId,
    required this.status,
    required this.steps,
    required this.createdBy,
    required this.createdAt,
    required this.sentAt,
    required this.approvedAt,
  });

  factory RecommendationsPlan.empty(String appointmentId) {
    return RecommendationsPlan(
      appointmentId: appointmentId,
      journalId: '',
      status: 'draft',
      steps: const [],
      createdBy: '',
      createdAt: '',
      sentAt: '',
      approvedAt: '',
    );
  }

  factory RecommendationsPlan.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List<dynamic>? ?? const [];
    return RecommendationsPlan(
      appointmentId: json['appointment_id'] as String? ?? '',
      journalId: json['journal_id'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      steps: rawSteps
          .map(
            (step) => RecommendationStep.fromJson(
              step as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      sentAt: json['sent_at'] as String? ?? '',
      approvedAt: json['approved_at'] as String? ?? '',
    );
  }

  final String appointmentId;
  final String journalId;
  final String status;
  final List<RecommendationStep> steps;
  final String createdBy;
  final String createdAt;
  final String sentAt;
  final String approvedAt;

  bool get isSent => status == 'sent';
  bool get isApproved => status == 'approved';
}

class RecommendationsSavePayload {
  const RecommendationsSavePayload({required this.steps});

  final List<RecommendationStep> steps;

  Map<String, dynamic> toJson() {
    return {'steps': steps.map((step) => step.toJson()).toList()};
  }
}

class RecommendationsResponse {
  const RecommendationsResponse({
    required this.appointment,
    required this.recommendations,
  });

  factory RecommendationsResponse.fromJson(Map<String, dynamic> json) {
    final appointmentJson = json['appointment'] as Map<String, dynamic>?;
    return RecommendationsResponse(
      appointment: appointmentJson == null
          ? null
          : AppointmentRecord.fromJson(appointmentJson),
      recommendations: RecommendationsPlan.fromJson(
        json['recommendations'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
    );
  }

  final AppointmentRecord? appointment;
  final RecommendationsPlan recommendations;
}

class CareJournalInfo {
  const CareJournalInfo({
    required this.id,
    required this.appointmentId,
    required this.clientId,
    required this.masterId,
    required this.integrityStatus,
    required this.lastVerifiedAt,
    required this.createdAt,
    required this.status,
    required this.rootJournalId,
    required this.parentJournalId,
    required this.replacedByJournalId,
    required this.stoppedAt,
    required this.completedAt,
    required this.stopReason,
    required this.replacementReason,
    required this.finalHash,
  });

  factory CareJournalInfo.fromJson(Map<String, dynamic> json) {
    String nullableString(String key) => json[key] as String? ?? '';

    return CareJournalInfo(
      id: nullableString('id'),
      appointmentId: nullableString('appointment_id'),
      clientId: nullableString('client_id'),
      masterId: nullableString('master_id'),
      integrityStatus: json['integrity_status'] as bool? ?? false,
      lastVerifiedAt: nullableString('last_verified_at'),
      createdAt: nullableString('created_at'),
      status: nullableString('status'),
      rootJournalId: nullableString('root_journal_id'),
      parentJournalId: nullableString('parent_journal_id'),
      replacedByJournalId: nullableString('replaced_by_journal_id'),
      stoppedAt: nullableString('stopped_at'),
      completedAt: nullableString('completed_at'),
      stopReason: nullableString('stop_reason'),
      replacementReason: nullableString('replacement_reason'),
      finalHash: nullableString('final_hash'),
    );
  }

  final String id;
  final String appointmentId;
  final String clientId;
  final String masterId;
  final bool integrityStatus;
  final String lastVerifiedAt;
  final String createdAt;
  final String status;
  final String rootJournalId;
  final String parentJournalId;
  final String replacedByJournalId;
  final String stoppedAt;
  final String completedAt;
  final String stopReason;
  final String replacementReason;
  final String finalHash;
}

class CareJournalStep {
  const CareJournalStep({
    required this.id,
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.dueOffsetDays,
    required this.dueAt,
    required this.confirmedAt,
    required this.deadlineAt,
    required this.status,
  });

  factory CareJournalStep.fromJson(Map<String, dynamic> json) {
    final confirmedAt =
        (json['confirmed_at'] as String?) ??
        (json['completed_at'] as String?) ??
        '';
    final deadlineAt =
        (json['deadline_at'] as String?) ?? (json['due_at'] as String?) ?? '';
    final status =
        json['status'] as String? ??
        (confirmedAt.trim().isNotEmpty ? 'completed_by_client' : 'pending');
    return CareJournalStep(
      id: json['id'] as String? ?? '',
      stepNumber:
          (json['step_number'] as num?)?.round() ??
          (json['day_number'] as num?)?.round() ??
          0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      dueOffsetDays:
          (json['due_offset_days'] as num?)?.round() ??
          (json['day_number'] as num?)?.round(),
      dueAt: json['due_at'] as String? ?? '',
      confirmedAt: confirmedAt,
      deadlineAt: deadlineAt,
      status: status,
    );
  }

  final String id;
  final int stepNumber;
  final String title;
  final String description;
  final int? dueOffsetDays;
  final String dueAt;
  final String confirmedAt;
  final String deadlineAt;
  final String status;

  bool get isConfirmed =>
      confirmedAt.trim().isNotEmpty || status == 'completed_by_client';
}

class CareJournalProgress {
  const CareJournalProgress({
    required this.stepsDone,
    required this.stepsTotal,
    required this.percent,
  });

  factory CareJournalProgress.empty() {
    return const CareJournalProgress(stepsDone: 0, stepsTotal: 0, percent: 0);
  }

  factory CareJournalProgress.fromJson(Map<String, dynamic> json) {
    return CareJournalProgress(
      stepsDone: (json['steps_done'] as num?)?.round() ?? 0,
      stepsTotal: (json['steps_total'] as num?)?.round() ?? 0,
      percent: (json['percent'] as num?)?.round() ?? 0,
    );
  }

  final int stepsDone;
  final int stepsTotal;
  final int percent;
}

class CareJournalSummary {
  const CareJournalSummary({
    required this.journal,
    required this.appointment,
    required this.progress,
  });

  factory CareJournalSummary.fromJson(Map<String, dynamic> json) {
    return CareJournalSummary(
      journal: CareJournalInfo.fromJson(
        json['journal'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      appointment: AppointmentRecord.fromJson(
        json['appointment'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      progress: CareJournalProgress.fromJson(
        json['progress'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }

  final CareJournalInfo journal;
  final AppointmentRecord appointment;
  final CareJournalProgress progress;
}

class CareJournalDetail {
  const CareJournalDetail({
    required this.journal,
    required this.appointment,
    required this.steps,
    required this.progress,
  });

  factory CareJournalDetail.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List<dynamic>? ?? const [];
    return CareJournalDetail(
      journal: CareJournalInfo.fromJson(
        json['journal'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      appointment: AppointmentRecord.fromJson(
        json['appointment'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      steps: rawSteps
          .map(
            (step) => CareJournalStep.fromJson(
              step as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
      progress: CareJournalProgress.fromJson(
        json['progress'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }

  final CareJournalInfo journal;
  final AppointmentRecord appointment;
  final List<CareJournalStep> steps;
  final CareJournalProgress progress;
}

class CareJournalListResponse {
  const CareJournalListResponse({required this.items});

  factory CareJournalListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return CareJournalListResponse(
      items: rawItems
          .map(
            (item) => CareJournalSummary.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
    );
  }

  final List<CareJournalSummary> items;
}

class JournalIntegrityReport {
  const JournalIntegrityReport({
    required this.journalId,
    required this.valid,
    required this.status,
    required this.eventsCount,
    required this.hashedEventsCount,
    required this.unhashedEventsCount,
    required this.signedEventsCount,
    required this.validSignaturesCount,
    required this.invalidSignaturesCount,
    required this.unsignedHashedEventsCount,
    required this.finalHashMatches,
    required this.hasLegacyUnhashedEvents,
    required this.issues,
  });

  factory JournalIntegrityReport.fromJson(Map<String, dynamic> json) {
    final rawIssues = json['issues'] as List<dynamic>? ?? const [];
    return JournalIntegrityReport(
      journalId: json['journal_id'] as String? ?? '',
      valid: json['valid'] as bool? ?? false,
      status: json['status'] as String? ?? 'partial',
      eventsCount: (json['events_count'] as num?)?.round() ?? 0,
      hashedEventsCount: (json['hashed_events_count'] as num?)?.round() ?? 0,
      unhashedEventsCount:
          (json['unhashed_events_count'] as num?)?.round() ?? 0,
      signedEventsCount: (json['signed_events_count'] as num?)?.round() ?? 0,
      validSignaturesCount:
          (json['valid_signatures_count'] as num?)?.round() ?? 0,
      invalidSignaturesCount:
          (json['invalid_signatures_count'] as num?)?.round() ?? 0,
      unsignedHashedEventsCount:
          (json['unsigned_hashed_events_count'] as num?)?.round() ?? 0,
      finalHashMatches: json['final_hash_matches'] as bool? ?? false,
      hasLegacyUnhashedEvents:
          json['has_legacy_unhashed_events'] as bool? ?? false,
      issues: rawIssues.map((issue) => issue.toString()).toList(),
    );
  }

  final String journalId;
  final bool valid;
  final String status;
  final int eventsCount;
  final int hashedEventsCount;
  final int unhashedEventsCount;
  final int signedEventsCount;
  final int validSignaturesCount;
  final int invalidSignaturesCount;
  final int unsignedHashedEventsCount;
  final bool finalHashMatches;
  final bool hasLegacyUnhashedEvents;
  final List<String> issues;
}

class JournalEventRecord {
  const JournalEventRecord({
    required this.id,
    required this.journalId,
    required this.stepId,
    required this.eventType,
    required this.actorRole,
    required this.payload,
    required this.reason,
    required this.createdAt,
    required this.hasHash,
    required this.hasSignature,
  });

  factory JournalEventRecord.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload_json'];
    return JournalEventRecord(
      id: json['id'] as String? ?? '',
      journalId: json['journal_id'] as String? ?? '',
      stepId: json['step_id'] as String? ?? '',
      eventType: json['event_type'] as String? ?? '',
      actorRole: json['actor_role'] as String? ?? '',
      payload: rawPayload is Map<String, dynamic>
          ? rawPayload
          : const <String, dynamic>{},
      reason: json['reason'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      hasHash: json['has_hash'] as bool? ?? false,
      hasSignature: json['has_signature'] as bool? ?? false,
    );
  }

  final String id;
  final String journalId;
  final String stepId;
  final String eventType;
  final String actorRole;
  final Map<String, dynamic> payload;
  final String reason;
  final String createdAt;
  final bool hasHash;
  final bool hasSignature;
}

class JournalEventListResponse {
  const JournalEventListResponse({required this.items});

  factory JournalEventListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return JournalEventListResponse(
      items: rawItems
          .map(
            (item) => JournalEventRecord.fromJson(
              item as Map<String, dynamic>? ?? const <String, dynamic>{},
            ),
          )
          .toList(),
    );
  }

  final List<JournalEventRecord> items;
}

class JournalEventResult {
  const JournalEventResult({
    required this.eventId,
    required this.journalId,
    required this.eventType,
    required this.createdAt,
    required this.signed,
  });

  factory JournalEventResult.fromJson(Map<String, dynamic> json) {
    return JournalEventResult(
      eventId: json['event_id'] as String? ?? '',
      journalId: json['journal_id'] as String? ?? '',
      eventType: json['event_type'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      signed: json['signed'] as bool? ?? false,
    );
  }

  final String eventId;
  final String journalId;
  final String eventType;
  final String createdAt;
  final bool signed;
}

class JournalUnavailabilityPayload {
  const JournalUnavailabilityPayload({
    required this.unavailableFrom,
    required this.unavailableUntil,
    required this.reason,
    required this.comment,
  });

  final String unavailableFrom;
  final String unavailableUntil;
  final String reason;
  final String comment;

  Map<String, dynamic> toJson() {
    return {
      'unavailable_from': unavailableFrom,
      'unavailable_until': unavailableUntil,
      'reason': reason,
      'comment': comment,
    };
  }
}

class JournalClientProblemPayload {
  const JournalClientProblemPayload({
    required this.reason,
    required this.comment,
  });

  final String reason;
  final String comment;

  Map<String, dynamic> toJson() {
    return {'reason': reason, 'comment': comment};
  }
}

class JournalDeadlineExtensionPayload {
  const JournalDeadlineExtensionPayload({
    required this.newDeadlineAt,
    required this.reason,
    this.linkedClientNoticeEventId,
  });

  final String newDeadlineAt;
  final String reason;
  final String? linkedClientNoticeEventId;

  Map<String, dynamic> toJson() {
    return {
      'new_deadline_at': newDeadlineAt,
      'reason': reason,
      if (linkedClientNoticeEventId != null)
        'linked_client_notice_event_id': linkedClientNoticeEventId,
    };
  }
}

class JournalStopPayload {
  const JournalStopPayload({
    required this.reason,
    required this.stopCategory,
    this.linkedClientNoticeEventId,
  });

  final String reason;
  final String stopCategory;
  final String? linkedClientNoticeEventId;

  Map<String, dynamic> toJson() {
    return {
      'reason': reason,
      'stop_category': stopCategory,
      if (linkedClientNoticeEventId != null)
        'linked_client_notice_event_id': linkedClientNoticeEventId,
    };
  }
}

class ReplacementJournalStepPayload {
  const ReplacementJournalStepPayload({
    required this.dayNumber,
    required this.title,
    required this.description,
    this.deadlineAt,
  });

  final int dayNumber;
  final String title;
  final String description;
  final String? deadlineAt;

  Map<String, dynamic> toJson() {
    return {
      'day_number': dayNumber,
      'title': title,
      'description': description,
      if (deadlineAt != null && deadlineAt!.isNotEmpty)
        'deadline_at': deadlineAt,
    };
  }
}

class ReplacementJournalPayload {
  const ReplacementJournalPayload({required this.reason, required this.steps});

  final String reason;
  final List<ReplacementJournalStepPayload> steps;

  Map<String, dynamic> toJson() {
    return {
      'reason': reason,
      'steps': steps.map((step) => step.toJson()).toList(),
    };
  }
}

class ReplacementJournalResult {
  const ReplacementJournalResult({
    required this.parentJournalId,
    required this.newJournalId,
    required this.rootJournalId,
    required this.appointmentId,
    required this.versionNumber,
    required this.stepsCreated,
    required this.eventId,
    required this.parentFinalHash,
    required this.createdAt,
    required this.signed,
  });

  factory ReplacementJournalResult.fromJson(Map<String, dynamic> json) {
    return ReplacementJournalResult(
      parentJournalId: json['parent_journal_id'] as String? ?? '',
      newJournalId: json['new_journal_id'] as String? ?? '',
      rootJournalId: json['root_journal_id'] as String? ?? '',
      appointmentId: json['appointment_id'] as String? ?? '',
      versionNumber: (json['version_number'] as num?)?.round() ?? 0,
      stepsCreated: (json['steps_created'] as num?)?.round() ?? 0,
      eventId: json['event_id'] as String? ?? '',
      parentFinalHash: json['parent_final_hash'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      signed: json['signed'] as bool? ?? false,
    );
  }

  final String parentJournalId;
  final String newJournalId;
  final String rootJournalId;
  final String appointmentId;
  final int versionNumber;
  final int stepsCreated;
  final String eventId;
  final String parentFinalHash;
  final String createdAt;
  final bool signed;
}

class AppointmentJournalSummary {
  const AppointmentJournalSummary({
    required this.id,
    required this.appointmentId,
    required this.status,
    required this.versionNumber,
    required this.parentJournalId,
    required this.rootJournalId,
    required this.replacedByJournalId,
    required this.createdAt,
    required this.stoppedAt,
    required this.completedAt,
    required this.stopReason,
    required this.replacementReason,
    required this.finalHash,
    required this.stepsCount,
    required this.completedStepsCount,
    required this.pendingStepsCount,
    required this.cancelledStepsCount,
    required this.isOpen,
    required this.integrityCheckStatus,
    required this.integrityValid,
    required this.integrityEventsCount,
  });

  factory AppointmentJournalSummary.fromJson(Map<String, dynamic> json) {
    String nullableString(String key) => json[key] as String? ?? '';

    return AppointmentJournalSummary(
      id: nullableString('id'),
      appointmentId: nullableString('appointment_id'),
      status: nullableString('status'),
      versionNumber: (json['version_number'] as num?)?.round() ?? 0,
      parentJournalId: nullableString('parent_journal_id'),
      rootJournalId: nullableString('root_journal_id'),
      replacedByJournalId: nullableString('replaced_by_journal_id'),
      createdAt: nullableString('created_at'),
      stoppedAt: nullableString('stopped_at'),
      completedAt: nullableString('completed_at'),
      stopReason: nullableString('stop_reason'),
      replacementReason: nullableString('replacement_reason'),
      finalHash: nullableString('final_hash'),
      stepsCount: (json['steps_count'] as num?)?.round() ?? 0,
      completedStepsCount:
          (json['completed_steps_count'] as num?)?.round() ?? 0,
      pendingStepsCount: (json['pending_steps_count'] as num?)?.round() ?? 0,
      cancelledStepsCount:
          (json['cancelled_steps_count'] as num?)?.round() ?? 0,
      isOpen: json['is_open'] as bool? ?? false,
      integrityCheckStatus: nullableString('integrity_check_status'),
      integrityValid: json['integrity_valid'] as bool? ?? false,
      integrityEventsCount:
          (json['integrity_events_count'] as num?)?.round() ?? 0,
    );
  }

  final String id;
  final String appointmentId;
  final String status;
  final int versionNumber;
  final String parentJournalId;
  final String rootJournalId;
  final String replacedByJournalId;
  final String createdAt;
  final String stoppedAt;
  final String completedAt;
  final String stopReason;
  final String replacementReason;
  final String finalHash;
  final int stepsCount;
  final int completedStepsCount;
  final int pendingStepsCount;
  final int cancelledStepsCount;
  final bool isOpen;
  final String integrityCheckStatus;
  final bool integrityValid;
  final int integrityEventsCount;
}
