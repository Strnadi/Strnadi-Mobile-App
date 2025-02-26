import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Define the function signatures from your Rust code
typedef InitOpenGLFunc = Void Function();
typedef ProcessAudioFunc = Void Function(Pointer<Uint8> data, Int32 len);

// Define the Dart function types
typedef InitOpenGLDart = void Function();
typedef ProcessAudioDart = void Function(Pointer<Uint8> data, int len);

class SpectrogramFFI {
  late DynamicLibrary _lib;
  late InitOpenGLDart _initOpenGL;
  late ProcessAudioDart _processAudio;

  SpectrogramFFI() {
    // Load the appropriate library based on platform
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libspectrogram.so');
    } else if (Platform.isIOS) {
      throw UnsupportedError("unsuported platform");
    } else {
      throw UnsupportedError('Unsupported platform');
    }

    // Look up the C functions
    _initOpenGL = _lib
        .lookupFunction<InitOpenGLFunc, InitOpenGLDart>('init_opengl');
    _processAudio = _lib
        .lookupFunction<ProcessAudioFunc, ProcessAudioDart>('process_audio');
  }

  void initOpenGL() {
    _initOpenGL();
  }

  void processAudio(List<int> audioData) {
    final length = audioData.length;
    final ptr = calloc<Uint8>(length);

    // Copy data to the pointer
    for (var i = 0; i < length; i++) {
      ptr[i] = audioData[i];
    }

    // Call the Rust function
    _processAudio(ptr, length);

    // Free the allocated memory
    calloc.free(ptr);
  }
}