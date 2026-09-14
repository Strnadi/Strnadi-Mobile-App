import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strnadi/PostRecordingForm/imageUpload.dart';
import 'package:strnadi/localization/localization.dart';

void main() {
  late Directory tempDirectory;
  late File imageFile;

  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await Localization.load('assets/lang/en.json');
    tempDirectory = await Directory.systemTemp.createTemp('image-upload-test-');
    imageFile = File('${tempDirectory.path}/pixel.png');
    await imageFile.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
  });

  tearDownAll(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets(
    'selected thumbnails contain full delete targets at narrow width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      List<File> selected = [];
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: const Key('upload-preview'),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: MultiPhotoUploadWidget(
                  onImagesSelected: (files) => selected = files,
                  pickMultipleImages: () async =>
                      List.generate(5, (_) => XFile(imageFile.path)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          FileImage(imageFile),
          tester.element(find.byType(MultiPhotoUploadWidget)),
        );
      });
      await tester.tap(find.byKey(const Key('photo-upload-gallery')));
      await tester.pumpAndSettle();
      final images = find.byType(Image);
      final buttons = find.widgetWithIcon(IconButton, Icons.close_rounded);
      for (var i = 0; i < 2; i++) {
        final tile = tester.getRect(images.at(i));
        final control = tester.getRect(buttons.at(i));
        expect(tile.size, const Size(120, 120));
        expect(control.size, const Size(48, 48));
        expect(tile.contains(control.topLeft), isTrue);
        expect(tile.contains(control.bottomRight), isTrue);
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('upload-preview')),
        matchesGoldenFile('goldens/upload_thumbnails.png'),
      );
      // The edge of the full touch target must remain interactive.
      await tester.tapAt(
        tester.getRect(buttons.first).bottomLeft + const Offset(6, -6),
      );
      await tester.pumpAndSettle();
      expect(selected, hasLength(4));
      await tester.drag(find.byType(GridView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('single picker result is ignored after the widget is disposed', (
    WidgetTester tester,
  ) async {
    final Completer<XFile?> picker = Completer<XFile?>();
    int callbacks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiPhotoUploadWidget(
          onImagesSelected: (_) => callbacks += 1,
          pickImage: (_) => picker.future,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('photo-upload-camera')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    picker.complete(XFile(imageFile.path));
    await tester.pump();

    expect(callbacks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery picker result is ignored after disposal', (
    WidgetTester tester,
  ) async {
    final Completer<List<XFile>> picker = Completer<List<XFile>>();
    int callbacks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiPhotoUploadWidget(
          onImagesSelected: (_) => callbacks += 1,
          pickMultipleImages: () => picker.future,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('photo-upload-gallery')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    picker.complete(<XFile>[XFile(imageFile.path)]);
    await tester.pump();

    expect(callbacks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid camera taps start only one picker request', (
    WidgetTester tester,
  ) async {
    final Completer<XFile?> picker = Completer<XFile?>();
    int pickerCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiPhotoUploadWidget(
          onImagesSelected: (_) {},
          pickImage: (_) {
            pickerCalls += 1;
            return picker.future;
          },
        ),
      ),
    );

    final Finder button = find.byKey(const Key('photo-upload-camera'));
    await tester.tap(button);
    await tester.tap(button);
    expect(pickerCalls, 1);

    await tester.pump();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

    picker.complete(null);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid gallery taps start only one picker request', (
    WidgetTester tester,
  ) async {
    final Completer<List<XFile>> picker = Completer<List<XFile>>();
    int pickerCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiPhotoUploadWidget(
          onImagesSelected: (_) {},
          pickMultipleImages: () {
            pickerCalls += 1;
            return picker.future;
          },
        ),
      ),
    );

    final Finder button = find.byKey(const Key('photo-upload-gallery'));
    await tester.tap(button);
    await tester.tap(button);
    expect(pickerCalls, 1);

    await tester.pump();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

    picker.complete(const <XFile>[]);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected files are reported as an immutable snapshot', (
    WidgetTester tester,
  ) async {
    ImageSource? observedSource;
    List<File>? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiPhotoUploadWidget(
          onImagesSelected: (List<File> files) => selected = files,
          pickImage: (ImageSource source) async {
            observedSource = source;
            return XFile(imageFile.path);
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('photo-upload-camera')));
    await tester.pump();

    expect(observedSource, ImageSource.camera);
    expect(selected, isNotNull);
    expect(selected, hasLength(1));
    expect(selected!.single.path, imageFile.path);
    expect(
      () => selected!.add(File('${tempDirectory.path}/other.png')),
      throwsUnsupportedError,
    );
    expect(tester.takeException(), isNull);
  });
}
