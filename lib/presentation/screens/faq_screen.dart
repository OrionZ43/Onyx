import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void0,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D0420), Color(0xFF03020A)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  children: [
                    ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0x99050410),
                            border: Border(
                              bottom: BorderSide(color: AppColors.glassBorder),
                            ),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.glass,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColors.glassBorder,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 14,
                                    color: AppColors.nebula1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Text(
                                'FAQ / Справка',
                                style: TextStyle(
                                  fontFamily: 'Syne',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.nebula0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor:
                              Colors.transparent, // Hides ExpansionTile borders
                        ),
                        child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: const [
                            _CategoryHeader(title: '📚 Базовые понятия'),
                            SizedBox(height: 12),
                            _FaqAccordion(
                              question: 'Что такое «Подписка»?',
                              answer:
                                  'Подписка — это специальная ссылка (URL), в которой зашифрован список конфигураций прокси-серверов. Приложение скачивает этот список, расшифровывает его и выбирает для вас лучшие варианты. Вы можете использовать как публичные (бесплатные) подписки, так и покупать приватные.',
                            ),
                            SizedBox(height: 8),
                            _FaqAccordion(
                              question: 'Где брать другие подписки?',
                              answer:
                                  'Их можно найти в специализированных Telegram-каналах, на GitHub или купить у провайдеров, предоставляющих услуги VLESS/Shadowsocks. Onyx поддерживает стандартные форматы ссылок (base64 или plain-text).',
                            ),
                            SizedBox(height: 8),
                            _FaqAccordion(
                              question:
                                  'Безопасно ли использовать публичные серверы?',
                              answer:
                                  'Сам протокол VLESS надежно шифрует ваш трафик от провайдера. Однако владелец публичного сервера теоретически может видеть, к каким сайтам вы обращаетесь (но не ваши пароли или переписки, так как сайты используют HTTPS). Для конфиденциальных данных (банки, Госуслуги) мы рекомендуем использовать «Умную маршрутизацию».',
                            ),

                            SizedBox(height: 24),
                            _CategoryHeader(
                              title: '⚙️ Как работает обход блокировок',
                            ),
                            SizedBox(height: 12),
                            _FaqAccordion(
                              question:
                                  'Чем Onyx лучше обычных VPN (OpenVPN, WireGuard)?',
                              answer:
                                  'Обычные VPN-протоколы имеют узнаваемый «почерк» (сигнатуру). Системы блокировок (ТСПУ в РФ) легко распознают их и замедляют или полностью блокируют. Onyx использует современные протоколы (VLESS), которые притворяются обычным интернет-трафиком.',
                            ),
                            SizedBox(height: 8),
                            _FaqAccordion(
                              question: 'Что такое VLESS и Reality?',
                              answer:
                                  'Это маскировка высшего уровня. VLESS Reality не просто шифрует трафик, а «крадет» чужое лицо. Для систем блокировки ваш трафик выглядит так, будто вы просто читаете сайт Microsoft, Apple или загружаете обновления Windows. Заблокировать это — значит сломать половину интернета в стране.',
                            ),
                            SizedBox(height: 8),
                            _FaqAccordion(
                              question:
                                  'Что такое Глубокая проверка (Deep Probe)?',
                              answer:
                                  'В большинстве VPN серверы проверяются обычным «пингом» (TCP). Но в реалиях блокировок сервер может отвечать на пинг, но при этом не пропускать трафик. Deep Probe в Onyx незаметно запускает ядро VPN в фоне и реально пытается открыть сайт. Если тест успешен (статус LIVE) — сервер работает на 100%.',
                            ),

                            SizedBox(height: 24),
                            _CategoryHeader(title: '🛠 Функции приложения'),
                            SizedBox(height: 12),
                            _FaqAccordion(
                              question:
                                  'Что такое Умная маршрутизация (Split Tunneling)?',
                              answer:
                                  'Это функция, которая разделяет ваш интернет надвое. Зарубежные заблокированные сайты (Instagram, YouTube, X) идут через VPN. А все российские сайты (оканчивающиеся на .ru, .рф), Госуслуги, Сбербанк, Яндекс и Авито идут напрямую через вашего провайдера. Это дает максимальную скорость и защищает от блокировок со стороны банков.',
                            ),
                            SizedBox(height: 8),
                            _FaqAccordion(
                              question:
                                  'Почему сервер иногда отключается сам по себе?',
                              answer:
                                  'В Onyx встроен «Монитор здоровья» (Active Health Monitor). ТСПУ иногда может «душить» соединения спустя 10-20 минут работы. Если Onyx замечает, что трафик перестал идти, он автоматически отбраковывает зависший сервер и мгновенно переключает вас на следующий рабочий.',
                            ),
                            SizedBox(height: 8),
                            _FaqAccordion(
                              question:
                                  'Что означают статусы LIVE и MUX у серверов?',
                              answer:
                                  '• LIVE — сервер прошел Глубокую проверку (Deep Probe) и гарантированно работает прямо сейчас.\n• MUX — сервер поддерживает мультиплексирование (Multiplexing). Это технология, которая склеивает множество мелких запросов в один поток, сильно ускоряя загрузку тяжелых страниц и видео.',
                            ),
                            SizedBox(height: 8),
                            _FaqAccordion(
                              question:
                                  'Я нажал крестик / свернул окно, но VPN всё ещё работает. Почему?',
                              answer:
                                  'Onyx — это полноценное десктопное приложение. При закрытии окна оно сворачивается в системный трей (возле часов в правом нижнем углу экрана). Чтобы полностью закрыть VPN, нажмите правой кнопкой мыши по иконке Onyx в трее и выберите «Выход».',
                            ),

                            SizedBox(height: 24),
                            _CategoryHeader(
                              title: '🛡 О проекте и приватности',
                            ),
                            SizedBox(height: 12),
                            _FaqAccordion(
                              question: 'Собирает ли Onyx мои данные или логи?',
                              answer:
                                  'Нет. Onyx — это полностью локальный клиент. Все логи отладки существуют только в оперативной памяти вашего устройства и безвозвратно удаляются при закрытии приложения. Мы не отправляем телеметрию или статистику ни на какие сервера.',
                            ),
                            SizedBox(height: 8),
                            _FaqAccordion(
                              question: 'Кто такой zieng2?',
                              answer:
                                  'Это энтузиаст, который содержит и регулярно обновляет бесплатную универсальную подписки VLESS, используемую в Onyx для быстрого старта (тестовая подписка). Мы выражаем ему огромную благодарность за вклад в свободный интернет!',
                            ),

                            SizedBox(height: 32),
                            GlassCard(
                              padding: EdgeInsets.all(20),
                              borderRadius: 16,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.favorite_rounded,
                                    color: AppColors.ember,
                                    size: 32,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Благодарность',
                                    style: TextStyle(
                                      fontFamily: 'Syne',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.nebula0,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Огромная благодарность энтузиасту zieng2 за создание и поддержку бесплатной универсальной подписки VLESS, которая используется в нашем приложении в качестве тестовой!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'DM Sans',
                                      fontSize: 13,
                                      color: AppColors.nebula1,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Syne',
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.nebula1,
        ),
      ),
    );
  }
}

class _FaqAccordion extends StatelessWidget {
  const _FaqAccordion({required this.question, required this.answer});
  final String question, answer;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(
            fontFamily: 'Syne',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.nebula0,
          ),
        ),
        iconColor: AppColors.nebula1,
        collapsedIconColor: AppColors.nebula1,
        childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Divider(color: AppColors.horizon, height: 1),
          ),
          Text(
            answer,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 13,
              color: AppColors.nebula1,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
