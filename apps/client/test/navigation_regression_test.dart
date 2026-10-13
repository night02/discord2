import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/api_client.dart';
import 'package:veylor/application/models.dart';
import 'package:veylor/application/veylor_controller.dart';
import 'package:veylor/main.dart';

import 'support/workspace_fixture.dart';

void main() {
  test('opening the default text channel clears its unread marker', () async {
    final f = WorkspaceFixture();
    addTearDown(f.dispose);
    await f.login();
    f.realtime.emit({'type': 'channel.message', 'channel_id': 'channel-a'});
    expect(f.app.hasUnread(const Conversation.channel('channel-a')), isTrue);
    await f.app.selectCommunity(f.app.communities.first);
    expect(f.app.conversation, const Conversation.channel('channel-a'));
    expect(f.app.hasUnread(const Conversation.channel('channel-a')), isFalse);
  });

  test(
    'a late send failure preserves the source draft and retry nonce',
    () async {
      final f = WorkspaceFixture();
      addTearDown(f.dispose);
      await f.openCommunity();
      final response = Completer<Json>(), source = f.app.conversation!;
      f.app.saveDraft(source, 'Texto para reenviar');
      f.api.handler = (method, route, body) async {
        if (method == 'POST' && route == source.route) return response.future;
        return f.api.response(method, route, body);
      };
      final sending = f.app.send('Texto para reenviar');
      await f.app.selectThread(f.app.threads.first);
      response.completeError(
        const ApiException(503, 'Falha no canal anterior'),
      );
      expect(await sending, isFalse);
      expect(f.app.error, isNull);
      expect(f.app.draft(source), 'Texto para reenviar');
      expect(f.app.sending, isFalse);
      f.api.handler = null;
      await f.app.selectCommunity(f.app.communities.first);
      expect(await f.app.send('Texto para reenviar'), isTrue);
      final sends = f.api.calls
          .where((call) => call.method == 'POST' && call.route == source.route)
          .toList();
      expect(sends.length, 2);
      expect(
        sends.first.body!['client_nonce'],
        sends.last.body!['client_nonce'],
      );
      expect(f.app.draft(source), '');
    },
  );

  test('a failure in the visible conversation still shows its error', () async {
    final f = WorkspaceFixture();
    addTearDown(f.dispose);
    await f.openCommunity();
    f.api.handler = (method, route, body) async {
      if (method == 'POST')
        throw const ApiException(503, 'Envio temporariamente indisponível');
      return f.api.response(method, route, body);
    };
    expect(await f.app.send('olá'), isFalse);
    expect(f.app.error, 'Envio temporariamente indisponível');
    expect(f.app.phase, AppPhase.signedIn);
  });

  test(
    'a late expired-session response still signs out after navigation',
    () async {
      final f = WorkspaceFixture();
      addTearDown(f.dispose);
      await f.openCommunity();
      final response = Completer<Json>(), source = f.app.conversation!;
      f.app.saveDraft(source, 'Rascunho privado');
      f.api.handler = (method, route, body) async {
        if (method == 'POST' && route == source.route) return response.future;
        return f.api.response(method, route, body);
      };
      final sending = f.app.send('Rascunho privado');
      await f.app.selectThread(f.app.threads.first);
      response.completeError(const ApiException(401, 'Expired'));
      expect(await sending, isFalse);
      expect(f.app.phase, AppPhase.signedOut);
      expect(f.app.account, isNull);
      expect(f.sessions.token, isNull);
      expect(f.app.draft(source), '');
      expect(f.realtime.active, isFalse);
      expect(f.app.error, 'Sua sessão expirou. Entre novamente.');
    },
  );

  testWidgets('a late confirmed send cannot clear the draft of another DM', (
    tester,
  ) async {
    final f = WorkspaceFixture();
    addTearDown(f.dispose);
    f.api.threads.add({'id': 'thread-b', 'username': 'Alice'});
    await f.login();
    await f.app.selectThread(f.app.threads.first);
    await tester.pumpWidget(
      VeylorApp(controller: f.app, sessionRestorationEnabled: false),
    );
    await tester.pumpAndSettle();
    final composer = find.byKey(const ValueKey('message-composer'));
    await tester.enterText(composer, 'Mesmo texto');
    final response = Completer<Json>();
    f.api.handler = (method, route, body) async {
      if (method == 'POST' && route == '/api/dms/thread-a/messages')
        return response.future;
      return f.api.response(method, route, body);
    };
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dm-thread-b')));
    await tester.pumpAndSettle();
    await tester.enterText(composer, 'Mesmo texto');
    response.complete({
      'message': FixtureApi.message(901, 'Mesmo texto', username: 'Vinicius'),
    });
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(composer).controller!.text, 'Mesmo texto');
    expect(f.app.conversation, const Conversation.direct('thread-b'));
    expect(f.app.messages, isEmpty);
    await tester.tap(find.byKey(const ValueKey('dm-thread-a')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(composer).controller!.text, '');
    expect(find.text('Mesmo texto'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'mobile navigation fits larger text, safe insets and the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final f = WorkspaceFixture();
      addTearDown(f.dispose);
      await f.openCommunity();
      await tester.pumpWidget(
        VeylorApp(controller: f.app, sessionRestorationEnabled: false),
      );
      await tester.pumpAndSettle();
      final composer = find.byKey(const ValueKey('message-composer'));
      await tester.enterText(composer, 'Rascunho no celular');
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('open-navigation')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('channel-channel-b')));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
        isFalse,
      );
      expect(f.app.conversation, const Conversation.channel('channel-b'));
      expect(tester.widget<TextField>(composer).controller!.text, '');
      expect(
        f.app.draft(const Conversation.channel('channel-a')),
        'Rascunho no celular',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
