import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/chat_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/profile_service_interface.dart';
import 'package:rodnya/models/chat_attachment.dart';
import 'package:rodnya/models/chat_details.dart';
import 'package:rodnya/models/chat_message.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_tree.dart';
import 'package:rodnya/models/chat_send_progress.dart';
import 'package:rodnya/models/user_profile.dart';
import 'package:rodnya/models/person_dossier.dart';
import 'package:rodnya/screens/user_profile_entry_screen.dart';

class _FakeAuthService implements AuthServiceInterface {
  _FakeAuthService(this._currentUserId);

  final String? _currentUserId;

  @override
  String? get currentUserId => _currentUserId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  _FakeProfileService(this.profiles, {this.currentUserId});

  final Map<String, UserProfile> profiles;
  final String? currentUserId;

  @override
  Future<UserProfile?> getUserProfile(String userId) async => profiles[userId];

  @override
  Future<UserProfile?> getCurrentUserProfile() async =>
      currentUserId == null ? null : profiles[currentUserId!];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  _FakeFamilyTreeService({
    required this.trees,
    required this.peopleByTree,
    this.profiles = const {},
  });

  final List<FamilyTree> trees;
  final Map<String, List<FamilyPerson>> peopleByTree;
  final Map<String, UserProfile> profiles;

  @override
  Future<List<FamilyTree>> getUserTrees() async => trees;

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async =>
      peopleByTree[treeId] ?? const <FamilyPerson>[];

