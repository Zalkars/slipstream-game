package com.slipstream.ads;

import android.app.Activity;
import android.os.Build;
import android.view.DisplayCutout;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import com.yandex.mobile.ads.banner.*;
import com.yandex.mobile.ads.common.*;
import com.yandex.mobile.ads.rewarded.*;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Yandex Mobile Ads bridge for SLIPSTREAM: a rewarded ad (revive) and top
 * banner slots (menu, garage, finish). Ported from Last Hook's LastHookAds.
 * All SDK work runs on Android's UI thread; Godot receives queued signals.
 */
public final class SlipstreamAds extends GodotPlugin {
    private boolean ready, initializing, destroyed, fullscreen;
    private RewardedAdLoader rewardedLoader;
    private RewardedAd rewarded;

    public SlipstreamAds(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "SlipstreamAds"; }

    @Override public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        for (String name : new String[]{"initialized", "rewarded_loaded", "reward_earned", "rewarded_closed"}) {
            signals.add(new SignalInfo(name));
        }
        signals.add(new SignalInfo("ad_failed", String.class, String.class));
        signals.add(new SignalInfo("banner_slot_height_changed", String.class, Integer.class));
        return signals;
    }

    private void ui(Runnable action) {
        Activity activity = getActivity();
        if (activity != null && !destroyed) activity.runOnUiThread(() -> {
            if (!destroyed && !activity.isFinishing()) action.run();
        });
    }
    private void failed(String kind, String message) { emitSignal("ad_failed", kind, message); }

    @UsedByGodot public void initialize() {
        ui(() -> {
            if (ready) { emitSignal("initialized"); return; }
            if (initializing) return;
            initializing = true;
            try {
                YandexAds.initialize(getActivity(), () -> ui(() -> {
                    try {
                        ready = true;
                        rewardedLoader = new RewardedAdLoader(getActivity());
                        emitSignal("initialized");
                    } catch (Throwable error) {
                        ready = false;
                        initializing = false;
                        failed("initialize", error.toString());
                    }
                }));
            } catch (Throwable error) {
                initializing = false;
                failed("initialize", error.toString());
            }
        });
    }

    @UsedByGodot public void loadRewarded(String id) {
        ui(() -> {
            if (!ready || fullscreen) return;
            rewardedLoader.loadAd(new AdRequest.Builder(id).build(), new RewardedAdLoadListener() {
                @Override public void onAdLoaded(RewardedAd ad) {
                    if (destroyed) return;
                    rewarded = ad;
                    emitSignal("rewarded_loaded");
                }
                @Override public void onAdFailedToLoad(AdRequestError error) {
                    if (!destroyed) failed("rewarded_load", error.getDescription());
                }
            });
        });
    }

    @UsedByGodot public void showRewarded() {
        ui(() -> {
            if (rewarded == null || fullscreen) { failed("rewarded_show", "Ad is not ready"); return; }
            fullscreen = true;
            final RewardedAd ad = rewarded;
            rewarded = null; // A loaded ad can only be shown once.
            ad.setAdEventListener(new RewardedAdEventListener() {
                private boolean earned, finished;
                @Override public void onAdShown() {}
                @Override public void onAdClicked() {}
                @Override public void onAdImpression(ImpressionData data) {}
                @Override public void onRewarded(Reward reward) {
                    if (!finished && !earned && !destroyed) {
                        earned = true;
                        emitSignal("reward_earned");
                    }
                }
                @Override public void onAdDismissed() {
                    if (finished) return;
                    finished = true;
                    ad.setAdEventListener(null);
                    fullscreen = false;
                    if (!destroyed) emitSignal("rewarded_closed");
                }
                @Override public void onAdFailedToShow(AdError error) {
                    if (finished) return;
                    finished = true;
                    ad.setAdEventListener(null);
                    fullscreen = false;
                    if (!destroyed) failed("rewarded_show", error.getDescription());
                }
            });
            ad.show(getActivity());
        });
    }

    /** One banner placement at the top of the screen. */
    private static final class BannerSlot {
        String unitId;
        // The banner on screen and, during a refresh, the next one loading
        // hidden behind it; the old one stays up until the new one is ready.
        BannerAdView banner;
        BannerAdView pending;
        // Full width at the very top of the screen; the bar inside fills the
        // sides when the creative is narrower than the screen.
        FrameLayout container;
        FrameLayout bar;
        // Height the screen gives the slot in pixels; 0 while nothing is
        // loaded.
        int loadedHeight;
        // Fixed strip height in pixels: every creative fits inside it, so a
        // refresh never moves the game's layout.
        int zone;
        int widthPixels;
        BannerAdSize size;
        boolean wanted;
        long shownAt;
        int refreshFailures;
    }

    // A thin strip: the adaptive sticky size took up to 15% of the screen
    // (about 100dp on phones). 56dp still fits the standard 320x50 creative.
    private static final int BANNER_MAX_HEIGHT_DP = 56;
    // Inline banners are not refreshed by the SDK; the plugin swaps in a new
    // one while the slot is on screen.
    private static final long BANNER_REFRESH_MS = 45_000L;
    private static final long BANNER_TICK_MS = 5_000L;
    private static final int BANNER_REFRESH_MAX_FAILURES = 3;
    private boolean paused;
    private final Runnable bannerTick = this::refreshDueBanners;
    private final Map<String, BannerSlot> slots = new HashMap<>();

    private BannerSlot slot(String name) {
        BannerSlot result = slots.get(name);
        if (result == null) {
            result = new BannerSlot();
            slots.put(name, result);
        }
        return result;
    }

    @UsedByGodot public void setBannerSlotVisible(String name, boolean visible) {
        ui(() -> {
            BannerSlot slot = slot(name);
            if (visible && !slot.wanted) slot.refreshFailures = 0;
            slot.wanted = visible;
            if (slot.container != null) {
                // INVISIBLE, never GONE: a GONE view is not measured, so a
                // banner that loaded while hidden reported no height.
                slot.container.setVisibility(visible && slot.loadedHeight > 0 ? View.VISIBLE : View.INVISIBLE);
                if (visible) slot.container.bringToFront();
            }
            // The screen lays itself out below the banner each time it shows.
            if (visible && slot.loadedHeight > 0) emitSignal("banner_slot_height_changed", name, slot.loadedHeight);
        });
    }

    @UsedByGodot public void loadBannerSlot(String name, String id) {
        ui(() -> {
            if (!ready) return;
            destroyBanner(name);
            final BannerSlot slot = slot(name);
            Activity activity = getActivity();
            ViewGroup parent = (ViewGroup) activity.getWindow().getDecorView();
            int widthPixels = parent.getWidth();
            if (widthPixels <= 0) widthPixels = activity.getResources().getDisplayMetrics().widthPixels;
            float density = activity.getResources().getDisplayMetrics().density;
            if (density <= 0f) density = 1f;
            DisplayCutout cutout = displayCutout(parent);
            int leftInset = cutout != null ? cutout.getSafeInsetLeft() : 0;
            int rightInset = cutout != null ? cutout.getSafeInsetRight() : 0;
            int widthDp = Math.max(1, (int) Math.floor((widthPixels - leftInset - rightInset) / density));
            // Adaptive inline with a height cap: the server picks the best
            // creative for the full width that fits the thin strip.
            slot.unitId = id;
            slot.size = BannerAdSize.inline(activity, widthDp, BANNER_MAX_HEIGHT_DP);
            slot.widthPixels = Math.round(widthDp * density);
            slot.zone = Math.round(BANNER_MAX_HEIGHT_DP * density);
            slot.loadedHeight = 0;
            slot.refreshFailures = 0;
            slot.container = new FrameLayout(activity);
            // Flush with the top edge, over the camera's band, by choice of
            // the game: no strip above the ad.
            slot.container.setPadding(leftInset, 0, rightInset, 0);
            slot.bar = new FrameLayout(activity);
            slot.bar.setBackgroundColor(BAR_COLOR);
            slot.container.addView(slot.bar, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, slot.zone);
            params.gravity = Gravity.TOP;
            parent.addView(slot.container, params);
            // Godot renders into a SurfaceView: keep the banner in the decor
            // overlay and raise it so it never ends up behind the game.
            slot.container.setElevation(1000f);
            slot.container.setTranslationZ(1000f);
            // Hidden while loading, but laid out (INVISIBLE, not GONE), so the
            // loaded banner can be measured. The screen moves only once it is.
            slot.container.setVisibility(View.INVISIBLE);
            requestBanner(name, slot);
        });
    }

    /** Loads the next creative into a hidden view inside the strip. */
    private void requestBanner(final String name, final BannerSlot slot) {
        Activity activity = getActivity();
        if (activity == null || slot.bar == null || slot.pending != null) return;
        final BannerAdView banner = new BannerAdView(activity);
        banner.setAdSize(slot.size);
        // A creative narrower or shorter than the strip is centred; the bar's
        // colour fills the rest. The strip clips anything taller.
        slot.bar.addView(banner, new FrameLayout.LayoutParams(
                slot.widthPixels, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER));
        banner.setVisibility(View.INVISIBLE);
        slot.pending = banner;
        banner.setBannerAdEventListener(new BannerAdEventListener() {
            @Override public void onAdLoaded() { measureBanner(name, banner, 0); }
            @Override public void onAdClicked() {}
            @Override public void onImpression(ImpressionData data) {}
            @Override public void onAdFailedToLoad(AdRequestError error) {
                if (destroyed || slot.pending != banner) return;
                dropPending(slot);
                if (slot.banner != null) {
                    // A failed refresh keeps the current creative up.
                    slot.shownAt = System.currentTimeMillis();
                    slot.refreshFailures++;
                    return;
                }
                slot.loadedHeight = 0;
                if (slot.container != null) slot.container.setVisibility(View.INVISIBLE);
                failed("banner" + name + "_load", error.getDescription());
            }
        });
        banner.loadAd(new AdRequest.Builder(slot.unitId).build());
    }

    private static void dropPending(BannerSlot slot) {
        BannerAdView banner = slot.pending;
        if (banner == null) return;
        slot.pending = null;
        banner.setBannerAdEventListener(null);
        ViewGroup parent = (ViewGroup) banner.getParent();
        if (parent != null) parent.removeView(banner);
        banner.destroy();
    }

    /** onAdLoaded can arrive before Android has measured the inline slot. */
    private void measureBanner(final String name, final BannerAdView banner, final int attempt) {
        ui(() -> {
            BannerSlot slot = slot(name);
            if (destroyed || slot.pending != banner || slot.container == null) return;
            if (!banner.isLaidOut() || banner.isLayoutRequested()
                    || banner.getWidth() <= 0 || banner.getHeight() <= 0) {
                if (attempt < 20) {
                    slot.container.postDelayed(() -> measureBanner(name, banner, attempt + 1), 50L);
                } else if (slot.banner != null) {
                    dropPending(slot);
                    slot.shownAt = System.currentTimeMillis();
                    slot.refreshFailures++;
                } else {
                    destroyBanner(name);
                    failed("banner" + name + "_load", "Banner view was not laid out");
                }
                return;
            }
            // Swap: the new creative appears in place of the old one.
            BannerAdView old = slot.banner;
            slot.banner = banner;
            slot.pending = null;
            banner.setVisibility(View.VISIBLE);
            if (old != null) {
                old.setBannerAdEventListener(null);
                slot.bar.removeView(old);
                old.destroy();
            }
            slot.shownAt = System.currentTimeMillis();
            slot.refreshFailures = 0;
            boolean first = slot.loadedHeight == 0;
            slot.loadedHeight = slot.zone;
            slot.container.setVisibility(slot.wanted ? View.VISIBLE : View.INVISIBLE);
            if (slot.wanted) slot.container.bringToFront();
            if (first) emitSignal("banner_slot_height_changed", name, slot.zone);
            scheduleBannerTick();
        });
    }

    private void scheduleBannerTick() {
        Activity activity = getActivity();
        if (activity == null || destroyed) return;
        View root = activity.getWindow().getDecorView();
        root.removeCallbacks(bannerTick);
        root.postDelayed(bannerTick, BANNER_TICK_MS);
    }

    /** Refreshes each banner that has been on screen for the full interval. */
    private void refreshDueBanners() {
        if (destroyed) return;
        long now = System.currentTimeMillis();
        boolean any = false;
        for (Map.Entry<String, BannerSlot> entry : slots.entrySet()) {
            BannerSlot slot = entry.getValue();
            if (slot.banner == null || slot.container == null) continue;
            any = true;
            // Stops after repeated failures (no network, no fill) instead of
            // hammering the server; the next full load starts over.
            if (paused || fullscreen || !slot.wanted || slot.pending != null
                    || slot.refreshFailures >= BANNER_REFRESH_MAX_FAILURES) continue;
            if (now - slot.shownAt >= BANNER_REFRESH_MS) requestBanner(entry.getKey(), slot);
        }
        if (any) scheduleBannerTick();
    }

    @Override public void onMainPause() {
        paused = true;
        super.onMainPause();
    }

    @Override public void onMainResume() {
        paused = false;
        super.onMainResume();
    }

    // SLIPSTREAM's menu background (#121417).
    private static final int BAR_COLOR = 0xFF121417;

    private static DisplayCutout displayCutout(View root) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null;
        WindowInsets insets = root.getRootWindowInsets();
        return insets != null ? insets.getDisplayCutout() : null;
    }

    private void destroyBanner(String name) {
        BannerSlot slot = slots.get(name);
        if (slot == null) return;
        slot.loadedHeight = 0;
        dropPending(slot);
        if (slot.banner != null) {
            slot.banner.setBannerAdEventListener(null);
            slot.banner.destroy();
            slot.banner = null;
        }
        if (slot.container != null) {
            ViewGroup parent = (ViewGroup) slot.container.getParent();
            if (parent != null) parent.removeView(slot.container);
            slot.container = null;
            slot.bar = null;
        }
    }

    @Override public void onMainDestroy() {
        destroyed = true;
        for (String name : slots.keySet().toArray(new String[0])) destroyBanner(name);
        if (rewardedLoader != null) rewardedLoader.cancelLoading();
        if (rewarded != null) rewarded.setAdEventListener(null);
        rewarded = null;
        super.onMainDestroy();
    }
}
