import 'package:flutter/material.dart';

class _LegalSection {
  const _LegalSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

class _LegalDocumentScreen extends StatelessWidget {
  const _LegalDocumentScreen({
    required this.title,
    required this.subtitle,
    required this.sections,
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<_LegalSection> sections;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                for (final section in sections) ...[
                  Text(
                    section.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    section.body,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                  const SizedBox(height: 20),
                ],
                if (footer != null) ...[
                  const Divider(height: 32),
                  SelectableText(
                    footer!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScreen(
      title: 'Политика конфиденциальности',
      subtitle:
          '«Родня» помогает семьям хранить историю рода, общаться в закрытых чатах и обмениваться семейным контентом. Здесь описано, какие данные мы собираем, зачем они нужны и как пользователь может ими управлять.',
      sections: [
        _LegalSection(
          title: '1. Какие данные мы обрабатываем',
          body:
              'Мы обрабатываем данные аккаунта (имя, email, пароль в защищённом виде), профиль пользователя, карточки родственников, связи в семейном дереве, сообщения, вложения, уведомления, технические данные устройства, IP-адрес и push-токены. При использовании RuStore-интеграций также обрабатываются данные, необходимые для работы обновлений, отзывов и покупок в RuStore.',
        ),
        _LegalSection(
          title: '2. Для чего это нужно',
          body:
              'Данные используются для входа в приложение, хранения семейных деревьев, доставки сообщений и уведомлений, загрузки фото и видео, защиты аккаунта, расследования жалоб и улучшения стабильности сервиса. Мы не продаём персональные данные третьим лицам.',
        ),
        _LegalSection(
          title: '3. Хранение и защита',
          body:
              'Данные хранятся на управляемой инфраструктуре «Родни» и у технических провайдеров, которые помогают нам обеспечивать хостинг, доставку медиа и push-уведомления. Мы ограничиваем доступ к данным и применяем разумные меры защиты, но ни один интернет-сервис не может гарантировать абсолютную безопасность.',
        ),
        _LegalSection(
          title: '4. Жалобы, блокировки и безопасность',
          body:
              'В приложении доступны инструменты жалобы и блокировки пользователей. Жалобы рассматриваются вручную, а заблокированный пользователь не должен иметь возможность продолжать личный диалог с тем, кто его заблокировал. Эти меры используются для защиты пользователей и соблюдения правил сервиса.',
        ),
        _LegalSection(
          title: '5. Ваши права',
          body:
              'Пользователь может редактировать профиль, управлять содержимым семейного дерева, удалить аккаунт из настроек приложения и обратиться в поддержку с запросом на доступ, исправление или удаление данных. Удаление аккаунта удаляет сессию и очищает связанные персональные данные в рамках текущего продукта.',
        ),
        _LegalSection(
          title: '6. Контакты',
          body:
              'По вопросам конфиденциальности и обработки данных: ahjkuio@gmail.com. Для обращений по безопасности и жалобам на контент также используйте этот адрес с темой письма «Родня / безопасность».',
        ),
      ],
      footer:
          'Последнее обновление: 12.04.2026. Этот текст предназначен для релизной версии MVP и должен обновляться при изменении состава данных, инфраструктуры или store-интеграций.',
    );
  }
}

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScreen(
      title: 'Условия использования',
      subtitle:
          'Используя «Родню», пользователь соглашается соблюдать правила уважительного общения, не публиковать незаконный контент и не нарушать приватность других членов семьи.',
      sections: [
        _LegalSection(
          title: '1. Назначение сервиса',
          body:
              '«Родня» — закрытый family-first сервис для хранения семейных деревьев, общения и обмена семейным контентом. Приложение предназначено для пользователей 13+.',
        ),
        _LegalSection(
          title: '2. Обязанности пользователя',
          body:
              'Нельзя публиковать контент, нарушающий закон, права третьих лиц, нормы уважительного общения или приватность родственников. Нельзя использовать сервис для спама, мошенничества, травли, выдачи себя за другое лицо и несанкционированного сбора данных.',
        ),
        _LegalSection(
          title: '3. Контент и модерация',
          body:
              'Пользователь отвечает за данные, которые добавляет в дерево, сообщения, посты, комментарии и медиа. Команда сервиса может ограничить доступ к аккаунту или отдельному контенту после жалобы, ручной проверки или при выявлении нарушений.',
        ),
        _LegalSection(
          title: '4. Доступность сервиса',
          body:
              'Мы стремимся поддерживать стабильную работу сервиса, но не гарантируем непрерывную доступность без технических перерывов. В MVP возможны ограничения функциональности, если это требуется для безопасности, миграции инфраструктуры или исправления ошибок.',
        ),
        _LegalSection(
          title: '5. Аккаунт и удаление',
          body:
              'Пользователь может прекратить использование сервиса и удалить аккаунт через настройки приложения. После удаления часть служебных записей может храниться ограниченное время для безопасности, аудита и исполнения правовых обязанностей.',
        ),
      ],
      footer:
          'Если вы не согласны с условиями, прекратите использование приложения и удалите аккаунт через встроенную функцию или по обращению в поддержку.',
    );
  }
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScreen(
      title: 'Поддержка',
      subtitle:
          'Если что-то пошло не так, напишите нам. Для первого релиза RuStore поддержка идёт через email и ручной разбор обращений.',
      sections: [
        _LegalSection(
          title: 'Куда писать',
          body:
              'Email поддержки: ahjkuio@gmail.com\n\nУкажите, пожалуйста, модель устройства, версию Android, версию приложения и краткое описание проблемы. Если ошибка связана с сообщениями, деревом или медиа, добавьте время и шаги воспроизведения.',
        ),
        _LegalSection(
          title: 'По каким вопросам поможем',
          body:
              'Вход и восстановление доступа, проблемы с уведомлениями, ошибки чатов и медиа, удаление аккаунта, жалобы на пользователей и контент, вопросы по релизному функционалу RuStore.',
        ),
        _LegalSection(
          title: 'Безопасность',
          body:
              'Если обращение связано с оскорблениями, спамом, мошенничеством или нарушением приватности, используйте встроенную жалобу в приложении и дублируйте обращение на email с пометкой «Родня / безопасность».',
        ),
      ],
      footer:
          'Базовый SLA для MVP не фиксирован, но критические обращения по входу, безопасности и удалению аккаунта должны разбираться в первую очередь.',
    );
  }
}

class AccountDeletionInfoScreen extends StatelessWidget {
  const AccountDeletionInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScreen(
      title: 'Удаление аккаунта',
      subtitle:
          'Удаление аккаунта доступно прямо в приложении и не требует отдельной формы на стороне магазина.',
      sections: [
        _LegalSection(
          title: 'Как удалить аккаунт',
          body:
              'Откройте Профиль -> Настройки -> Удаление аккаунта. Приложение попросит подтвердить пароль и после подтверждения удалит активную учётную запись.',
        ),
        _LegalSection(
          title: 'Что будет удалено',
          body:
              'Будут удалены сессии, профиль пользователя и связанные персональные данные, которые используются как часть текущего MVP. Если удаление затрагивает семейные деревья, личные чаты, уведомления или жалобы, связанные записи очищаются в рамках серверного контракта приложения.',
        ),
        _LegalSection(
          title: 'Если нет доступа к приложению',
          body:
              'Если вы не можете войти в приложение, отправьте запрос на ahjkuio@gmail.com с адресом почты аккаунта и темой «Родня / удаление аккаунта». Мы используем этот канал как резервный путь поддержки.',
        ),
      ],
      footer:
          'Эта страница сделана как публичный release-ready маршрут для RuStore и должна оставаться доступной без авторизации.',
    );
  }
}