  @override
  Future<PersonDossier> getPersonDossier(String treeId, String personId) async {
    final person = (peopleByTree[treeId] ?? const <FamilyPerson>[])
        .firstWhere((entry) => entry.id == personId);
    final profile = person.userId != null ? profiles[person.userId!] : null;
    if (profile != null) {
      return PersonDossier.fromProfile(profile, treePerson: person);
    }
    return PersonDossier.fromPerson(person);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatService implements ChatServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  Future<String?> getOrCreateChat(String otherUserId) async =>
      'chat-user-1-$otherUserId';

  @override
  Future<void> refreshMessages(String chatId) async {}

  @override
  Future<void> sendMessageToChat({
    required String chatId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
    List<ChatAttachment> forwardedAttachments = const <ChatAttachment>[],
    ChatReplyReference? replyTo,
    String? clientMessageId,
    int? expiresInSeconds,
    void Function(ChatSendProgress progress)? onProgress,
  }) async {}

  @override
  Future<String?> createGroupChat({
    required List<String> participantIds,
    String? title,
    String? treeId,
  }) async =>
      'chat-group-1';

  @override
  Future<String?> createBranchChat({
    required String treeId,
    required List<String> branchRootPersonIds,
    String? title,
  }) async =>
      'chat-branch-1';

  @override
  Future<ChatDetails> getChatDetails(String chatId) async => const ChatDetails(
        chatId: 'chat-group-1',
        type: 'group',
        title: 'Группа',
        participantIds: ['user-1', 'user-2'],
        participants: [
          ChatParticipantSummary(userId: 'user-1', displayName: 'Артем'),
          ChatParticipantSummary(userId: 'user-2', displayName: 'Иван'),
        ],
        branchRoots: [],
      );

  @override
  Future<ChatDetails> renameGroupChat({
    required String chatId,
    required String title,
  }) async =>
      getChatDetails(chatId);

  @override
  Future<ChatDetails> addGroupParticipants({
    required String chatId,
    required List<String> participantIds,
  }) async =>
      getChatDetails(chatId);

  @override
  Future<ChatDetails> removeGroupParticipant({
    required String chatId,
    required String participantId,
  }) async =>
      getChatDetails(chatId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('shows direct actions when profile exists in current trees',
      (tester) async {
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService('user-1'));
    getIt.registerSingleton<ProfileServiceInterface>(
      _FakeProfileService(
        {
          'user-2': UserProfile.create(
            id: 'user-2',
            email: 'user-2@example.com',
            displayName: 'Мария Романова',
            username: 'romanova',
            phoneNumber: '',
            city: 'Москва',
            country: 'Россия',
            bio: 'Собирает семейные фотоархивы.',
            aboutFamily: 'Хранит дома большой семейный архив.',
            education: 'СПбГУ',
            work: 'Историк семьи',
            hometown: 'Ярославль',
            languages: 'Русский, французский',
            interests: 'Архивы, старые фото, поездки по родным местам',
            hiddenProfileSections: const ['contacts'],
          ),
        },
        currentUserId: 'user-2',
      ),
    );
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeFamilyTreeService(
        trees: [
          FamilyTree(
            id: 'tree-1',
            name: 'Историческое дерево',
            description: '',
            creatorId: 'user-1',
            memberIds: const ['user-1'],
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
            isPrivate: false,
            members: const ['user-1'],
          ),
        ],
        peopleByTree: {
          'tree-1': [
            FamilyPerson(
              id: 'person-2',
              treeId: 'tree-1',
              userId: 'user-2',
              name: 'Мария Романова',
              gender: Gender.female,
              isAlive: true,
              createdAt: DateTime(2024, 1, 1),
              updatedAt: DateTime(2024, 1, 1),
            ),
          ],
        },
        profiles: {
          'user-2': UserProfile.create(
            id: 'user-2',
            email: 'user-2@example.com',
            displayName: 'Мария Романова',
            username: 'romanova',
            phoneNumber: '',
            city: 'Москва',
            country: 'Россия',
            bio: 'Собирает семейные фотоархивы.',
            aboutFamily: 'Хранит дома большой семейный архив.',
            education: 'СПбГУ',
            work: 'Историк семьи',
            hometown: 'Ярославль',
            languages: 'Русский, французский',
            interests: 'Архивы, старые фото, поездки по родным местам',
            hiddenProfileSections: const ['contacts'],
          ),
        },
      ),
    );
    getIt.registerSingleton<ChatServiceInterface>(_FakeChatService());

    await tester.pumpWidget(
      const MaterialApp(
        home: UserProfileEntryScreen(userId: 'user-2'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Мария Романова'), findsOneWidget);
    expect(find.text('Написать'), findsOneWidget);
    expect(find.text('Карточка в дереве'), findsOneWidget);
    expect(find.text('Историческое дерево'), findsOneWidget);
    expect(
      find.text(
          'Часть профиля скрыта настройками видимости этого пользователя.'),
      findsOneWidget,
    );
    expect(find.text('Собирает семейные фотоархивы.'), findsOneWidget);
    expect(find.text('Хранит дома большой семейный архив.'), findsOneWidget);
    expect(find.text('СПбГУ'), findsOneWidget);
    expect(find.text('Историк семьи'), findsOneWidget);
    expect(find.text('Ярославль'), findsOneWidget);
    expect(find.text('Русский, французский'), findsOneWidget);
    expect(
      find.text('Архивы, старые фото, поездки по родным местам'),
      findsOneWidget,
    );
    expect(find.text('user-2@example.com'), findsNothing);
  });

  testWidgets('shows self-profile action for current user route',
      (tester) async {
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService('user-1'));
    getIt.registerSingleton<ProfileServiceInterface>(
      _FakeProfileService(
        {
          'user-1': UserProfile.create(
            id: 'user-1',
            email: 'user-1@example.com',
            displayName: 'Алексей Петров',
            username: 'petrov',
            phoneNumber: '',
          ),
        },
        currentUserId: 'user-1',
      ),
    );
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeFamilyTreeService(
          trees: const <FamilyTree>[], peopleByTree: const {}),
    );
    getIt.registerSingleton<ChatServiceInterface>(_FakeChatService());

    await tester.pumpWidget(
      const MaterialApp(
        home: UserProfileEntryScreen(userId: 'user-1'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Открыть мой профиль'), findsOneWidget);
  });

  testWidgets('falls back to tree card when app profile is missing',
      (tester) async {
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService('user-1'));
    getIt.registerSingleton<ProfileServiceInterface>(
      _FakeProfileService(const <String, UserProfile>{},
          currentUserId: 'user-1'),
    );
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeFamilyTreeService(
        trees: [
          FamilyTree(
            id: 'tree-1',
            name: 'Историческое дерево',
            description: '',
            creatorId: 'user-1',
            memberIds: const ['user-1'],
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
            isPrivate: false,
            members: const ['user-1'],
          ),
        ],
        peopleByTree: {
          'tree-1': [
            FamilyPerson(
              id: 'person-2',
              treeId: 'tree-1',
              userId: 'user-2',
              name: 'Мария Романова',
              gender: Gender.female,
              isAlive: true,
              notes: 'Историческая персона в дереве',
              createdAt: DateTime(2024, 1, 1),
              updatedAt: DateTime(2024, 1, 1),
            ),
          ],
        },
      ),
    );
    getIt.registerSingleton<ChatServiceInterface>(_FakeChatService());

    await tester.pumpWidget(
      const MaterialApp(
        home: UserProfileEntryScreen(userId: 'user-2'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Мария Романова'), findsOneWidget);
    expect(
      find.text(
          'Профиль в приложении ещё не заполнен. Открыта карточка человека из дерева.'),
      findsOneWidget,
    );
    expect(find.text('Историческое дерево'), findsOneWidget);
    expect(find.text('Карточка в дереве'), findsOneWidget);
  });
}
