import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Shared «Пригласить в Родню» bottom sheet.
///
/// On phones the OS share sheet works well — there's a real list of
/// installed messengers that can receive a `text/plain` payload. On
/// PC the Windows native share dialog shows the same `share_plus`
/// targets (WhatsApp, Outlook, Teams, Discord) but they often fail
/// silently because the host messenger isn't logged in / installed
/// the way the share-target API expects. The user spotted this:
/// «отправить в мои мессенджеры/просто скопировать у меня на пк не
/// получается».
///
/// Solution: surface two choices instead of going straight to the
/// system share. «Скопировать ссылку» is the always-works fallback
/// (puts the URL on the clipboard, shows a snackbar). «Поделиться
/// через…» runs the regular `SharePlus` flow for the cases where
/// the system share works just fine.
///
/// `inviteUrl` is the canonical link (built by
/// `InvitationLinkService.buildInvitationLink`); `message` is the
/// pre-composed full text (URL embedded) used for system share +
/// clipboard so what lands in the recipient's inbox is identical
/// regardless of channel.
Future<void> showInviteShareSheet(
  BuildContext context, {
  required Uri inviteUrl,
  required String message,
  required String subject,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final urlText = inviteUrl.toString();
  final box = context.findRenderObject() as RenderBox?;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Скопировать ссылку'),
                subtitle: Text(
                  urlText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Clipboard.setData(ClipboardData(text: urlText));
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Ссылка-приглашение скопирована.'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Поделиться через…'),
                subtitle: const Text(
                  'Открыть системное окно — мессенджеры, почта, AirDrop.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await SharePlus.instance.share(
                      ShareParams(
                        text: message,
                        subject: subject,
                        sharePositionOrigin: box != null
                            ? box.localToGlobal(Offset.zero) & box.size
                            : null,
                      ),
                    );
                  } catch (error) {
                    debugPrint('Failed to open system share sheet: $error');
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Не удалось открыть окно «Поделиться». '
                          'Ссылка скопирована в буфер обмена.',
                        ),
                      ),
                    );
                    await Clipboard.setData(ClipboardData(text: urlText));
                  }
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}
