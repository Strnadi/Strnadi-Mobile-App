package com.delta.strnadi;

import android.content.Context;
import android.content.Intent;
import android.content.ActivityNotFoundException;
import android.net.Uri;
import android.media.AudioManager;
import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import com.google.android.play.core.appupdate.AppUpdateManager;
import com.google.android.play.core.appupdate.AppUpdateManagerFactory;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.util.HashMap;
import java.util.Map;
import java.io.File;
import java.net.URLConnection;

public class MainActivity extends FlutterActivity {
    private static final String AUDIO_CHANNEL = "com.delta.strnadi/audio";
    private static final String APP_UPDATE_CHANNEL = "com.delta.strnadi/app_update";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(),
            "com.delta.strnadi/markdown_files").setMethodCallHandler((call, result) -> {
                if (!call.method.equals("openFile")) {
                    result.notImplemented();
                    return;
                }
                try {
                    String path = call.argument("path");
                    if (path == null) {
                        result.success(false);
                        return;
                    }
                    File file = new File(path).getCanonicalFile();
                    File root = new File(getCacheDir(), "markdown-attachments").getCanonicalFile();
                    if (!file.isFile() || !file.getPath().startsWith(root.getPath() + File.separator)) {
                        result.success(false);
                        return;
                    }
                    Uri uri = FileProvider.getUriForFile(this,
                        getPackageName() + ".markdown-files", file);
                    String mime = URLConnection.guessContentTypeFromName(file.getName());
                    Intent intent = new Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, mime != null ? mime : "application/octet-stream")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    startActivity(intent);
                    result.success(true);
                } catch (ActivityNotFoundException error) {
                    result.success(false);
                } catch (Exception error) {
                    result.error("ATTACHMENT_OPEN_FAILED", "Could not open attachment", null);
                }
            });
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), AUDIO_CHANNEL)
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

        new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            APP_UPDATE_CHANNEL
        ).setMethodCallHandler(
            (call, result) -> {
                if (!call.method.equals("checkForUpdate")) {
                    result.notImplemented();
                    return;
                }

                AppUpdateManager updateManager =
                    AppUpdateManagerFactory.create(getApplicationContext());
                updateManager.getAppUpdateInfo()
                    .addOnSuccessListener(updateInfo -> {
                        Map<String, Object> response = new HashMap<>();
                        response.put("availability", updateInfo.updateAvailability());
                        response.put(
                            "availableVersionCode",
                            updateInfo.availableVersionCode()
                        );
                        result.success(response);
                    })
                    .addOnFailureListener(error ->
                        result.error(
                            "PLAY_UPDATE_CHECK_FAILED",
                            "Google Play could not determine update availability.",
                            error.getMessage()
                        )
                    );
            }
        );
    }
}
