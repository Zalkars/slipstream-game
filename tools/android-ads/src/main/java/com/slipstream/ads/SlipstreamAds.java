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
        BannerAdView banner;
        FrameLayout container;
        BannerAdSize size;
        // Height the screen gives the slot in pixels (the cut-out band over
        // it plus the banner); 0 while nothing is loaded.
        int loadedHeight;
        // The camera cut-out's band at the top of the screen, in pixels.
        int inset;
        // Most the top zone may take in pixels: the band plus the bar.
        int zone;
        boolean wanted;
    }
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
            // The top zone is the cut-out's band plus a 50dp bar (90dp on a
            // tablet); the game lays itself out below it.
            slot.inset = cutout != null ? cutout.getSafeInsetTop() : 0;
            int barDp = widthDp > 728 ? 90 : 50;
            slot.zone = slot.inset + Math.round(barDp * density);
            BannerAdSize size = BannerAdSize.inline(activity, widthDp, barDp);
            slot.size = size;
            slot.loadedHeight = 0;
            slot.banner = new BannerAdView(activity);
            slot.banner.setAdSize(size);
            slot.container = new FrameLayout(activity);
            slot.container.setBackgroundColor(BAR_COLOR);
            slot.container.setPadding(leftInset, slot.inset, rightInset, 0);
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, slot.zone);
            params.gravity = Gravity.TOP;
            parent.addView(slot.container, params);
            // Godot renders into a SurfaceView: keep the banner in the decor
            // overlay and raise it so it never ends up behind the game.
            slot.container.setElevation(1000f);
            slot.container.setTranslationZ(1000f);
            slot.container.setClipChildren(false);
            FrameLayout.LayoutParams childParams = new FrameLayout.LayoutParams(
                    size.getWidthInPixels(activity), ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.TOP | Gravity.CENTER_HORIZONTAL);
            slot.container.addView(slot.banner, childParams);
            // Hidden while loading, but laid out (INVISIBLE, not GONE), so the
            // loaded banner can be measured. The screen moves only once it is.
            slot.container.setVisibility(View.INVISIBLE);
            final BannerAdView banner = slot.banner;
            banner.setBannerAdEventListener(new BannerAdEventListener() {
                @Override public void onAdLoaded() { measureBanner(name, banner, 0); }
                @Override public void onAdClicked() {}
                @Override public void onImpression(ImpressionData data) {}
                @Override public void onAdFailedToLoad(AdRequestError error) {
                    if (destroyed || slot.banner != banner) return;
                    slot.loadedHeight = 0;
                    if (slot.container != null) slot.container.setVisibility(View.INVISIBLE);
                    failed("banner" + name + "_load", error.getDescription());
                }
            });
            banner.loadAd(new AdRequest.Builder(id).build());
        });
    }

    /** onAdLoaded can arrive before Android has measured the inline slot. */
    private void measureBanner(final String name, final BannerAdView banner, final int attempt) {
        ui(() -> {
            BannerSlot slot = slot(name);
            if (destroyed || slot.banner != banner || slot.container == null) return;
            int measured = banner.getHeight();
            if (measured <= 0 && attempt < 8) {
                slot.container.postDelayed(() -> measureBanner(name, banner, attempt + 1), 50L);
                return;
            }
            if (measured <= 0 && slot.size != null) measured = slot.size.getHeightInPixels(getActivity());
            if (measured <= 0) return;
            int total = Math.min(slot.inset + measured, slot.zone);
            slot.loadedHeight = total;
            ViewGroup.LayoutParams lp = slot.container.getLayoutParams();
            if (lp != null && lp.height != total) {
                lp.height = total;
                slot.container.setLayoutParams(lp);
            }
            slot.container.setVisibility(slot.wanted ? View.VISIBLE : View.INVISIBLE);
            if (slot.wanted) slot.container.bringToFront();
            emitSignal("banner_slot_height_changed", name, total);
        });
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
        if (slot.banner != null) {
            slot.banner.setBannerAdEventListener(null);
            slot.banner.destroy();
            slot.banner = null;
        }
        if (slot.container != null) {
            ViewGroup parent = (ViewGroup) slot.container.getParent();
            if (parent != null) parent.removeView(slot.container);
            slot.container = null;
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
