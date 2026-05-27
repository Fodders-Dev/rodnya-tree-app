// Ship FE8 (2026-05-27): MembershipActionMenu widget tests.
//
// Covers:
//   • Menu items conditional на target role (viewer/editor/owner)
//   • Invite-grant toggle visible только для editor target
//   • Confirmation dialogs gate destructive ops (promote-to-owner,
//     demote-from-owner, kick)
//   • Non-destructive ops (viewer↔editor toggle, invite-grant) skip
//     dialog
//   • Pending state shows progress, hides PopupMenuButton

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/widgets/membership_action_menu.dart';

SemyaMembership _membership({
  String userId = 'u-target',
  SemyaRole role = SemyaRole.viewer,
  bool hasInviteGrant = false,
}) {
  return SemyaMembership(
    id: 'mem-1',
    semyaId: 's-1',
    userId: userId,
    role: role,
    joinedAt: '2026-05-26T00:00:00.000Z',
    hasInviteGrant: hasInviteGrant,
  );
}

class _Recorder {
  SemyaRole? lastRoleChange;
  bool? lastGrantToggle;
  int kickCalls = 0;

  MembershipActions get actions => MembershipActions(
        onChangeRole: (role) async {
          lastRoleChange = role;
        },
        onToggleInviteGrant: (enabled) async {
          lastGrantToggle = enabled;
        },
        onKick: () async {
          kickCalls += 1;
        },
      );
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

Future<void> _openMenu(WidgetTester tester, String userId) async {
  await tester.tap(find.byKey(Key('membership-menu-$userId')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('viewer target — promote/editor/kick visible, no grant toggle',
      (tester) async {
    final rec = _Recorder();
    await tester.pumpWidget(_wrap(MembershipActionMenu(
      membership: _membership(role: SemyaRole.viewer),
      actions: rec.actions,
    )));
    await _openMenu(tester, 'u-target');
    expect(find.text('Сделать владельцем'), findsOneWidget);
    expect(find.text('Сделать редактором'), findsOneWidget);
    expect(find.text('Сделать наблюдателем'), findsNothing); // already viewer
    expect(find.text('Разрешить приглашать'), findsNothing);
    expect(find.text('Удалить из семьи'), findsOneWidget);
  });

  testWidgets('editor target — grant toggle visible', (tester) async {
    final rec = _Recorder();
    await tester.pumpWidget(_wrap(MembershipActionMenu(
      membership: _membership(role: SemyaRole.editor, hasInviteGrant: false),
      actions: rec.actions,
    )));
    await _openMenu(tester, 'u-target');
    expect(find.text('Сделать редактором'), findsNothing); // already editor
    expect(find.text('Сделать владельцем'), findsOneWidget);
    expect(find.text('Сделать наблюдателем'), findsOneWidget);
    expect(find.text('Разрешить приглашать'), findsOneWidget);
    expect(find.text('Удалить из семьи'), findsOneWidget);
  });

  testWidgets(
    'editor target с grant=true → «Запретить приглашать»',
    (tester) async {
      final rec = _Recorder();
      await tester.pumpWidget(_wrap(MembershipActionMenu(
        membership: _membership(role: SemyaRole.editor, hasInviteGrant: true),
        actions: rec.actions,
      )));
      await _openMenu(tester, 'u-target');
      expect(find.text('Запретить приглашать'), findsOneWidget);
      expect(find.text('Разрешить приглашать'), findsNothing);
    },
  );

  testWidgets(
    'owner target — both demote options shown, no grant toggle',
    (tester) async {
      final rec = _Recorder();
      await tester.pumpWidget(_wrap(MembershipActionMenu(
        membership: _membership(role: SemyaRole.owner),
        actions: rec.actions,
      )));
      await _openMenu(tester, 'u-target');
      expect(find.text('Сделать владельцем'), findsNothing); // already owner
      expect(find.text('Сделать редактором'), findsOneWidget);
      expect(find.text('Сделать наблюдателем'), findsOneWidget);
      expect(find.text('Разрешить приглашать'), findsNothing);
      expect(find.text('Удалить из семьи'), findsOneWidget);
    },
  );

  testWidgets('promote-to-owner shows confirmation dialog', (tester) async {
    final rec = _Recorder();
    await tester.pumpWidget(_wrap(MembershipActionMenu(
      membership: _membership(role: SemyaRole.viewer),
      actions: rec.actions,
    )));
    await _openMenu(tester, 'u-target');
    await tester.tap(find.text('Сделать владельцем'));
    await tester.pumpAndSettle();
    expect(find.text('Сделать владельцем семьи?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('membership-confirm-ok')));
    await tester.pumpAndSettle();
    expect(rec.lastRoleChange, SemyaRole.owner);
  });

  testWidgets('promote-to-owner — cancel preserves state', (tester) async {
    final rec = _Recorder();
    await tester.pumpWidget(_wrap(MembershipActionMenu(
      membership: _membership(role: SemyaRole.viewer),
      actions: rec.actions,
    )));
    await _openMenu(tester, 'u-target');
    await tester.tap(find.text('Сделать владельцем'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('membership-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(rec.lastRoleChange, isNull);
  });

  testWidgets(
    'demote owner → editor shows confirmation',
    (tester) async {
      final rec = _Recorder();
      await tester.pumpWidget(_wrap(MembershipActionMenu(
        membership: _membership(role: SemyaRole.owner),
        actions: rec.actions,
      )));
      await _openMenu(tester, 'u-target');
      await tester.tap(find.text('Сделать редактором'));
      await tester.pumpAndSettle();
      expect(find.text('Снять права владельца?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('membership-confirm-ok')));
      await tester.pumpAndSettle();
      expect(rec.lastRoleChange, SemyaRole.editor);
    },
  );

  testWidgets(
    'demote viewer ↔ editor — no confirmation, immediate action',
    (tester) async {
      final rec = _Recorder();
      await tester.pumpWidget(_wrap(MembershipActionMenu(
        membership: _membership(role: SemyaRole.editor),
        actions: rec.actions,
      )));
      await _openMenu(tester, 'u-target');
      await tester.tap(find.text('Сделать наблюдателем'));
      await tester.pumpAndSettle();
      // Editor → viewer not destructive, no dialog.
      expect(find.text('Снять права владельца?'), findsNothing);
      expect(rec.lastRoleChange, SemyaRole.viewer);
    },
  );

  testWidgets('grant invite toggle fires immediate', (tester) async {
    final rec = _Recorder();
    await tester.pumpWidget(_wrap(MembershipActionMenu(
      membership: _membership(role: SemyaRole.editor, hasInviteGrant: false),
      actions: rec.actions,
    )));
    await _openMenu(tester, 'u-target');
    await tester.tap(find.text('Разрешить приглашать'));
    await tester.pumpAndSettle();
    expect(rec.lastGrantToggle, isTrue);
  });

  testWidgets('kick fires destructive confirmation', (tester) async {
    final rec = _Recorder();
    await tester.pumpWidget(_wrap(MembershipActionMenu(
      membership: _membership(role: SemyaRole.editor),
      actions: rec.actions,
    )));
    await _openMenu(tester, 'u-target');
    await tester.tap(find.text('Удалить из семьи'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Удалить'), findsWidgets);
    await tester.tap(find.byKey(const Key('membership-destructive-ok')));
    await tester.pumpAndSettle();
    expect(rec.kickCalls, 1);
  });

  testWidgets('kick cancel preserves state', (tester) async {
    final rec = _Recorder();
    await tester.pumpWidget(_wrap(MembershipActionMenu(
      membership: _membership(role: SemyaRole.editor),
      actions: rec.actions,
    )));
    await _openMenu(tester, 'u-target');
    await tester.tap(find.text('Удалить из семьи'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('membership-destructive-cancel')));
    await tester.pumpAndSettle();
    expect(rec.kickCalls, 0);
  });

  testWidgets('isPending=true → spinner, menu button hidden', (tester) async {
    final rec = _Recorder();
    await tester.pumpWidget(_wrap(MembershipActionMenu(
      membership: _membership(role: SemyaRole.editor),
      isPending: true,
      actions: rec.actions,
    )));
    expect(
      find.byKey(const Key('membership-menu-u-target')),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
