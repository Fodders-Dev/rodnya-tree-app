class FamilyStoryQuestion {
  const FamilyStoryQuestion({
    required this.id,
    required this.title,
    required this.question,
    required this.context,
  });

  final String id;
  final String title;
  final String question;
  final String context;
}

const List<FamilyStoryQuestion> familyStoryQuestions = [
  FamilyStoryQuestion(
    id: 'parents_birthplace',
    title: 'Родители',
    question: 'Где родились твои родители?',
    context: 'Поможет восстановить географию семьи.',
  ),
  FamilyStoryQuestion(
    id: 'grandparents_met',
    title: 'История знакомства',
    question: 'Как познакомились бабушка и дедушка?',
    context: 'Такие истории редко записывают, но их любят пересказывать.',
  ),
  FamilyStoryQuestion(
    id: 'family_legend',
    title: 'Семейная легенда',
    question: 'Какая история в семье передаётся из поколения в поколение?',
    context: 'Хороший первый вопрос, если человек не знает, с чего начать.',
  ),
  FamilyStoryQuestion(
    id: 'old_photos',
    title: 'Старые фотографии',
    question: 'Кто изображён на старых фотографиях?',
    context: 'Помогает подписать фото, пока ещё есть кому вспомнить.',
  ),
  FamilyStoryQuestion(
    id: 'remember_for_children',
    title: 'Что важно помнить',
    question: 'Что ты хочешь, чтобы дети и внуки помнили?',
    context: 'Личный и сильный вопрос для семейной памяти.',
  ),
  FamilyStoryQuestion(
    id: 'childhood_traditions',
    title: 'Традиции детства',
    question: 'Какие семейные традиции были в детстве?',
    context: 'Даёт живые детали про быт, праздники и привычки семьи.',
  ),
  FamilyStoryQuestion(
    id: 'surname_origin',
    title: 'Фамилия',
    question: 'Откуда родом наша фамилия?',
    context: 'Подходит для разговора о корнях и переездах.',
  ),
  FamilyStoryQuestion(
    id: 'great_grandparents',
    title: 'Старшие поколения',
    question: 'Что ты помнишь о своих бабушках и дедушках?',
    context: 'Связывает живую память сразу с несколькими поколениями.',
  ),
];

String buildFamilyStoryShareMessage({
  required FamilyStoryQuestion question,
  required String personName,
  String? relation,
}) {
  final cleanName = personName.trim();
  final cleanRelation = relation?.trim();
  final target = cleanRelation == null || cleanRelation.isEmpty
      ? cleanName
      : '$cleanName ($cleanRelation)';
  return 'Привет! Я собираю семейные истории в Родне про $target.\n\n'
      '${question.question}\n\n'
      'Ответь, пожалуйста, как удобно: текстом или голосом. '
      'Я сохраню ответ в семейной памяти, чтобы дети и внуки тоже знали.';
}

String buildFamilyStoryEditorHint(FamilyStoryQuestion question) {
  return 'Вопрос: ${question.question}\n\n'
      'Когда родственник ответит, вставьте сюда текст или нажмите '
      '«Голос» и надиктуйте историю.';
}
