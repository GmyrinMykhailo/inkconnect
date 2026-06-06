import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme/authenticated_dashboard_theme.dart';
import '../utils/auto_refresh.dart';
import '../widgets/authenticated_mobile_navigation.dart';
import '../widgets/authenticated_page_shell.dart';
import '../widgets/authenticated_sidebar.dart';
import '../widgets/profile_image.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.user,
    required this.userName,
    required this.api,
    required this.sessionToken,
    required this.onOpenHome,
    required this.onOpenSearch,
    required this.onOpenAppointments,
    required this.onOpenMasterAppointments,
    required this.onOpenCareJournal,
    required this.onOpenClientJournals,
    required this.onOpenServicesPrices,
    required this.onOpenRecommendations,
    required this.onOpenProfile,
    required this.onOpenFavorites,
    this.initialPeerUserId,
  });

  final AuthUser? user;
  final String userName;
  final InkConnectApiClient api;
  final String? sessionToken;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMasterAppointments;
  final ValueChanged<String> onOpenCareJournal;
  final VoidCallback onOpenClientJournals;
  final VoidCallback onOpenServicesPrices;
  final VoidCallback onOpenRecommendations;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenFavorites;
  final String? initialPeerUserId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late final AutoRefreshController _threadsAutoRefresh;
  late final AutoRefreshController _messagesAutoRefresh;

  List<ChatThreadSummary> _threads = const <ChatThreadSummary>[];
  List<ChatMessage> _messages = const <ChatMessage>[];
  ChatThreadSummary? _selectedThread;
  bool _loadingThreads = true;
  bool _loadingMessages = false;
  bool _sending = false;
  String? _threadsError;
  String? _messagesError;
  String? _handledInitialPeerId;

  static const _accent = AuthenticatedDashboardTheme.accent;
  static const _text = AuthenticatedDashboardTheme.text;
  static const _muted = AuthenticatedDashboardTheme.muted;
  static const _card = AuthenticatedDashboardTheme.card;
  static const _line = AuthenticatedDashboardTheme.line;
  static const _soft = AuthenticatedDashboardTheme.soft;

  @override
  void initState() {
    super.initState();
    _threadsAutoRefresh = AutoRefreshController(
      interval: const Duration(seconds: 8),
      onRefresh: () => _loadThreads(silent: true),
    )..start();
    _messagesAutoRefresh = AutoRefreshController(
      interval: const Duration(seconds: 3),
      onRefresh: _refreshSelectedMessages,
    )..start();
    _loadThreads().then((_) => _handleInitialPeer());
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.api != widget.api) {
      _selectedThread = null;
      _messages = const <ChatMessage>[];
      _handledInitialPeerId = null;
      _loadThreads().then((_) => _handleInitialPeer());
      return;
    }
    if (oldWidget.initialPeerUserId != widget.initialPeerUserId) {
      _handleInitialPeer();
    }
  }

  @override
  void dispose() {
    _threadsAutoRefresh.dispose();
    _messagesAutoRefresh.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshSelectedMessages() async {
    final thread = _selectedThread;
    if (thread == null) {
      return;
    }
    await _loadMessages(thread, silent: true);
  }

  Future<void> _loadThreads({bool silent = false}) async {
    final token = widget.sessionToken;
    if (token == null || token.isEmpty) {
      if (silent) {
        return;
      }
      setState(() {
        _loadingThreads = false;
        _threadsError = 'Сообщения доступны после входа.';
      });
      return;
    }

    if (!silent) {
      setState(() {
        _loadingThreads = true;
        _threadsError = null;
      });
    }

    try {
      final items = await widget.api.getChatThreads(sessionToken: token);
      if (!mounted) {
        return;
      }
      setState(() {
        _threads = items;
        _loadingThreads = false;
        _threadsError = null;
        if (_selectedThread != null) {
          _selectedThread = _findThread(_selectedThread!.id);
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _threads = const <ChatThreadSummary>[];
        _loadingThreads = false;
        _threadsError = 'Не удалось загрузить сообщения';
      });
    }
  }

  Future<void> _handleInitialPeer() async {
    final peerId = widget.initialPeerUserId?.trim() ?? '';
    if (peerId.isEmpty || peerId == _handledInitialPeerId) {
      return;
    }
    _handledInitialPeerId = peerId;
    await _openOrCreateWithPeer(peerId);
  }

  Future<void> _openOrCreateWithPeer(String peerId) async {
    final token = widget.sessionToken;
    if (token == null || token.isEmpty) {
      _showSnackBar('Войдите, чтобы открыть чат');
      return;
    }
    setState(() {
      _loadingMessages = true;
      _messagesError = null;
    });
    try {
      final thread = await widget.api.getOrCreateChatWithUser(
        sessionToken: token,
        userId: peerId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedThread = thread;
        _upsertThread(thread);
      });
      await _loadMessages(thread);
      unawaited(_loadThreads(silent: true));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMessages = false;
        _messagesError = 'Не удалось открыть чат';
      });
      _showSnackBar('Не удалось открыть чат');
    }
  }

  Future<void> _loadMessages(
    ChatThreadSummary thread, {
    bool silent = false,
  }) async {
    final token = widget.sessionToken;
    if (token == null || token.isEmpty) {
      return;
    }
    final previousLastId = _messages.isEmpty ? '' : _messages.last.id;
    final shouldStickToBottom = !silent || _isNearBottom;
    if (!silent) {
      setState(() {
        _selectedThread = thread;
        _loadingMessages = true;
        _messagesError = null;
      });
    }
    try {
      final items = await widget.api.getChatMessages(
        sessionToken: token,
        threadId: thread.id,
      );
      if (!mounted || _selectedThread?.id != thread.id) {
        return;
      }
      setState(() {
        _selectedThread = thread;
        _messages = items;
        _loadingMessages = false;
        _messagesError = null;
      });
      final nextLastId = items.isEmpty ? '' : items.last.id;
      if (!silent || (shouldStickToBottom && nextLastId != previousLastId)) {
        _scrollToBottom();
      }
    } catch (_) {
      if (!mounted || _selectedThread?.id != thread.id) {
        return;
      }
      if (silent) {
        return;
      }
      setState(() {
        _messages = const <ChatMessage>[];
        _loadingMessages = false;
        _messagesError = 'Не удалось загрузить диалог';
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final token = widget.sessionToken;
    final thread = _selectedThread;
    if (text.isEmpty || token == null || token.isEmpty || thread == null) {
      return;
    }
    setState(() => _sending = true);
    try {
      final message = await widget.api.sendChatMessage(
        sessionToken: token,
        threadId: thread.id,
        text: text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = [..._messages, message];
        _messageController.clear();
        _sending = false;
      });
      _scrollToBottom();
      unawaited(_loadThreads(silent: true));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _sending = false);
      _showSnackBar('Не удалось отправить сообщение');
    }
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.body);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать сообщение'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: 'Введите сообщение'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    final text = edited?.trim() ?? '';
    if (text.isEmpty || text == message.body.trim()) {
      return;
    }
    final token = widget.sessionToken;
    final thread = _selectedThread;
    if (token == null || token.isEmpty || thread == null) {
      return;
    }
    try {
      final updated = await widget.api.editChatMessage(
        sessionToken: token,
        threadId: thread.id,
        messageId: message.id,
        text: text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = [
          for (final item in _messages)
            item.id == updated.id ? updated : item,
        ];
      });
      unawaited(_loadThreads(silent: true));
    } catch (_) {
      _showSnackBar('Не удалось изменить сообщение');
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('После удаления текст сообщения будет скрыт.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final token = widget.sessionToken;
    final thread = _selectedThread;
    if (token == null || token.isEmpty || thread == null) {
      return;
    }
    try {
      final deleted = await widget.api.deleteChatMessage(
        sessionToken: token,
        threadId: thread.id,
        messageId: message.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = [
          for (final item in _messages)
            item.id == deleted.id ? deleted : item,
        ];
      });
      unawaited(_loadThreads(silent: true));
    } catch (_) {
      _showSnackBar('Не удалось удалить сообщение');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthenticatedPageShell(
      user: widget.user,
      userName: widget.userName,
      activeSidebarItem: AuthenticatedSidebarItem.messages,
      activeMobileNavItem: AuthenticatedMobileNavItem.messages,
      onOpenHome: widget.onOpenHome,
      onOpenSearch: widget.onOpenSearch,
      onOpenAppointments: widget.onOpenAppointments,
      onOpenMasterAppointments: widget.onOpenMasterAppointments,
      onOpenMessages: () {},
      onOpenCareJournal: () => widget.onOpenCareJournal('journal'),
      onOpenClientJournals: widget.onOpenClientJournals,
      onOpenServicesPrices: widget.onOpenServicesPrices,
      onOpenRecommendations: widget.onOpenRecommendations,
      onOpenProfile: widget.onOpenProfile,
      onOpenFavorites: widget.onOpenFavorites,
      onMockAction: _showSnackBar,
      bodyBuilder: (context, isDesktop) => _body(isDesktop),
    );
  }

  Widget _body(bool isDesktop) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 32 : 16,
        isDesktop ? 28 : 16,
        isDesktop ? 32 : 16,
        isDesktop ? 32 : 92,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: isDesktop
              ? Row(
                  children: [
                    SizedBox(width: 340, child: _threadList(isDesktop: true)),
                    const SizedBox(width: 18),
                    Expanded(child: _dialogPanel(isDesktop: true)),
                  ],
                )
              : _selectedThread == null
                  ? _threadList(isDesktop: false)
                  : _dialogPanel(isDesktop: false),
        ),
      ),
    );
  }

  Widget _threadList({required bool isDesktop}) {
    return DecoratedBox(
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Сообщения',
                    style: TextStyle(
                      color: _text,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: () => unawaited(_loadThreads()),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          if (_loadingThreads)
            const Expanded(
              child: Center(child: Text('Загружаем сообщения...')),
            )
          else if (_threadsError != null)
            Expanded(
              child: _StateMessage(
                icon: Icons.wifi_off_rounded,
                title: _threadsError!,
                action: OutlinedButton(
                  onPressed: () => unawaited(_loadThreads()),
                  child: const Text('Повторить'),
                ),
              ),
            )
          else if (_threads.isEmpty)
            const Expanded(
              child: _StateMessage(
                icon: Icons.chat_bubble_outline,
                title: 'У вас пока нет сообщений',
                subtitle:
                    'Откройте профиль мастера или запись и нажмите «Написать сообщение».',
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                itemCount: _threads.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final thread = _threads[index];
                  final selected = _selectedThread?.id == thread.id;
                  return _ThreadTile(
                    thread: thread,
                    selected: selected,
                    onTap: () => _loadMessages(thread),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _dialogPanel({required bool isDesktop}) {
    final thread = _selectedThread;
    if (thread == null) {
      return DecoratedBox(
        decoration: _cardDecoration(),
        child: const _StateMessage(
          icon: Icons.chat_outlined,
          title: 'Выберите диалог',
          subtitle: 'Здесь появится переписка с выбранным пользователем.',
        ),
      );
    }
    return DecoratedBox(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _DialogHeader(
            thread: thread,
            showBack: !isDesktop,
            onBack: () => setState(() => _selectedThread = null),
            onRefresh: () => unawaited(_loadMessages(thread)),
          ),
          Expanded(child: _messagesList()),
          _Composer(
            controller: _messageController,
            sending: _sending,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _messagesList() {
    if (_loadingMessages) {
      return const Center(child: Text('Загружаем диалог...'));
    }
    if (_messagesError != null) {
      return _StateMessage(
        icon: Icons.wifi_off_rounded,
        title: _messagesError!,
        action: OutlinedButton(
          onPressed: _selectedThread == null
              ? null
              : () => _loadMessages(_selectedThread!),
          child: const Text('Повторить'),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const _StateMessage(
        icon: Icons.mark_chat_unread_outlined,
        title: 'Сообщений пока нет',
        subtitle: 'Напишите первое сообщение в поле ниже.',
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final mine = message.senderId == widget.user?.id;
        return _MessageBubble(
          message: message,
          mine: mine,
          onEdit: mine && !message.isDeleted ? () => _editMessage(message) : null,
          onDelete:
              mine && !message.isDeleted ? () => _deleteMessage(message) : null,
        );
      },
    );
  }

  void _upsertThread(ChatThreadSummary thread) {
    _threads = [
      thread,
      for (final item in _threads)
        if (item.id != thread.id) item,
    ];
  }

  ChatThreadSummary? _findThread(String id) {
    for (final thread in _threads) {
      if (thread.id == id) {
        return thread;
      }
    }
    return _selectedThread;
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 120;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.selected,
    required this.onTap,
  });

  final ChatThreadSummary thread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = thread.lastMessagePreview.trim().isEmpty
        ? 'Диалог создан'
        : thread.lastMessagePreview.trim();
    return Material(
      color: selected ? _ChatScreenState._soft : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _Avatar(participant: thread.participant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.participant.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ChatScreenState._text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ChatScreenState._muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _shortTime(thread.lastMessageAt.isEmpty
                    ? thread.updatedAt
                    : thread.lastMessageAt),
                style: const TextStyle(
                  color: _ChatScreenState._muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.thread,
    required this.showBack,
    required this.onBack,
    required this.onRefresh,
  });

  final ChatThreadSummary thread;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _ChatScreenState._line)),
      ),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              tooltip: 'Назад',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          _Avatar(participant: thread.participant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.participant.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ChatScreenState._text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'Личные сообщения',
                  style: TextStyle(
                    color: _ChatScreenState._muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.onEdit,
    required this.onDelete,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = screenWidth < 640 ? screenWidth * 0.74 : 460.0;
    final minBubbleWidth = mine ? 154.0 : 96.0;
    final background = message.isDeleted
        ? const Color(0xFFF4F1EC)
        : mine
            ? _ChatScreenState._accent
            : const Color(0xFFF7F8FA);
    final foreground =
        mine && !message.isDeleted ? Colors.white : _ChatScreenState._text;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minBubbleWidth,
          maxWidth: maxBubbleWidth,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            onEdit != null || onDelete != null ? 4 : 16,
            10,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 6),
              bottomRight: Radius.circular(mine ? 6 : 18),
            ),
            border: message.isDeleted
                ? Border.all(color: _ChatScreenState._line)
                : null,
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      message.body,
                      style: TextStyle(
                        color: foreground,
                        fontStyle: message.isDeleted
                            ? FontStyle.italic
                            : FontStyle.normal,
                        height: 1.35,
                      ),
                      softWrap: true,
                    ),
                  ),
                  if (onEdit != null || onDelete != null)
                    PopupMenuButton<String>(
                      tooltip: 'Действия',
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.more_vert, size: 18, color: foreground),
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit?.call();
                        } else if (value == 'delete') {
                          onDelete?.call();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Редактировать'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Удалить'),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                [
                  _shortTime(message.createdAt),
                  if (message.isEdited && !message.isDeleted) 'изменено',
                  if (mine && !message.isDeleted) _statusLabel(message.status),
                ].join(' · '),
                style: TextStyle(
                  color: mine && !message.isDeleted
                      ? Colors.white70
                      : _ChatScreenState._muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _ChatScreenState._line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final sendIcon = sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded, size: 18);
          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: 'Введите сообщение',
                    counterText: '',
                  ),
                  onSubmitted: (_) {
                    if (!sending) {
                      onSend();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              if (compact)
                SizedBox(
                  width: 52,
                  height: 48,
                  child: FilledButton(
                    onPressed: sending ? null : onSend,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: sendIcon,
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: sending ? null : onSend,
                  icon: sendIcon,
                  label: const Text('Отправить'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.participant});

  final ChatParticipant participant;

  @override
  Widget build(BuildContext context) {
    return ProfileImage(
      avatarUrl: participant.avatarUrl,
      letterFallback: participant.title,
      width: 44,
      height: 44,
      circular: true,
      backgroundColor: _ChatScreenState._accent,
      letterStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _ChatScreenState._accent, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ChatScreenState._text,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _ChatScreenState._muted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) {
  return status == 'sent' ? 'Отправлено' : 'Доставлено';
}

String _shortTime(String raw) {
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) {
    return '';
  }
  final h = parsed.hour.toString().padLeft(2, '0');
  final m = parsed.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
