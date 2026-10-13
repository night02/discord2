import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/call_media_gallery.dart';

ScreenStageStream stream(String id, String label) => ScreenStageStream(
      id: id,
      label: label,
      video: ColoredBox(key: ValueKey('video-$id'), color: Colors.blue),
    );

Widget gallery(List<ScreenStageStream> streams) => MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Canal de voz')),
        body: Column(
          children: [
            Expanded(
              child: CallMediaGallery(
                streams: streams,
                participants: const [
                  VoiceParticipantTile(name: 'Ana', microphoneEnabled: true),
                  VoiceParticipantTile(name: 'Bruno', microphoneEnabled: false),
                ],
              ),
            ),
            SizedBox(
              height: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                      child: TextButton(
                          onPressed: () {},
                          child: const Text('Silenciar',
                              maxLines: 1, overflow: TextOverflow.ellipsis))),
                  Expanded(
                      child: TextButton(
                          onPressed: () {},
                          child: const Text('Desconectar',
                              maxLines: 1, overflow: TextOverflow.ellipsis))),
                ],
              ),
            ),
          ],
        ),
      ),
    );

void expectNoLayoutError(WidgetTester tester) {
  final error = tester.takeException();
  expect(
    error,
    isNull,
    reason: error is FlutterError
        ? error.diagnostics.map((node) => node.toStringDeep()).join('\n')
        : '$error',
  );
}

void main() {
  test(
    'automatic choice follows remote-first order until the viewer selects',
    () {
      final selection = MediaStageSelection();
      expect(selection.activeId(['local']), 'local');
      expect(selection.activeId(['remote', 'local']), 'remote');
      selection.preferredId = 'local';
      expect(selection.activeId(['remote', 'local']), 'local');
      selection.reconcile(['remote']);
      expect(selection.activeId(['remote']), 'remote');
      expect(selection.preferredId, isNull);
    },
  );

  testWidgets('can switch streams without duplicating their video', (
    tester,
  ) async {
    await tester.pumpWidget(
      gallery([stream('ana', 'Ana'), stream('bruno', 'Bruno')]),
    );
    expect(find.byKey(const ValueKey('video-ana')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-bruno')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('stream-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Bruno'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-bruno')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-ana')), findsNothing);
    // A room refresh must not overwrite the viewer's explicit choice.
    await tester.pumpWidget(
      gallery([stream('ana', 'Ana'), stream('bruno', 'Bruno')]),
    );
    expect(find.byKey(const ValueKey('video-bruno')), findsOneWidget);
    expectNoLayoutError(tester);
  });

  testWidgets(
    'enlarging keeps controls; ended streams fall back and reset the gallery',
    (tester) async {
      await tester.pumpWidget(
        gallery([stream('ana', 'Ana'), stream('bruno', 'Bruno')]),
      );
      await tester.tap(find.byKey(const ValueKey('stream-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Bruno'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expand-stage')));
      await tester.pump();
      expect(find.byKey(const ValueKey('call-participants')), findsNothing);
      expect(find.text('Silenciar'), findsOneWidget);
      expect(find.text('Desconectar'), findsOneWidget);
      await tester.tap(find.text('Silenciar'));
      await tester.pumpWidget(gallery([stream('ana', 'Ana')]));
      expect(find.byKey(const ValueKey('video-ana')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-bruno')), findsNothing);
      await tester.pumpWidget(gallery([]));
      expect(find.byKey(const ValueKey('screen-stage')), findsNothing);
      expect(find.byKey(const ValueKey('call-participants')), findsOneWidget);
      await tester.pumpWidget(gallery([stream('ana', 'Ana')]));
      expect(find.byKey(const ValueKey('call-participants')), findsOneWidget);
      expectNoLayoutError(tester);
    },
  );

  testWidgets('names and muted status remain visible with a camera video', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 160,
            height: 96,
            child: VoiceParticipantTile(
              name: 'Nome muito longo do participante',
              microphoneEnabled: false,
              speaking: true,
              video: ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Nome muito longo do participante'), findsOneWidget);
    expect(find.byIcon(Icons.mic_off), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    expectNoLayoutError(tester);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(640, 360),
    const Size(1280, 720),
  ]) {
    testWidgets('gallery and stream menu fit $size with long names', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        gallery([
          stream(
            'ana',
            'Um nome de transmissão muito longo para uma janela pequena',
          ),
          stream(
            'bruno',
            'Uma segunda transmissão com outro nome também muito longo',
          ),
        ]),
      );
      expectNoLayoutError(tester);
      await tester.tap(find.byKey(const ValueKey('stream-selector')));
      await tester.pumpAndSettle();
      expectNoLayoutError(tester);
      await tester.tap(
        find.widgetWithText(
          PopupMenuItem<String>,
          'Uma segunda transmissão com outro nome também muito longo',
        ),
      );
      await tester.pumpAndSettle();
      expectNoLayoutError(tester);
      await tester.tap(find.byKey(const ValueKey('expand-stage')));
      await tester.pump();
      expect(find.text('Desconectar'), findsOneWidget);
      expectNoLayoutError(tester);
    });
  }
}
