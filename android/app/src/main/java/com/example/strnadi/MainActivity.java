package com.delta.strnadi;

import android.content.Context;
import android.media.AudioManager;
import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.util.HashMap;
import java.util.Map;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.delta.strnadi/audio";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler(
                (call, result) -> {
                    if (call.method.equals("getBestAudioSettings")) {
                        try {
                            AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
                            String sampleRateStr = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE);
                            int sampleRate = sampleRateStr != null ? Integer.parseInt(sampleRateStr) : 44100;
                            Map<String, Object> settings = new HashMap<>();
                            settings.put("sampleRate", sampleRate);
                            settings.put("bitRate", 128000);
                            result.success(settings);
                        } catch (Exception e) {
                            result.error("UNAVAILABLE", "Cannot load microphone settings", e.getMessage());
                        }
                    } else {
                        result.notImplemented();
                    }
                }
            );
    }
}
