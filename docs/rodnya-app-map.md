# Родня — Единая карта сущностей, прав и экранов (OOUX + Breadboard)

> **Статус:** Живой источник правды (Step 1 & Step 2 по навыку `product-integration-workflow`, **ожидает согласования** до перехода к макетам/коду).  
> **Дата аудита:** 2026-11-27 (проверено по реальному коду `lib/` и `backend/src/`).  
> **Интерактивная схема экранов в FigJam:** [Родня — Карта экранов (Breadboard)](https://www.figma.com/board/S4XrhlvvG6iJput7R6Pnpb) *(вторую диаграмму OOUX-связей не удалось дозагрузить в FigJam из-за исчерпания лимита вызовов MCP на плане Starter, поэтому её актуальная Mermaid-версия встроена прямо в Раздел 1 ниже).*  
> **Правила работы с картой:**
> 1. **Схема → Макет → Код (Integration-first):** перед крупной фичей или переделкой экрана сначала обновляем эту карту, затем согласуем макет + 5-State Matrix, затем пишем код.
> 2. **Delete-first:** старые дубли, мёртвые роуты и legacy-экраны удаляются в том же коммите, а не накрываются сверху.
> 3. **Полный цикл (`CRUD × Роли`):** ни одна пользовательская сущность не вводится без цикла `Создать · Открыть · Изменить/Переименовать · Поделиться · Скрыть/Архивировать · Удалить` (или явно задокументированного ограничения в матрице ниже) с проверкой владельца (`ownerId / creatorId / userId === user.id`), а не хардкодом legacy-роли.

---

## 1. ORCA — Карта сущностей, связей и ролевой модели

### 1.1 Визуальная карта сущностей и основных проблем CRUD/RBAC

```mermaid
flowchart LR
    subgraph sgCore ["Ядро семьи и графа"]
        userProfile["UserProfile и Сеансы"]
        semyaEntity["Semya + SemyaMember (нет restore и delete UI)"]
        familyTree["FamilyTree (нет PATCH rename и isPublic)"]
        familyPerson["FamilyPerson + GraphPerson"]
        familyRelation["FamilyRelation + KinshipCheck"]
    end

    subgraph sgMemory ["Память и истории"]
        profileArticle["ProfileArticle (блоки биографии)"]
        storyRequest["StoryRequest (v2 parity + PATCH + /story/:token)"]
        trashEntity["Trash: DeletedPerson и Post (RBAC закрыт в Wave A)"]
    end

    subgraph sgFeedEntities ["Лента и социальное"]
        postEntity["Post + Comment (полный CRUD)"]
        pollEntity["Poll (PATCH + closeNow + unvote + delete UI)"]
        gatheringEntity["Gathering (PATCH + delete UI)"]
        story24h["Story 24h (архив + delete, 365д)"]
        circleEntity["Circle (CRUD UI + owner/creator + 5-коллекц. перепривязка)"]
    end

    subgraph sgCommEntities ["Общение"]
        chatEntity["Chat (archive/mute/delete + передача createdBy)"]
        chatMessage["ChatMessage (полный CRUD)"]
        callEntity["Call LiveKit (история только в чате)"]
    end

    subgraph sgAccess ["Приглашения и права"]
        semyaInvite["SemyaInvitation (нет decline и preview)"]
        browseToken["SemyaBrowseToken (гостевой просмотр)"]
        editGrant["EditGrant (UI выдачи + отзыв + отказ)"]
        legacyInvite["Legacy TreeInvite + Claim (RBAC усилен)"]
        mergeIdentity["MergeProposal + IdentityClaim"]
    end

    userProfile -->|"состоит в"| semyaEntity
    userProfile -->|"привязан к"| familyPerson
    semyaEntity <-->|"1:1 привязано"| familyTree
    familyTree -->|"содержит"| familyPerson
    familyTree -->|"содержит"| familyRelation
    familyRelation -->|"связывает"| familyPerson
    familyPerson -->|"1:1 биография"| profileArticle
    familyPerson -->|"вопросы о герое"| storyRequest
    storyRequest -->|"добавляет блок"| profileArticle
    familyPerson -->|"soft-delete 30д"| trashEntity

    familyTree -->|"лента"| postEntity
    familyTree -->|"опросы"| pollEntity
    familyTree -->|"встречи"| gatheringEntity
    familyTree -->|"истории"| story24h
    familyTree -->|"круги"| circleEntity
    circleEntity -.->|"аудитория"| postEntity
    postEntity -->|"soft-delete 30д"| trashEntity

    userProfile -->|"участник"| chatEntity
    chatEntity -->|"содержит"| chatMessage
    chatEntity -->|"звонок"| callEntity

    semyaEntity -->|"инвайт"| semyaInvite
    semyaEntity -->|"гостевой доступ"| browseToken
    familyPerson -->|"права правки"| editGrant
    familyPerson -->|"склейка"| mergeIdentity
    legacyInvite -.->|"обходит права"| semyaEntity

    classDef ok fill:#CDF4D3,stroke:#66D575
    classDef warn fill:#FFECBD,stroke:#FFC943
    classDef crit fill:#FFCDC2,stroke:#FF7556

    class familyPerson,familyRelation,profileArticle,storyRequest,postEntity,pollEntity,gatheringEntity,story24h,circleEntity,chatEntity,chatMessage,editGrant,semyaInvite,browseToken ok
    class semyaEntity,familyTree,trashEntity warn
    class legacyInvite crit

    style sgCore fill:#C2E5FF,stroke:#3DADFF
    style sgMemory fill:#DCCCFF,stroke:#874FFF
    style sgFeedEntities fill:#CDF4D3,stroke:#66D575
    style sgCommEntities fill:#C6FAF6,stroke:#5AD8CC
    style sgAccess fill:#FFE0C2,stroke:#FF9E42
```

### 1.2 Ролевая модель и проверки доступа (`backend/src/middleware/access-guards.js`)

| Роль / уровень | Как определяется в коде | Что может по замыслу | Известные оговорки / расхождения |
|---|---|---|---|
| **Owner (`owner`)** | `SemyaMember.role === 'owner'` (ранг 3 в дереве / 2 в семье); либо владелец ресурса (`userId`, `creatorId`, `authorId`) | Управление семьёй, ролями, `hasInviteGrant`, отзыв любых инвайтов/токенов, удаление дерева, управление привязанными персонами | В legacy-пути (`!tree.semyaId` или `RODNYA_FEDERATED_SEMYI_ENABLED=false`) `requireTreeAccess` игнорирует `requiredRole`. `include-rules` проверяет только `tree.creatorId`. Владелец семьи не может модерировать чужие посты/опросы/встречи. |
| **Editor (`editor`)** | `SemyaMember.role === 'editor'`; опционально флаг `hasInviteGrant` | Добавление/правка неклеймленных персон, связей, кругов, мердж (с грантами), публикация в ленте | С `hasInviteGrant` может приглашать и создавать browse/claim-токены. *(Исправлено в Wave A: legacy `TreeInvitation` теперь тоже проверяет `hasInviteGrant` и не позволяет редактору разбанить кикнутого.)* |
| **Viewer (`viewer`)** | `SemyaMember.role === 'viewer'` | Чтение дерева, ленты, биографий, карточек, чатов; правка **только своей** привязанной персоны; реакции, комментарии, голоса в опросах и RSVP во встречах | *(Исправлено в Wave A: `viewer` больше НЕ может публиковать посты/истории/опросы/встречи и НЕ может восстанавливать/чистить чужих людей в `DeletedPerson`.)* |
| **Person Steward / Grantee** | `graphPerson.userId || createdBy` или активный `GraphPersonEditGrant` (`edit`, `soft-delete`, `merge-consent`) | Правка, удаление или склейка конкретной клеймленной персоны | `PUT /persons/:id/attributes` дополнительно требует `_isPersonSteward` даже при наличии `EditGrant`. Выдача и отзыв прав — через `GrantEditAccessSheet` на карточке персоны («Соавторы») и в `/profile/access`; отказ получателя — через `DELETE /v1/me/edit-grants/:grantId` *(Wave B2a)*. |
| **Guest (Anonymous)** | Capability-токен `/story/:token`, `/browse/:token`, публичное дерево `/public/tree/:id` | Ответ на «Спросить историю v2» (аудио/текст/фото), чтение урезанного дерева (`browse`) или публичного дерева (`public`) | У `/public/trees/*` нет переключения приватности после создания дерева. |
| **Admin** | `RODNYA_BACKEND_ADMIN_EMAILS` (`requireAdmin`) | Просмотр и резолв жалоб (`/v1/admin/reports*`), диагностика (`/v1/admin/runtime`, `client-diagnostics`) | Только серверная модерация жалоб; системный доступ. |

### 1.3 Связи объектов (Relationships) и модель хранения

Rodnya использует гибрид PostgreSQL + JSONB (`public.rodnya_state.data` + вынесенные таблицы SPEED-6/7/8b/15 без SQL `FOREIGN KEY` — связи поддерживаются в JS-сторе `backend/src/store/`):

```text
User (id, identityId -> PersonIdentity.id)
 ├── 1:N -> Session (таблица auth_sessions), PushDevice, Notification (таблица notifications)
 ├── 1:1 -> OnboardingState (treeId -> FamilyTree.id, personIds[])
 ├── 1:N -> SemyaMember (semyaId -> Semya.id, role: owner|editor|viewer, hasInviteGrant, hiddenAt)
 ├── 1:N -> Block, Report, ProfileContribution (authorUserId -> targetUserId), KinshipCheck
 └── 0..1 -> PersonIdentity <-> 1:1 GraphPerson (id == identityId, visibility)
                                  ├── 1:N -> GraphPersonEditGrant (scope: edit|soft-delete|merge-consent)
                                  └── 1:N -> GraphRelation

Semya (id, ownerId -> User.id, treeId -> FamilyTree.id [1:1], deletedAt)
 ├── 1:N -> SemyaMember
 ├── 1:N -> SemyaInvitation (inviterUserId, recipientUserId/Email/Phone, token)
 ├── 1:N -> SemyaBrowseToken (createdByUserId, token)
 └── 1:N -> SemyaMemberHiddenPerson (userId, personId)

FamilyTree (id, creatorId -> User.id, semyaId -> Semya.id [nullable], memberIds[], kind: family|friends)
 ├── 1:1 -> Branch (includeRules)
 ├── 1:N -> FamilyPerson (treeId, userId [nullable], identityId, photoGallery[])
 │          ├── 1:1 -> ProfileArticle (blocks[{id, type, content, authorUserId, source}])
 │          ├── 1:N -> PersonAttribute
 │          ├── 1:N -> StoryRequest (requesterUserId, targetUserId [nullable], deliveryMode, shareToken)
 │          └── soft-delete (30d) -> DeletedPerson (таблица deleted_persons)
 ├── 1:N -> FamilyRelation (person1Id, person2Id, unionStatus, parentSetId)
 ├── 1:N -> Circle (kind: all_tree|favorites|descendants_of|ancestors_of|pair|custom) -> CircleMember
 ├── 1:N -> Post (branchIds[], circleId, imageUrls[], anchorPersonIds[])
 │          ├── 1:N -> Comment (2 уровня), PostReaction
 │          └── soft-delete (30d) -> DeletedPost
 ├── 1:N -> Story (24h), Poll, Gathering
 └── legacy -> TreeInvitation, RelationRequest

Chat (id, type: direct|group|branch, participantIds[], createdBy)
 ├── 1:N -> ChatMessage (таблица chat_messages), ChatReaction, ChatDraft, ChatPin
 └── 1:N -> Call (LiveKit room, participantIds[], итог записывается в ChatMessage)
```

### 1.4 Non-Goals и Rabbit Holes (зафиксированные границы)

- **Non-Goals (чего НЕ делаем сейчас):**
  - Не переписываем гибридное хранилище `rodnya_state` в полностью нормализованный SQL без отдельного migration RFC.
  - Не строим корпоративный RBAC-конструктор (хватает `owner / editor (+hasInviteGrant) / viewer` + `person owner / EditGrant` + capability tokens).
  - Не возвращаем RuStore/Supabase, телефоно-поиск (410) и платные подписки в рамках текущего цикла.
  - Не дублируем отдельный экран истории звонков до появления продуктового запроса (звонки живут в таймлайне чата).
- **Rabbit Holes (скрытые ловушки при будущих доработках):**
  1. **Рассинхрон `Semya` ↔ `FamilyTree`:** переименование семьи (`PATCH /v1/semya/:id`) не меняет `tree.name`; удаление дерева бьёт всё хардом + soft-delete семьи, а удаление семьи оставляет дерево без владельца; переименовать дерево нельзя вообще.
  2. **Claimed vs Anonymous `FamilyPerson`:** привязанная к реальному аккаунту карточка защищена `owner` + `EditGrant`, но обходы через legacy `pending/process` или `DeletedPerson` (viewer!) ломают эту защиту.
  3. **Удаление аккаунта (`deleteUser`):** удаление последнего `owner` оставляет бесхозную `Semya`, куда никто не может войти как владелец.
  4. **Выход создателя из группового чата:** *(Закрыто в Wave B2a)* при `leave` / `DELETE` создатель передаёт `createdBy` следующему активному участнику либо пустая группа удаляется.
  5. **Двойной источник правды в приглашениях/онбординге:** старые роуты `/onboarding`, `/complete_profile`, `/invite?treeId=&personId=`, `TreeInvitation` и `/public/tree/*` всё ещё смонтированы и конкурируют с `/setup`, `/invite/:token` и `/browse/:token`.

---

## 2. Матрица жизненного цикла (`Сущность × CRUD × Роли`)

Обозначения: **Back ✓** = эндпоинт есть · **UI ✓** = подключено в интерфейсе · **⚠️** = частично / с оговоркой / без UI · **❌** = отсутствует.

| Сущность | Create | Read / Open | Update / Rename | Share / Access | Archive / Hide / Restore | Delete / Leave | Владелец / Роли | Главный пробел (Back vs UI) |
|---|---|---|---|---|---|---|---|---|
| **1. `UserProfile` / Account** | Back ✓ (`register`, OAuth)<br>UI ✓ (`/login`, `/setup`) | Back ✓ (`profile/me`, `users/:id/profile`)<br>UI ✓ (`/profile`, `/user/:id`) | **Back ✓ (`PATCH /profile/me`, `users/:id/profile` с sync фото, `POST /auth/change-password`)**<br>**UI ✓ (`showProfileEditSheet`, «Вход и безопасность»)** | Back ✓ (поиск, discovery)<br>UI ✓ (`/user/:id`, код) | ❌ нет деактивации | **Back ✓ (`DELETE /auth/account`, `DELETE /auth/providers/:provider`)**<br>**UI ✓ (`SettingsScreen`: отвязка OAuth, удаление без пароля для OAuth)** | Только сам пользователь | Wave B2b закрыл смену пароля в сессии, отвязку OAuth с защитой от потери последнего входа, passwordless delete для OAuth и sync `photoUrl` *(ранее Wave A починил передачу `Semya` и 3 поля GDPR)*; `ProfileNote` решается в P2 |
| **2. `FamilyTree`** | Back ✓ (`POST /trees`)<br>UI ✓ (`/trees/create`) | Back ✓ (`GET /trees`, `GET /:treeId`)<br>UI ✓ (`/trees`, `/tree`) | **Back ✓ (`PATCH /trees/:treeId`)**<br>**UI ✓ (`/trees` меню «Изменить»)** | Back ✓ (`isPrivate` + `publicSlug`)<br>UI ✓ | ❌ нет архива/корзины дерева | Back ✓ (`DELETE /trees/:id`: owner=hard, member=leave)<br>UI ✓ (`/trees`) | Owner / `Semya owner` (исправлено в Wave B1, вкл. `include-rules`) | Синкается с `Semya.name/description`; hard-delete пока без корзины; legacy `/public/trees/*` уберём в Wave C *(Wave B1)* |
| **3. `Semya` & `SemyaMember`** | Back ✓ (`POST /semya` + auto-bind)<br>UI ⚠️ (auto-bind + бейдж в дереве) | Back ✓ (`GET /me/semya`, `/semya/:id`)<br>UI ✓ (`SemyaDetailsScreen`) | Back ✓ (`PATCH /semya/:id`, роли/гранты)<br>UI ✓ (owner, синкает `tree.name`) | Back ✓ (инвайты + browse)<br>UI ✓ | Back ✓ (`SemyaMember` `hiddenAt`; `POST /semya/:id/restore` 90d + `hardDeleteExpired` sweep)<br>UI ⚠️ | Back ✓ (`DELETE /semya/:id` owner soft; `DELETE /membership` leave/kick)<br>**UI ✓ (Leave + Delete для owner)** | `Semya` owner (`editor+hasInviteGrant` для приглашений) | Восстановление `POST /semya/:id/restore` доступно на бэке и чистится `hardDeleteExpired` за 90 дней *(Wave B1)* |
| **4. `SemyaInvitation`** | Back ✓ (`POST /semya/:id/invitation`)<br>UI ✓ (`SemyaInviteScreen`) | Back ✓ (список, нет `GET /:token` preview)<br>UI ✓ (`SemyaInvitationsListScreen`, `/invite/:token`) | ❌ нельзя сменить роль/срок | Back ✓ (токен / email)<br>UI ✓ | ❌ | Back ✓ (`DELETE` отзыв; `accept` по токену; **нет `decline`**)<br>UI ✓ (отзыв/принятие) | Owner или `editor + hasInviteGrant`; принятие по токену | Нет `decline` получателем, нет preview до принятия, нельзя сделать открытую одноразовую ссылку без email/userId/phone |
| **5. `SemyaBrowseToken`** | Back ✓ (`POST /browse-token`)<br>UI ✓ (`ShareBrowseTokenModal`) | Back ✓ (`GET /browse-tokens`, публичный `GET /browse/:token`)<br>UI ✓ (`/browse/:token`, список) | ❌ нет имени/метки и продления срока | Back ✓ (capability-токен)<br>UI ✓ | ❌ | Back ✓ (`DELETE /browse-token/:id`)<br>UI ✓ (отзыв) | Owner, `editor + hasInviteGrant` или `createdByUserId` | Нельзя подписать назначение ссылки или продлить срок |
| **6. Legacy `TreeInvitation` / `Pending` / `RelationRequest`** | Back ✓ (все 3 смонтированы)<br>UI ✓ (`TreeSelector`, `FindRelative`) | **Back ✓ (`pending?direction=incoming\|outgoing\|all`)**<br>**UI ✓ (`RelationRequestsScreen` 2 вкладки, `/trees?tab=invitations`)** | ❌ | ⚠️ `/invite?treeId=&personId=` + `claim-token` | ❌ | **Back ✓ (`DELETE /relation-requests/:id` и `POST /respond {canceled}` для отправителя; `TreeInvitation` в P2)**<br>**UI ✓ («Отозвать» во вкладке «Отправленные»)** | Owner или `editor + hasInviteGrant` *(Wave A)*; `RelationRequest` cancel — только отправитель | `RelationRequest` outgoing + отмена закрыты *(Wave B2b)*; legacy-инвайты ещё дублируют `SemyaInvitation` (консолидация в P2) |
| **7. `FamilyPerson` & `GraphPerson`** | Back ✓ (`POST /persons`, `import`, `pull-person`)<br>UI ✓ (`/relatives/add`, quick-add, pull) | Back ✓ (`persons`, `dossier`, `search`, `graph-persons/:id`)<br>UI ✓ (`/tree`, `/family`, `/relative/details/:id`) | Back ✓ (`PATCH`, медиа, атрибуты, visibility)<br>UI ✓ (полная правка) | Back ✓ (гранты, visibility, pull)<br>UI ⚠️ (нет UI выдачи `EditGrant`) | Back ✓ (soft-delete 30d + `hide-filter`)<br>UI ✓ (скрыть в семье + корзина) | Back ✓ (soft-delete + `unlink`)<br>UI ✓ | Anon: `editor+`; Claimed: owner или `EditGrant` | `GET /persons/:id` не проверяет `hide-filter`; `PUT /attributes` требует `_isPersonSteward` *(Wave A починил отзыв `semyaMembers` при `unlinkUserFromPerson`)* |
| **8. `FamilyRelation` & `KinshipCheck`** | Back ✓ (`POST /relations`, `kinship-checks`)<br>UI ✓ (`AddRelative`, `Tree`, `Discover`) | Back ✓ (`GET /relations`, `graph/relation`)<br>UI ✓ (`RelativeDetails`, `Discover`) | Back ⚠️ (upsert по паре, нет `PATCH /:id`)<br>UI ✓ (смена типа связи) | — | ❌ (нет архива) | Back ✓ (`DELETE /relations/:id` hard; `kinship/revoke`)<br>UI ✓ | `editor+` для связей; инициатор/цель для `KinshipCheck` | В UI нельзя изменить даты брака/развода без пересоздания; `DELETE` сразу hard-delete |
| **9. `ProfileArticle` (Биография)** | Back ✓ (авто при 1-м блоке)<br>UI ✓ (`ProfileArticleEditorScreen`) | Back ✓ (`article`, `article/history`)<br>UI ✓ (`ArticleReadView`, `AllPhotos`, `Voice`, `History`) | Back ✓ (`POST/PATCH/PUT order`)<br>UI ✓ (полный редактор блоков) | ❌ (наследует доступ дерева) | ❌ (история read-only, нет rollback) | Back ⚠️ (удаление только по блоку, не всей статьи)<br>UI ✓ (блок) | `requireGraphPersonEdit(..., "edit")` (LWW) | История изменений без кнопки «Откатить»; при purge персоны `profileArticle` остаётся в БД |
| **10. `StoryRequest` («Спросить историю v2»)** | Back ✓ (`POST /story-requests`)<br>UI ✓ (`FamilyStoryQuestionsSheet`) | Back ✓ (`me/story-requests`, `:id`, `/story/:token`)<br>UI ✓ (строка статуса + текст вопроса, `Notifications`) | **Back ✓ (`PATCH /story-requests/:id`)**<br>**UI ✓ («Изменить» в `StoryRequestStatusLine`)** | Back ✓ (`shareToken` / `/story/:token`)<br>UI ✓ (копия/шаринг) | ❌ (нельзя скрыть завершённые) | Back ⚠️ (`revoke`/`decline`, без hard `DELETE`)<br>UI ✓ (`Отозвать`/`Отклонить`) | Инициатор (`edit` персоны или свой вопрос) и адресат / гость с токеном | Комбинированный ответ (`audio+STT+text+photo`) и `PUT /media` выровнены между `/story/:token` и in-app `StoryRequestAnswerScreen` *(Wave B2a)* |
| **11. `Post`** | Back ✓ (`POST /posts`)<br>UI ✓ (`/post/create`, `/post/album`) | **Back ✓ (`GET /posts/:id`)**<br>**UI ✓ (`PostDetailScreen` `/post/:postId`)** | **Back ✓ (`PATCH /posts/:id`)**<br>**UI ✓ (`PostCard` «Редактировать»)** | Back ✓ (permalink `/post/:id`)<br>UI ✓ | Back ✓ (soft-delete 30d `deletedPosts`)<br>UI ✓ (`TrashScreen`) | Back ✓ (`DELETE` автор / `Semya owner`)<br>UI ✓ | Публикация: `editor+` *(Wave A)*; правка: автор; удаление: автор / `Semya owner` | Полный CRUD закрыт *(Wave B1)* |
| **12. `Comment`** | Back ✓ (`POST /comments`)<br>UI ✓ (`CommentSheet`) | Back ✓ (`GET /comments`)<br>UI ✓ (`CommentSheet`) | **Back ✓ (`PATCH /comments/:id`)**<br>**UI ✓ (inline edit в `CommentSheet`)** | — | ❌ | Back ✓ (`DELETE` автор / пост / `Semya owner`)<br>**UI ✓ (`CommentSheet` меню `⋮`)** | Создание: `viewer+`; правка: автор; удаление: автор коммента/поста или `Semya owner` | Полный CRUD закрыт *(Wave B1)* |
| **13. `Story` (24h)** | Back ✓ (`POST /stories`)<br>UI ✓ (`/stories/create`) | Back ✓ (`GET /stories`, `?includeArchive=true` автору, view, reactions)<br>UI ✓ (`StoryViewerScreen`, `StoryArchiveScreen`) | ❌ нет `PATCH` *(для 24h сторис не требуется)* | Back ✓ (круг / дерево)<br>UI ✓ | **Back ✓ (истёкшие хранятся 365д в архиве автора)**<br>**UI ✓ (`StoryArchiveScreen` + CTA)** | Back ✓ (`DELETE` активные и истёкшие, автор / `Semya owner`)<br>**UI ✓ (просмотрщик + `StoryArchiveScreen`)** | Публикация: `editor+` *(Wave A)*; архив: только автор; удаление: автор или `Semya owner` | Полный цикл архива историй закрыт *(Wave B2a)* |
| **14. `Poll` (Опросы)** | Back ✓ (`POST /polls`)<br>UI ✓ (`/poll/create`) | Back ✓ (`GET /polls`, `:id`, `respond`)<br>UI ✓ (`PollCard` в ленте) | **Back ✓ (`PATCH /polls/:id` + `DELETE /respond`)**<br>**UI ✓ (правка / досрочное закрытие / «Снять голос»)** | — | ❌ | Back ✓ (`DELETE` hard, автор / `Semya owner`)<br>**UI ✓ (`PollCard` меню `⋮`)** | Создание: `editor+` *(Wave A)*; правка: автор; закрытие/удаление: автор / `Semya owner` | Полный CRUD + закрытие + отзыв голоса закрыты *(Wave B1)* |
| **15. `Gathering` (Встречи)** | Back ✓ (`POST /gatherings`)<br>UI ✓ (`/gathering/create`) | **Back ✓ (`GET /gatherings` с опциональным `treeId`)**<br>UI ✓ (`GatheringCard`, `/calendar`) | **Back ✓ (`PATCH /gatherings/:id`)**<br>**UI ✓ (`CreateGatheringScreen` edit mode)** | — | ❌ | Back ✓ (`DELETE` hard, автор / `Semya owner`)<br>**UI ✓ (`GatheringCard` меню `⋮`)** | Создание: `editor+` *(Wave A)*; правка: автор; удаление: автор / `Semya owner` | Полный CRUD + audience mode «Все» закрыты *(Wave B1)* |
| **16. `Chat` & `ChatMessage`** | Back ✓ (`direct`, `groups`, `branches`, `messages`)<br>UI ✓ (`ChatsList`, `ChatScreen`) | Back ✓ (`chats`, `search`, `messages` с `hiddenAt`/`clearedBefore`)<br>UI ✓ (`/chats`, `/chats/view/:id`) | Back ✓ (`title/photo` + **серверные `PATCH /preferences` mute/archive**)<br>**UI ✓ (`ChatsListScreen`, `ChatScreen`, `ChatInfoSheet`)** | Back ⚠️ (пересылка вложениями)<br>UI ✓ | **Back ✓ (`memberPrefs.isArchived`, `notificationLevel`)**<br>**UI ✓ (синхронизация с сервером)** | **Back ✓ (`DELETE /chats/:id` + передача `createdBy` при `leave`)**<br>**UI ✓ (`Удалить чат` / `Удалить у всех` / `Покинуть группу`)** | Группа: участники меняют тему/участников, `createdBy` передаётся при выходе; личный чат: per-user hide/clear | Жизненный цикл и серверные настройки чатов закрыты *(Wave B2a; 2 лишних роута вынесем в Wave C)* |
| **17. `Call` (LiveKit)** | Back ✓ (`POST /calls`)<br>UI ✓ (`ChatScreen`, `ChatsList`) | Back ✓ (`active`, `:callId`)<br>UI ✓ (`CallScreen`) | Back ✓ (`nudge`, `add`)<br>UI ✓ (добавление в звонок) | ❌ | — | Back ✓ (`reject`, `cancel`, `hangup`)<br>UI ✓ | Участники чата/звонка | Отдельного списка истории звонков нет (история в чате — ОК для текущей версии) |
| **18. `Circle` (Аудитории)** | **Back ✓ (`POST /circles`)**<br>**UI ✓ (`ManageCirclesSheet`)** | Back ✓ (`circles`, `audience-presets`, `members`)<br>UI ✓ (`AudiencePicker` + `ManageCirclesSheet`) | **Back ✓ (`PATCH`, `PUT members`)**<br>**UI ✓ (переименов., участники)** | — | ❌ | **Back ✓ (`DELETE custom` + перепривязка `posts/deletedPosts/stories/gatherings/polls` -> `all_tree`)**<br>**UI ✓ (`ManageCirclesSheet`)** | `editor+` на создание; правка/участники/удаление — **автор круга или `owner` `Semya`** | Закрыто в Wave B2b (`SemyaDetailsScreen` + быстрый вход из `AudiencePicker`) |
| **19. `EditGrant`, `Trash`, `MergeProposal`, `IdentityClaim`, `Notification`** | **Back ✓ (`POST grants` + push, `POST /identity-claims`)**<br>**UI ✓ (`GrantEditAccessSheet`)** | **Back ✓ (`issued/edit-grants`, `identity-claims/mine`, `deleted-persons/posts`, `merge-proposals`, `notifications`)**<br>**UI ✓ (`/profile/access`, 2 корзины, `/identity/review` + «Мои запросы личности», `/notifications`)** | Back ✓ (`review`, `conflicts/resolve`, `notifications/read`)<br>UI ✓ | — | Back ✓ (`restore`, `unmerge`)<br>UI ✓ | **Back ✓ (`DELETE grants`, `DELETE /me/edit-grants/:grantId`, `DELETE /identity-claims/:id`, `trash DELETE`)**<br>**UI ✓ («Отозвать» + «Отказаться»)** | `EditGrant`: владелец + отказ получателя; `IdentityClaim`: отзыв заявителем; `Trash`: автор/owner/`editor+` *(Wave A)* | `EditGrant` UI *(Wave B2a)* и `IdentityClaim` cancel UI *(Wave B2b)* закрыты; 2 дубля корзин консолидируются в P2 |

---

## 3. Реестр экранов и маршрутов (Breadboard Inventory)

Всего в проекте **58 файлов `*_screen.dart`** (57 в `lib/screens/` + `kruzhok_recorder_screen.dart` в `lib/widgets/`, содержащих **61 класс экранов** с учётом 4 правовых экранов и 2 классов просмотра историй).

### 3.1 Пять вкладок нижнего бара / Desktop Rail (`StatefulShellRoute`)

| # | Название в UI | Корневой URL | Экран | Бейдж |
|---|---|---|---|---|
| 0 | `Лента` | `/` | `HomeScreen` | Непрочитанные уведомления |
| 1 | `Родные` | `/family` | `RelativesScreen` | Legacy `pendingTreeInvitations` |
| 2 | `Дерево` | `/tree` (`?tree=&name=`) | `TreeViewScreen` | Нет (центр бара; верхний логотип rail ведёт сюда же) |
| 3 | `Чаты` | `/chats` | `ChatsListScreen` | Непрочитанные сообщения |
| 4 | `Профиль` | `/profile` (`?edit=1..3`) | `ProfileScreen` | Нет |

### 3.2 Маршруты-редиректы и перехваты (`AppShellRouteModule` / `AppRouterGuards`)

| URL | Куда перенаправляет | Комментарий |
|---|---|---|
| `/settings` | `/profile/settings` | Короткий алиас настроек |
| `/album` | `/post/album` | Короткий алиас альбома |
| `/relatives` | `/family` | Только корень; подмаршруты `/relatives/add\|edit\|find\|requests\|send_request\|chat` живут наверху |
| `/family?view=tree[&tree=&name=]` | `/tree[?tree=&name=]` | Legacy после выноса дерева на отдельную вкладку |
| `/tree/view/:treeId[?name=]` | `/tree?tree=:treeId[&name=]` | Deep-link из пушей и инвайтов |
| `/profile/edit[?step=0..3]` | `/profile?edit=<step\|1>` | Автооткрывает `showProfileEditSheet` |
| `/post/:postId` | Экран `PostDetailScreen` (`[ОСТАВЛЯЕМ]`) | Полноценный просмотр поста, правка/удаление и переходы из уведомлений *(Wave B1)* |
| `/invite` (`?treeId=&personId=`) | `/` или `/login` | Legacy-ссылка привязки персоны (guard перехватывает до рендера `SizedBox.shrink()`) |

### 3.3 Полный каталог экранов (по группам)

#### A. Корневые вкладки (5)

| Экран (`lib/screens/...`) | Маршрут / Вход | UI-название | Ключевые действия и выходы | Вердикт |
|---|---|---|---|---|
| `home_screen.dart` | `/` | `Родня` + переключатель ветки | Истории, композер, лента, опросы, встречи, `/calendar`, `/post/album`, `/post/search`, `/notifications`, `/setup` (баннер), `/trees`, `/identity/review` | `[ОСТАВЛЯЕМ]` |
| `relatives_screen.dart` | `/family` | `Родные` / `Круг` | Поиск, 3 бакета, `/relative/details/:id`, `/relatives/add/:treeId`, `/relatives/find/:treeId`, `/discover/relatives`, `/relatives/requests/:treeId` | `[ОСТАВЛЯЕМ]` |
| `tree_view_screen.dart` | `/tree` | `Дерево` / `Круг` | Интерактивный граф, тумблер расширенной сети, бейдж `SemyaDetailsScreen`, `/trees`, `/relatives/add`, `/relative/details/:id` | `[ОСТАВЛЯЕМ]` |
| `chats_list_screen.dart` | `/chats` | `Чаты` | Все / Непрочитанные / Архив (локально), создание direct/group/branch/branches чата, переход в `ChatScreen` (split на ≥1100px) | `[ОСТАВЛЯЕМ]` |
| `profile_screen.dart` | `/profile` | `Профиль` | Редактирование (`showProfileEditSheet`), код/шаринг `/user/:id`, входящие правки, `/profile/offline_profiles`, `/profile/stories/archive`, `/profile/settings` | `[ОСТАВЛЯЕМ]` |

#### B. Авторизация и онбординг (7)

| Экран | Маршрут / Вход | UI-название | Ключевые действия и выходы | Вердикт |
|---|---|---|---|---|
| `auth_screen.dart` | `/login` (`?from=`) | `РОДНЯ · Войти / Создать аккаунт` | Email, Google/TG/VK/MAX, `/auth/qr`, `/password_reset`, правовые экраны | `[ОСТАВЛЯЕМ]` |
| `password_reset_screen.dart` | `/password_reset` | `Сброс пароля` | Отправка письма → возврат на `/login` | `[ОСТАВЛЯЕМ]` |
| `reset_password_confirm_screen.dart` | `/reset-password?token=` | `Новый пароль` | Подтверждение токена → `/login` | `[ОСТАВЛЯЕМ]` |
| `qr_login_display_screen.dart` | `/auth/qr` | `Вход по QR` | Polling QR → `/` | `[ОСТАВЛЯЕМ]` |
| `onboarding/onboarding_wizard_screen.dart` | `/setup` | `Старт / О вас / Семья / Готово` | Профиль + первые родные → автосоздание дерева и `Semya` → `/` или `/tree` | `[ОСТАВЛЯЕМ]` |
| `onboarding_screen.dart` | `/onboarding` → redirect `/setup` | — | **Снесён в Wave C1:** старый маршрут редиректит на `/setup` | `[СНЕСЕНО]` |
| `complete_profile_screen.dart` | `/complete_profile` → redirect `/profile?edit=1` | — | **Снесён в Wave C1:** `parsePhoneWithCountryCode` вынесен в `utils/phone_parser.dart`, `/setup` заполняет профиль полностью | `[СНЕСЕНО]` |

#### C. Лента, события, истории, активность (10)

| Экран | Маршрут / Вход | UI-название | Ключевые действия и выходы | Вердикт |
|---|---|---|---|---|
| `create_post_screen.dart` | `/post/create` (`?action=`) | `Новый пост` | Текст, фото/видео/кружок, выбор круга/веток → `/` | `[ОСТАВЛЯЕМ]` (+ добавить режим edit) |
| `post_search_screen.dart` | `/post/search` | `Поиск по постам` | Поиск по постам дерева | `[ОСТАВЛЯЕМ]` |
| `family_album_screen.dart` | `/post/album` | `Альбом семьи` | Сетка фото из постов, лайтбокс, добавление фото-поста | `[ОСТАВЛЯЕМ]` |
| `family_calendar_screen.dart` | `/calendar` | `Календарь` | Дни рождения и встречи → `/gathering/create?date=`, `/relative/details/:id` | `[ОСТАВЛЯЕМ]` |
| `create_gathering_screen.dart` | `/gathering/create` (`?date=`) | `Новая встреча` | Создание встречи, аудитория → `/` или `/calendar` | `[ОСТАВЛЯЕМ]` (+ edit/delete) |
| `create_poll_screen.dart` | `/poll/create` | `Новый опрос` | Вопрос, варианты, дедлайн, аудитория → `/` | `[ОСТАВЛЯЕМ]` (+ edit/delete) |
| `create_story_screen.dart` | `/stories/create` | `История` | 24ч фото/видео/кружок/текст → `/` | `[ОСТАВЛЯЕМ]` |
| `story_viewer_screen.dart` | `/stories/view/:treeId/:authorId` | Имя автора (полный экран) | Просмотр, реакции, удаление своей истории | `[ОСТАВЛЯЕМ]` |
| `story_archive_screen.dart` | `/profile/stories/archive` | `Архив историй` | Архив истёкших историй автора (`includeArchive=true`), удаление, лайтбокс, CTA «Создать историю» *(Wave B2a)* | `[ОСТАВЛЯЕМ]` |
| `notifications_screen.dart` | `/notifications` | `Активность` | Уведомления + блок «Мне задали вопрос» → `/story-requests/:id/answer`, дерево, чат, инвайт | `[ОСТАВЛЯЕМ]` |

#### D. Дерево, публичный просмотр и поиск родных (11)

| Экран | Маршрут / Вход | UI-название | Ключевые действия и выходы | Вердикт |
|---|---|---|---|---|
| `tree_selector_screen.dart` | `/trees` (`?tab=invitations`) | `Деревья` | Выбор, `/trees/create`, удаление/выход, legacy `TreeInvitation`s | `[ОСТАВЛЯЕМ]` (убрать legacy инвайты) |
| `family_tree/create_tree_screen.dart` | `/trees/create` (`?kind=`) | `Новое дерево` | Имя, тип, приватность, `IncludeRules`, авто-создание `Semya` | `[ОСТАВЛЯЕМ]` (+ поддержать edit) |
| `add_relative_screen.dart` | `/relatives/add/:treeId`, `/relatives/edit/:treeId/:personId` | `Добавление / Редактирование родственника` | Создание/правка/удаление персоны, создание связи | `[ОСТАВЛЯЕМ]` |
| `find_relative_screen.dart` | `/relatives/find/:treeId` | `Найти родственника` | Поиск по Email/Коду/Ссылке → отправка `RelationRequest` | `[ОБЪЕДИНИТЬ]` с `/discover/relatives` |
| `discover_relatives/discover_relatives_screen.dart` | `/discover/relatives` | `Найти родню` | Bilateral `KinshipCheck` («мы родственники?»), цепочка графа | `[ОБЪЕДИНИТЬ]` (основной поиск родных) |
| `relation_requests_screen.dart` | `/relatives/requests/:treeId` | `Запросы на родство` | Принять/отклонить legacy `RelationRequest` | `[ОБЪЕДИНИТЬ]` с общим центром запросов |
| `send_relation_request_screen.dart` | ~~`/relatives/send_request/:treeId` и `/send_relation_request`~~ | — | **Снесён в Wave C1** вместе с 2 мёртвыми роутами и `page_transitions.dart` | `[СНЕСЕНО]` |
| `identity_review_screen.dart` | `/identity/review` | `Один человек?` | Мердж-предложения, клеймы, публичный discovery | `[ОСТАВЛЯЕМ]` |
| `browse_tree_screen.dart` | `/browse/:browseToken` | `<semyaName>` / `Дерево семьи` | Анонимный просмотр по токену + `PullPersonSheet` в своё дерево | `[ОСТАВЛЯЕМ]` (целевой гостевой режим) |
| `public_tree_entry_screen.dart` | `/public/tree/:publicTreeId` | `Публичное дерево` | Legacy-лендинг публичного дерева | `[ОБЪЕДИНИТЬ → СНЕСТИ]` в `/browse/:token` |
| `public_tree_viewer_screen.dart` | `/public/tree/:publicTreeId/view` | `Публичный просмотр` | Legacy read-only канвас без отзыва токена | `[ОБЪЕДИНИТЬ → СНЕСТИ]` в `/browse/:token` |

#### E. Карточка человека, биография и «Спросить историю» (8)

| Экран | Маршрут / Вход | UI-название | Ключевые действия и выходы | Вердикт |
|---|---|---|---|---|
| `relative_details_screen.dart` | `/relative/details/:personId` (`?treeId=&action=`) | `<person.displayName>` | Досье, связи, фото, биография, `FamilyStoryQuestionsSheet`, правка, чат | `[ОСТАВЛЯЕМ]` |
| `user_profile_entry_screen.dart` | `/user/:userId` | `Мой профиль / Профиль` | Резолв чужого/своего профиля из ленты/ссылки | `[ОСТАВЛЯЕМ]` |
| `profile_article_editor_screen.dart` | `/relative/details/:personId/biography` *(Wave C1)* | `<personName> / Биография` | Блоки текста/цитат/заголовков/фото/аудио, порядок, удаление | `[ОСТАВЛЯЕМ]` *(GoRouter ✓)* |
| `profile_article_history_screen.dart` | `Navigator.push` из `RelativeDetailsScreen` | `История изменений` | Аудит правок биографии (пока read-only) | `[ОСТАВЛЯЕМ]` |
| `profile_all_photos_screen.dart` | `Navigator.push` из `RelativeDetailsScreen` | `Все фото` | Сетка всех фото персоны → лайтбокс | `[ОСТАВЛЯЕМ]` |
| `profile_voice_recordings_screen.dart` | `Navigator.push` из `RelativeDetailsScreen` | `Голосовые записи` | Список/плеер всех аудио-блоков | `[ОСТАВЛЯЕМ]` |
| `profile_visibility_screen.dart` | `Navigator.push` из `RelativeDetailsScreen` | `Кто видит карточку` | Настройка видимости в графе + override 100-летнего правила | `[ОСТАВЛЯЕМ]` |
| `story_request_answer_screen.dart` | `/story-requests/:id/answer` | `Вопрос от родного` | Ответ голосом/текстом/фото или отказ → `ProfileArticle` | `[ОСТАВЛЯЕМ]` |

#### F. Семья (`Semya`) и приглашения (5)

| Экран | Маршрут / Вход | UI-название | Ключевые действия и выходы | Вердикт |
|---|---|---|---|---|
| `semya_details_screen.dart` | `/semya/:semyaId` (`?section=hidden`) *(Wave C1)* | `<semya.name>` / `Семья` | Участники, роли, переименование, инвайты, browse-ссылки, скрытые, удалённые, выход | `[ОСТАВЛЯЕМ]` *(GoRouter ✓)* |
| `semya_invitations_list_screen.dart` | `Navigator.push` из `SemyaDetailsScreen` | `Приглашения` | Список инвайтов, копирование, отзыв, кнопка `+` | `[ОСТАВЛЯЕМ]` |
| `semya_invite_screen.dart` | `Navigator.push` из `SemyaInvitationsListScreen` | `Пригласить в семью` | Роль, адресат, генерация `/invite/:token` | `[ОСТАВЛЯЕМ]` |
| `semya_invitation_accept_screen.dart` | `/invite/:token` | `Приглашение в семью` | Авто-принятие по токену + переход в дерево | `[ОСТАВЛЯЕМ]` |
| `semya_deleted_persons_screen.dart` | `/profile/trash?semyaId=` *(Wave C1)* | — | **Снесён в Wave C1:** объединён с `TrashScreen` | `[СНЕСЕНО]` |

#### G. Чаты, звонки и кружки (3 файла, включая `lib/widgets/kruzhok_recorder_screen.dart`)

| Экран | Маршрут / Вход | UI-название | Ключевые действия и выходы | Вердикт |
|---|---|---|---|---|
| `chat_screen.dart` | `/chats/view/:chatId` (канон) **+ `/chat/:userId`** *(дубль `/relatives/chat/:userId` снесён в Wave C1)* | `<title>` / `Чат` | Сообщения, ответы, правка, удаление, пересылка, закреп, кружки/голос, звонок, `ChatInfoSheet` | `[ОСТАВЛЯЕМ]` |
| `call_screen.dart` | `Navigator.push` из `CallRuntimeHost` | `Аудиозвонок / Видеозвонок / таймер` | LiveKit звонок 1:1 и группа, PiP, ростер, чат в звонке | `[ОСТАВЛЯЕМ]` |
| `lib/widgets/kruzhok_recorder_screen.dart` | `Navigator.push` (fullscreenDialog) | `Кружок / История / Видео` | Запись видеокружка для сторис и постов | `[ОСТАВЛЯЕМ]` |

#### H. Настройки, безопасность, корзина и право (9 файлов / 12 классов + служебные)

| Экран | Маршрут / Вход | UI-название | Ключевые действия и выходы | Вердикт |
|---|---|---|---|---|
| `settings_screen.dart` | `/profile/settings` (`/settings`) | `Настройки` | Тема, уведомления, `Моя семья`, скрытые, корзина, доступы, сеансы, блокировки, звонки, APK, выход, удаление аккаунта | `[ОСТАВЛЯЕМ]` |
| `access_grants_screen.dart` | `/profile/access` | `Доступы` | Вкладки «Кому я разрешил» / «Что мне разрешено», выдача (`GrantEditAccessSheet`), отзыв и «Отказаться» *(Wave B2a)* | `[ОСТАВЛЯЕМ]` |
| `blocked_users_screen.dart` | `/profile/blocks` | `Заблокированные пользователи` | Просмотр и разблокировка | `[ОСТАВЛЯЕМ]` |
| `sessions_screen.dart` | `/profile/sessions` | `Активные сеансы` | Переименование устройства, отзыв сеанса, вход в QR-сканер | `[ОСТАВЛЯЕМ]` |
| `qr_login_scan_screen.dart` | `/profile/sessions/scan` | `Сканировать QR` | Подтверждение QR-входа на десктопе/вебе | `[ОСТАВЛЯЕМ]` |
| `offline_profiles_screen.dart` | `/profile/offline_profiles` | `Созданные профили` | Список офлайн-карточек пользователя → `/relative/details/:id` | `[ОСТАВЛЯЕМ]` |
| `trash_screen.dart` | `/profile/trash` (`?semyaId=&semyaName=`) *(Wave C1)* | `Корзина` / `Удалённые · <семя>` | Единая корзина: «Родственники» и «Посты» глобально + режим по `semyaId` (30 дней, восстановление / purge) | `[ОСТАВЛЯЕМ]` *(объединён ✓)* |
| `about_screen.dart` | `/profile/about` | `О приложении` | Версия + переходы в правовые разделы | `[ОСТАВЛЯЕМ]` |
| `privacy_policy_screen.dart` (4 класса) | `/privacy`, `/terms`, `/support`, `/account-deletion` | `Политика`, `Соглашение`, `Поддержка`, `Удаление аккаунта` | Публичные информационные экраны | `[ОСТАВЛЯЕМ]` |
| Служебные виджеты/оверлеи | `/__e2e__/idle`, `MediaLightbox`, `_MandatoryUpdateScreen`, `_GalleryViewer`, `PersonMultiPickerSheet` | — | Вспомогательные системные оверлеи и лайтбоксы | `[ОСТАВЛЯЕМ]` (прим.: `lib/navigation/page_transitions.dart` — 0 импортов → `[СНЕСТИ]`) |

### 3.4 Инфраструктурные долги навигации
- **Оставшиеся `Navigator.push` экраны (после Wave C1 — переведены в GoRouter `SemyaDetailsScreen`, `TrashScreen`, `ProfileArticleEditorScreen`):** `SemyaInvitationsListScreen`, `SemyaInviteScreen`, `ProfileArticleHistoryScreen`, `ProfileAllPhotosScreen`, `ProfileVoiceRecordingsScreen`, `ProfileVisibilityScreen`, `CallScreen`, `KruzhokRecorderScreen`.
- **Android App Links (`app_links_dynamic_link_service.dart`):** синхронизирован в Wave C1 (`/post/:id`, `/user/:id`, `/notifications`, `/relative/details/:id`, `/discover/relatives`, `/semya/:id`, `/profile/trash`, `/chats/view/:id`, `/chat/:userId`, `/stories/view/...`, с исключением `/oauth/*` и `/story/:token`).

---

## 4. Приоритизированный бэклог закрытия пробелов

### P0 — Критические дыры RBAC, безопасности и целостности данных — ✅ Закрыто в Wave A (2026-11-27)
1. **`DeletedPerson` с проверкой роли и владельца (`backend/src/store/domains/persons-trees.js`, `pg-deleted-persons.js`):** ✅ Закрыто в Wave A — `viewer` больше не может восстанавливать или удалять навсегда карточки (`403`); для анонимных карточек нужен `editor+`, для claimed — владелец карточки или `EditGrant(soft-delete)`.
2. **Legacy `TreeInvitation` приведён к правам `Semya` (`backend/src/routes/tree-invitation-routes.js`, `relations.js`):** ✅ Закрыто в Wave A — проверяется `hasInviteGrant`, а повторное приглашение/разбан кикнутого разрешены только активному `owner` семьи (`403 KICKED_FROM_SEMYA`).
3. **`POST /v1/invitations/pending/process` + claim-токены (`backend/src/routes/pending-invitation-routes.js`, `auth-users.js`):** ✅ Закрыто в Wave A — блокирует ушедших (`400`) и заблокированных (`403`), добавлен одноразовый серверный `POST /v1/trees/:treeId/persons/:personId/claim-token` (с гейтом `RODNYA_REQUIRE_PERSON_CLAIM_TOKEN` для строгой проверки старых ссылок).
4. **`DELETE /v1/trees/:treeId/persons/:personId/user-link` (`unlinkUserFromPerson`):** ✅ Закрыто в Wave A — отвязка не-владельца теперь также скрывает его строку `semyaMembers` (`hiddenAt`), сразу закрывая доступ к федеративному дереву.
5. **`deleteUser` каскады (`backend/src/store/domains/auth-users.js`, `pg-cascades-fastpaths.js`):** ✅ Закрыто в Wave A — передача владения `Semya` и `tree.creatorId` при удалении последнего `owner` (или soft-delete пустой `Semya`), чистка `semyaInvitations`/`browseTokens`/`hiddenPersons`/`onboardingStates`/`deletedPersons`/`deletedPosts` (вкл. PG-таблицу) и исправление 3 имён полей GDPR (`authorUserId`, `claimantUserId`, `proposedByUserId`/`reviewerUserIds`).
6. **`POST /v1/posts|stories|polls|gatherings` RBAC и модерация (`post-routes.js`, `story-routes.js`, `poll-routes.js`, `gathering-routes.js`):** ✅ Закрыто в Wave A — публикация переведена на `editor+` (`viewer` сохраняет комментарии, реакции, голосование и RSVP), активный `Semya owner` может удалять/модерировать чужие публикации и комментарии в семье, а все 10 вызовов `_userCanAccessTreeRecord` получили `db`.

### P1 — Закрытие дыр `CRUD × Роли` («Создать есть — Изменить/Удалить нет»)
1. **Лента (Посты, Комментарии, Опросы, Встречи) — ✅ Закрыто в Wave B1 (2026-11-27):**
   - Подключены в UI `deletePoll` (`PollCard`), `deleteGathering` (`GatheringCard`) и `deleteComment` (`CommentSheet`), с поддержкой модерации `Semya owner`.
   - Добавлены `PATCH /v1/posts/:postId`, `PATCH /v1/posts/:postId/comments/:commentId`, `PATCH /v1/polls/:pollId` (+ `closeNow`), `DELETE /v1/polls/:pollId/respond` («Снять голос») и `PATCH /v1/gatherings/:gatheringId` на бэкенде и во Flutter UI (`PostCard`, inline edit в `CommentSheet`, диалог `PollCard`, edit mode в `CreateGatheringScreen`).
   - Добавлен `GET /v1/posts/:postId`, полноценный маршрут `/post/:postId` (`PostDetailScreen`, 5-State Matrix) и `GET /v1/gatherings` без обязательного `treeId` (audience mode).
2. **`Semya` ↔ `FamilyTree` синхронизация и полный цикл — ✅ Закрыто в Wave B1 (2026-11-27):**
   - Добавлены `GET /v1/trees/:treeId` и `PATCH /v1/trees/:treeId` (переименование, описание, `isPrivate`, `publicSlug`) + диалог редактирования дерева в `TreeSelectorScreen`; `semya.name/description ↔ tree.name/description` синхронизируются в обе стороны.
   - Заменён хардкод `tree.creatorId` в `updateBranchIncludeRules` (`graph-visibility.js`) и `restoreSemya` (`semyi.js`) на проверку активного `Semya owner`; `_userCanAccessTreeRecord` больше не раскрывает дерево мягко удалённой `Semya`.
   - Добавлены `POST /v1/semya/:id/restore` (90 дней), sweep `db.semyi` (90д) в `hardDeleteExpired` (`FileStore` + `PostgresStore` `_deletedPersonsTable`), и UI-кнопка «Удалить семью» для `owner` на `SemyaDetailsScreen`.
3. **Права, чаты и память — ✅ Закрыто в Wave B2a (2026-11-27):**
   - Добавлен `GrantEditAccessSheet` + кнопка «Соавторы» на карточке человека и «Выдать доступ» в `/profile/access`, уведомление `edit_grant_received`, а также `DELETE /v1/me/edit-grants/:grantId` и кнопка «Отказаться» для получателя гранта (при сохранении owner-only запрета на `DELETE /v1/graph-persons/:id/grants/:grantId`).
   - Добавлены серверные `memberPrefs` (`PATCH /v1/chats/:chatId/preferences`: `isArchived`, `notificationLevel` с подавлением пушей для `muted`), `DELETE /v1/chats/:chatId` (скрытие/очистка `direct`, выход/удаление группы с передачей `createdBy` следующему участнику) и синхронизация во Flutter (`ChatsListScreen`, `ChatScreen`, `ChatInfoSheet`).
   - Включён реальный «Архив историй» (`GET /v1/stories?includeArchive=true` только для автора, ретеншн 365 дней в maintenance sweep, удаление истёкших историй в `StoryArchiveScreen` + CTA «Создать историю»).
   - Выровнен in-app ответ «Спросить историю v2» с гостевым `/story/:token`: комбинированный ответ `audio + STT + text + photo` через `PUT /v1/story-requests/:id/media` + `POST /answer`, а также редактирование вопроса `PATCH /v1/story-requests/:id` (`_EditStoryRequestDialog` в `StoryRequestStatusLine`).
4. **Прочие точечные пробелы владения — ✅ Закрыто в Wave B2b (2026-11-27):**
   - Добавлены отмена исходящего `RelationRequest` отправителем (`GET /v1/relation-requests/pending?direction=outgoing|all`, `POST /respond {response:"canceled"}`, `DELETE /v1/relation-requests/:id`, 2 вкладки на `RelationRequestsScreen`) и просмотр/отзыв собственного `IdentityClaim` (`GET /v1/identity-claims/mine`, `DELETE /v1/identity-claims/:id`, секция «Мои запросы личности» на `IdentityReviewScreen`).
   - Введена проверка владельца `Circle` (`createdBy` или active `Semya owner`) при правке/смене участников/удалении, перепривязка `posts`, `deletedPosts[].snapshot`, `stories`, `gatherings` и `polls` к `all_tree` при удалении кастомного круга, а также полный CRUD UI (`ManageCirclesSheet` в `SemyaDetailsScreen` и `AudiencePicker`).
   - Добавлен sync `photoUrl` в `PATCH /v1/users/:userId/profile` (плюс фикс `photoGallery` в `syncUserPhotoToTreePersons`), сессионная смена/задание пароля (`POST /v1/auth/change-password`), отвязка OAuth-провайдеров (`DELETE /v1/auth/providers/:provider` с защитой `409 LAST_LOGIN_METHOD`), UI «Вход и безопасность» и passwordless delete для OAuth-аккаунтов в `SettingsScreen`.

### P2 — Delete-first и консолидация экранов/маршрутов
1. **Мгновенная чистка мёртвого кода — ✅ Закрыто в Wave C1 (2026-11-27):** удалены `SendRelationRequestScreen` + 2 мёртвых роута (`/relatives/send_request/:treeId`, `/send_relation_request`), `lib/navigation/page_transitions.dart`, дубль `/relatives/chat/:userId` (с переносом `UrlUtils.normalizeImageUrl` в `/chat/:userId`), а также неиспользуемый `ProfileNote` во Flutter и на бэке.
2. **Консолидация 3 онбордингов → 1 — ✅ Закрыто в Wave C1 (2026-11-27):** оставлен единый `/setup` (`OnboardingWizardScreen` с опциональной датой рождения; `seedOnboarding` заполняет `firstName`, `lastName` и уникальный `username`), удалены `OnboardingScreen`/`OnboardingService` и `CompleteProfileScreen` (парсер телефона перенесён в `lib/utils/phone_parser.dart`, `/onboarding` → `/setup`, `/complete_profile` → `/profile?edit=1`).
3. **Консолидация 3 инвайт-потоков → 1 (Wave C2):** добавить preview (`GET /v1/invitation/:token`) и `decline` к `SemyaInvitation`, и поэтапно вывести legacy `TreeInvitation` и `/invite?treeId=&personId=`.
4. **Консолидация 2 публичных просмотров → 1 (Wave C2):** мигрировать `/public/tree/*` на отзываемый `SemyaBrowseToken` (`/browse/:token`).
5. **Консолидация поиска родных и корзин — ⚠️ Частично закрыто (корзины ✅ в Wave C1):** объединены `TrashScreen` и `SemyaDeletedPersonsScreen` в единый `/profile/trash` (`?semyaId=&semyaName=`). Поиск родных (`/relatives/find/:treeId` + `/discover/relatives`) консолидируется в Wave C2.
6. **Маршрутизация — ✅ Закрыто в Wave C1 (2026-11-27):** переведены в `GoRouter` `SemyaDetailsScreen` (`/semya/:semyaId`), `TrashScreen` (`/profile/trash`) и `ProfileArticleEditorScreen` (`/relative/details/:personId/biography`), а `AppLinksDynamicLinkService` + `AndroidManifest.xml` синхронизированы со всеми активными deep-link маршрутами.

---

## 5. Стандарт 5-State Matrix (обязателен на Step 3 и Step 4)

Любой новый или переделываемый экран (начиная со следующих волн) перед кодом и перед пушем должен быть проверен во всех **5 состояниях**:
1. **Default (Идеальное):** реальные данные (кириллица, фото, роли `owner / editor / viewer`).
2. **Loading / Skeleton:** явный индикатор/скелетон без мигания пустым состоянием и без блокировки всего UI на долгий таймаут.
3. **Empty (Пустое):** понятный текст на русском и **1 чёткий CTA** (никогда не тупик вроде пустого `StoryArchiveScreen`).
4. **Error / Offline / 403:** человекочитаемое сообщение (`humanizeError`), кнопка «Повторить» или безопасный возврат при нехватке прав/удалении сущности.
5. **Edge Cases:** телефоны **360–375 px**, узкий десктоп/планшет **~860–900 px**, широкий **Web ≥ 1100 px**, длинные ФИО/названия семьи, переключение роли или отвязка профиля в реальном времени.

---

## Приложение: исходный код Breadboard для справки

```mermaid
flowchart LR
    subgraph sgEntry ["Вход и внешние ссылки"]
        authLogin["Вход и QR (/login)"]
        setupWizard["Мастер старта (/setup)"]
        legacyOnboard["УДАЛЕНО: /onboarding + /complete_profile → redirect"]
        inviteAccept["Инвайт семьи (/invite/:token)"]
        storyGuest["Гостевая история SSR (/story/:token)"]
        browseVsPublic["ОБЪЕДИНИТЬ: /browse/:token vs /public/tree/*"]
    end

    subgraph sgFeed ["Лента и события (Tab 1)"]
        homeFeed["Лента (/)"]
        feedComposers["Создать: Пост, Опрос, Встреча, История"]
        feedHubs["Альбом, Календарь, Поиск"]
        activityInbox["Активность (/notifications)"]
        storyAnswer["Ответ на вопрос (/story-requests/:id)"]
    end

    subgraph sgFamilyTree ["Родные и Дерево (Tabs 2 и 3)"]
        relativesTab["Родные (/family)"]
        treeTab["Дерево (/tree)"]
        treeSelector["Деревья (/trees и /trees/create)"]
        personDetails["Карточка родного (/relative/details/:id)"]
        personSubScreens["Биография, Фото, Голос, Видимость"]
        discoverDup["ОБЪЕДИНИТЬ: /discover vs /relatives/find"]
    end

    subgraph sgComm ["Чаты и звонки (Tab 4)"]
        chatsList["Чаты (/chats)"]
        chatScreen["Чат (/chats/view/:id)"]
        callScreen["Звонок LiveKit (CallScreen)"]
    end

    subgraph sgProfile ["Профиль, Семья и Настройки (Tab 5)"]
        profileTab["Профиль (/profile)"]
        settingsHub["Настройки (/profile/settings)"]
        semyaHub["Семья (/semya/:id)"]
        trashDup["Корзина (/profile/trash?semyaId=)"]
        securitySub["Сеансы, Доступы, Блокировки, Право"]
    end

    subgraph sgDelete ["Снесено в Wave C1 / к сносу в C2"]
        sendReqDead["СНЕСЕНО: SendRelationRequestScreen + page_transitions"]
        chatRouteDup["СНЕСЕНО: дубль /relatives/chat/:id + ProfileNote"]
        legacyInviteDead["СНЕСТИ в C2: /invite legacy и /public/tree"]
    end

    authLogin -->|"новый пользователь"| setupWizard
    authLogin -.->|"обходной legacy-путь"| legacyOnboard
    authLogin -->|"после входа"| homeFeed
    setupWizard -->|"создаёт дерево и семью"| homeFeed
    legacyOnboard -.-> homeFeed
    inviteAccept -->|"принял инвайт"| treeTab
    inviteAccept -.->|"заменяет"| legacyInviteDead
    browseVsPublic -->|"перетянуть родного"| treeTab
    storyGuest -->|"добавляет блок"| personSubScreens

    homeFeed --> feedComposers
    homeFeed --> feedHubs
    homeFeed --> activityInbox
    homeFeed --> treeSelector
    activityInbox -->|"входящий вопрос"| storyAnswer
    storyAnswer -->|"блок в биографию"| personSubScreens

    relativesTab --> personDetails
    relativesTab --> discoverDup
    relativesTab -.->|"мёртвый роут"| sendReqDead
    treeTab --> treeSelector
    treeTab --> personDetails
    treeTab -->|"бейдж семьи"| semyaHub
    personDetails --> personSubScreens
    personDetails -->|"спросить гостя"| storyGuest
    personDetails -->|"написать"| chatScreen

    chatsList --> chatScreen
    chatsList -.->|"дубль роута"| chatRouteDup
    chatScreen --> callScreen

    profileTab --> settingsHub
    settingsHub --> semyaHub
    settingsHub --> trashDup
    settingsHub --> securitySub
    semyaHub -->|"удалённые семьи"| trashDup
    semyaHub -->|"ссылка просмотра"| browseVsPublic
    semyaHub -->|"ссылка инвайта"| inviteAccept

    classDef core fill:#CDF4D3,stroke:#66D575
    classDef merge fill:#FFECBD,stroke:#FFC943
    classDef remove fill:#FFCDC2,stroke:#FF7556

    class homeFeed,relativesTab,treeTab,chatsList,profileTab core
    class legacyOnboard,browseVsPublic,discoverDup,trashDup merge
    class sendReqDead,chatRouteDup,legacyInviteDead remove

    style sgEntry fill:#F5F5F5,stroke:#B3B3B3
    style sgFeed fill:#CDF4D3,stroke:#66D575
    style sgFamilyTree fill:#C2E5FF,stroke:#3DADFF
    style sgComm fill:#C6FAF6,stroke:#5AD8CC
    style sgProfile fill:#DCCCFF,stroke:#874FFF
    style sgDelete fill:#FFCDC2,stroke:#FF7556
```
