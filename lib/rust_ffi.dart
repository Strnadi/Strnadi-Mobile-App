/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
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