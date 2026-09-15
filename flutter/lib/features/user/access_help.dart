import 'package:flutter/material.dart';

import '../../core/api_widgets.dart';
import '../../core/widgets.dart';
import '../../data/app_controller.dart';

class ServiceDocumentPage extends StatelessWidget {
  const ServiceDocumentPage({super.key, required this.privacy});
  final bool privacy;

  @override
  Widget build(BuildContext context) => BureauPage(
    title: privacy ? 'Политика конфиденциальности' : 'Правила сервиса',
    subtitle: 'Единое бюро находок · edinburo.ru',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in privacy ? _privacy : _rules) ...[
          SectionTitle(section.$1),
          SelectableText(section.$2),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => pushPage(context, const GuestSupportPage()),
          child: const Text('Обратиться в поддержку'),
        ),
      ],
    ),
  );

  static const _rules = <(String, String)>[
    (
      'Назначение сервиса',
      'Сервис помогает публиковать пропажи и находки, искать похожие вещи и связываться для их возврата. Размещение объявлений бесплатно.',
    ),
    (
      'Публикации',
      'Указывайте достоверные сведения о вещи. Не размещайте чужие контактные данные, документы, коды доступа и другие личные сведения в открытом описании. Для проверки владельца предусмотрены скрытые признаки и доказательства.',
    ),
    (
      'Проверка и совпадения',
      'Публикации проходят модерацию. Описание и совпадения, предложенные ИИ, могут содержать ошибки: проверяйте их перед отправкой. Совпадение не подтверждает право собственности.',
    ),
    (
      'Возврат вещи',
      'Подтверждайте принадлежность вещи через предусмотренный сценарий. Контакты раскрываются после согласия обеих сторон. Выбирайте безопасное место передачи; завершение фиксируется подтверждениями участников.',
    ),
    (
      'Недопустимые действия',
      'Нельзя выдавать чужую вещь за свою, вводить участников в заблуждение, публиковать спам, угрожать, преследовать других пользователей или использовать сервис для незаконных действий. Спорную публикацию или действия участника можно передать на проверку поддержке.',
    ),
    (
      'Обращения',
      'При ошибке или споре обратитесь в поддержку. Если войти не удаётся, доступна форма без авторизации. Не передавайте в обращении SMS-коды, пароли или реквизиты банковских карт.',
    ),
  ];
  static const _privacy = <(String, String)>[
    (
      'Какие данные используются',
      'Для входа используется номер телефона. В аккаунте сохраняются имя, сведения об активных сессиях и данные, которые вы отправляете: публикации, фотографии, место и время события, доказательства, сообщения и обращения. Для ответа на обращение без входа сохраняется указанный вами телефон или электронная почта.',
    ),
    (
      'Что доступно другим',
      'После модерации открыты описание вещи, фотографии, город, дата и общие признаки. Телефон, скрытые признаки и точный адрес не включаются в публичную карточку. Контакты участников возврата раскрываются через отдельный запрос согласия.',
    ),
    (
      'Обработка фотографий',
      'Фотографии проходят обработку и проверку. Для подготовки описания используется OpenAI: выбранное фото передаётся этому сервису. Визуальный поиск сравнивает признаки изображений. Не добавляйте к фотографии сведения, которые не нужны для поиска вещи; проверяйте предложенное описание.',
    ),
    (
      'Вход, карта и уведомления',
      'Для SMS-входа номер передаётся сервису отправки SMS. Карта использует внешнего провайдера. Определение текущего местоположения требует разрешения браузера. Push-уведомления включаются по вашему действию; для доставки сохраняется подписка браузера.',
    ),
    (
      'Защита и технические сведения',
      'Номер телефона, точный адрес и тексты защищённых сообщений хранятся в зашифрованном виде. Доступ к закрытым данным проверяется по аккаунту и роли. Сервис также обрабатывает технические сведения запросов для работы, защиты от злоупотреблений и устранения ошибок.',
    ),
    (
      'Управление данными',
      'В профиле можно изменить имя и завершить сессии. По вопросам исправления, удаления данных или отключения аккаунта обратитесь в поддержку. Укажите, какие данные или публикации затронуты; не отправляйте SMS-коды и пароли. Для защиты аккаунта может потребоваться подтверждение принадлежности данных.',
    ),
  ];
}

class GuestSupportPage extends StatefulWidget {
  const GuestSupportPage({super.key});
  @override
  State<GuestSupportPage> createState() => _GuestSupportPageState();
}

class _GuestSupportPageState extends State<GuestSupportPage> {
  final _form = GlobalKey<FormState>();
  final _contact = TextEditingController();
  final _subject = TextEditingController(text: 'Не удаётся войти');
  final _message = TextEditingController();
  String? _receipt;

  @override
  void dispose() {
    _contact.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Помощь без входа',
    subtitle: 'Проблемы с SMS и доступом к аккаунту',
    bottom: _receipt != null
        ? null
        : ApiButton(
            label: 'Отправить обращение',
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final result = await AppScope.of(context, listen: false).api
                  .createGuestSupportTicket({
                    'contact': _contact.text.trim(),
                    'subject': _subject.text.trim(),
                    'message': _message.text.trim(),
                  });
              if (mounted) setState(() => _receipt = result['id'].toString());
            },
          ),
    child: _receipt != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NoticeCard(
                'Обращение принято. Сохраните номер; он поможет поддержке найти вашу заявку.',
              ),
              const SizedBox(height: 16),
              SelectableText(_receipt!),
              const SizedBox(height: 16),
              const Text('Для связи вы указали:'),
              SelectableText(_contact.text.trim()),
            ],
          )
        : Form(
            key: _form,
            child: Column(
              children: [
                const NoticeCard(
                  'Опишите проблему и укажите телефон или почту для ответа. Не отправляйте SMS-коды, пароли и банковские данные.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contact,
                  maxLength: 254,
                  decoration: const InputDecoration(
                    labelText: 'Телефон или электронная почта',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 5
                      ? 'Укажите контакт для ответа'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subject,
                  maxLength: 180,
                  decoration: const InputDecoration(labelText: 'Тема'),
                  validator: (value) =>
                      (value?.trim().length ?? 0) < 3 ? 'Укажите тему' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _message,
                  maxLength: 4000,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Что произошло?',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 10
                      ? 'Опишите проблему подробнее'
                      : null,
                ),
                TextButton(
                  onPressed: () => pushPage(
                    context,
                    const ServiceDocumentPage(privacy: true),
                  ),
                  child: const Text('Как используются данные обращения'),
                ),
              ],
            ),
          ),
  );
}
