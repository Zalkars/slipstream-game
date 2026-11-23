package com.slipstream.ads;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import androidx.core.content.FileProvider;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.Set;
import java.util.regex.Pattern;

/** Opens Android's sharesheet with a local race replay and its invitation text. */
public final class SlipstreamChallenges extends GodotPlugin {
    private static final Pattern REPLAY_FILE =
            Pattern.compile("Slipstream-[0-9ABCDEFGHJKMNPQRSTVWXYZ]{8}\\.slipstream");
    private static final int MAX_REPLAY_BYTES = 16512;

    public SlipstreamChallenges(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "SlipstreamChallenges"; }

    @Override public Set<SignalInfo> getPluginSignals() {
        return Collections.singleton(new SignalInfo("replay_share_failed"));
    }

    @UsedByGodot public boolean shareReplay(String filename, String contents, String invitation) {
        Activity activity = getActivity();
        byte[] bytes = contents.getBytes(StandardCharsets.UTF_8);
        if (activity == null || !REPLAY_FILE.matcher(filename).matches() || bytes.length > MAX_REPLAY_BYTES) {
            return false;
        }
        activity.runOnUiThread(() -> {
            try {
                if (activity.isFinishing()) return;
                File directory = new File(activity.getFilesDir(), "challenge_shares");
                if (!directory.isDirectory() && !directory.mkdirs()) {
                    throw new IOException("Could not create the challenge directory");
                }
                File replay = new File(directory, filename);
                try (FileOutputStream stream = new FileOutputStream(replay)) {
                    stream.write(bytes);
                }
                Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", replay);
                Intent share = new Intent(Intent.ACTION_SEND);
                share.setType("application/octet-stream");
                share.putExtra(Intent.EXTRA_TEXT, invitation);
                share.putExtra(Intent.EXTRA_STREAM, uri);
                share.setClipData(ClipData.newRawUri(filename, uri));
                share.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                activity.startActivity(Intent.createChooser(share, "Поделиться вызовом"));
            } catch (IOException | RuntimeException error) {
                emitSignal("replay_share_failed");
            }
        });
        return true;
    }
}
