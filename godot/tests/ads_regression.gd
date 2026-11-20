extends Node

# Yandex Ads regression (ported from Last Hook's test_ads.gd): AdsService
# lifecycle against a fake native plugin, the top banner on menu / garage /
# finish screen only, and the rewarded revive after a fatal crash.
# Never writes the player's save (main_without_persistence) and leaves the
# AdsService autoload detached when done.

var failures := 0


class FakeAds extends RefCounted:
	signal initialized
	signal rewarded_loaded
	signal reward_earned
	signal rewarded_closed
	signal ad_failed(kind: String, message: String)
	signal banner_slot_height_changed(slot: String, height: int)
	var rewards_shown := 0
	var reward_loads := 0
	var reward_id := ""
	var banners_loaded := 0
	var banner_id := ""
	var banner_visible := false
	func initialize() -> void: initialized.emit()
	func loadRewarded(id: String) -> void:
		reward_loads += 1
		reward_id = id
	func showRewarded() -> void: rewards_shown += 1
	func loadBannerSlot(_slot: String, id: String) -> void:
		banners_loaded += 1
		banner_id = id
	func setBannerSlotVisible(_slot: String, visible: bool) -> void: banner_visible = visible


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	call_deferred("run")


func flush() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func run() -> void:
	check_units_config()
	check_desktop_has_no_ads()
	await check_service_lifecycle()
	await check_main_banner_and_revive()
	AdsService.detach_backend()
	print("[ads] units, desktop fallback, preload/banner lifecycle, banner screens & layout, revive offer/accept/decline/once/challenges: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)


func check_units_config() -> void:
	var real: Dictionary = AdsService.load_units(false)
	var demo: Dictionary = AdsService.load_units(true)
	check(real.get("menu_banner") == "R-M-20265899-3", "Release banner unit must be R-M-20265899-3")
	check(real.get("revive_rewarded") == "R-M-20265899-2", "Release rewarded unit must be R-M-20265899-2")
	check(demo.get("menu_banner") == "demo-banner-yandex" and demo.get("revive_rewarded") == "demo-rewarded-yandex", "Debug builds must use Yandex demo units")


func check_desktop_has_no_ads() -> void:
	AdsService.detach_backend()
	check(not AdsService.supported and not AdsService.can_show_rewarded(), "Desktop has no native ads and offers no rewarded ad")
	check(not AdsService.request_rewarded(), "Desktop cannot show a rewarded ad")
	AdsService.set_banner_visible(true)
	check(AdsService.banner_height == 0, "Without the plugin the banner takes no room")
	AdsService.set_banner_visible(false)


func check_service_lifecycle() -> void:
	var service: Node = load("res://scripts/ads_service.gd").new()
	add_child(service)
	service.set_banner_visible(true)
	var native := FakeAds.new()
	service.attach_backend(native, true)
	await flush()
	check(service.initialized, "Initialization completes")
	check(native.banner_visible, "A banner wish made before the plugin attached reaches it")
	check(native.reward_loads == 1 and native.reward_id == "demo-rewarded-yandex", "Initialization preloads the demo rewarded ad once")
	check(native.banners_loaded == 1 and native.banner_id == "demo-banner-yandex", "The wanted banner loads the demo unit once")
	service.preload_rewarded()
	check(native.reward_loads == 1, "Concurrent rewarded preloads are deduplicated")
	check(not service.can_show_rewarded() and not service.request_rewarded(), "Nothing is shown before an ad has loaded")
	native.rewarded_loaded.emit()
	await flush()
	check(service.can_show_rewarded(), "A loaded rewarded ad can be shown")
	native.banner_slot_height_changed.emit("menu", 132)
	await flush()
	check(service.banner_height == 132, "The measured banner height is reported")
	var finished := [null]
	service.rewarded_finished.connect(func(e: bool): finished[0] = e)
	check(service.request_rewarded() and native.rewards_shown == 1, "A rewarded ad is shown")
	check(service.fullscreen and not native.banner_visible and service.banner_height == 0, "The banner hides behind a fullscreen ad")
	native.reward_earned.emit()
	native.rewarded_closed.emit()
	await flush()
	check(finished[0] == true and not service.fullscreen, "Closing after the reward reports it earned")
	check(native.banner_visible and service.banner_height == 132, "The banner returns after the ad")
	check(native.reward_loads == 2, "The next rewarded ad preloads after one is used")
	# Failure: banner gives back its room, a failed show reports no reward.
	native.ad_failed.emit("bannermenu_load", "no fill")
	await flush()
	check(service.banner_height == 0, "A failed banner takes no room")
	native.rewarded_loaded.emit()
	await flush()
	finished[0] = null
	service.request_rewarded()
	native.ad_failed.emit("rewarded_show", "broken")
	await flush()
	check(finished[0] == false and not service.fullscreen, "A failed show finishes without a reward")
	service.set_banner_visible(false)
	check(not native.banner_visible and service.banner_height == 0, "Hiding the banner frees its room")
	service.queue_free()


func _crash(main) -> void:
	# A fatal collision with rewind history and no Chrono-Shield charge.
	main.game.nitro = 0.0
	main.game.distance = 400.0
	for _i in range(6):
		main.game.rewind_frames.append(main.game._snapshot_state())
	main.game._crash()


func check_main_banner_and_revive() -> void:
	Sfx.set_music_enabled(false)
	var main = load("res://tests/main_without_persistence.gd").new()
	main.cars_3d = false
	main.music_on = false
	main.tutorial_done = true
	add_child(main)
	main.game.set_process(false)
	var native := FakeAds.new()
	AdsService.attach_backend(native, true)
	await flush()

	# Banner: menu, garage and finish screen only, UI below its real height.
	main.show_menu()
	main._sync_ads_banner()
	native.banner_slot_height_changed.emit("menu", 120)
	await flush()
	check(native.banner_visible and native.banners_loaded == 1, "Menu shows the banner")
	check(is_equal_approx(main.menu.offset_top, 120.0), "Menu moves down by the banner height")
	main.show_garage()
	main._sync_ads_banner()
	check(native.banner_visible and is_equal_approx(main.garage.offset_top, 120.0), "Garage shows the banner and makes room")
	main._start_solo_game()
	main._sync_ads_banner()
	check(not native.banner_visible, "No banner during a race")
	check(is_equal_approx(main.menu.offset_top, 0.0), "Race screens take no banner room")

	# No ad loaded: no offer, the run settles immediately.
	var coins0: int = main.coins
	_crash(main)
	check(not main.revive_open and main.coins > coins0, "Without a loaded ad there is no offer and no waiting")
	await get_tree().create_timer(1.2).timeout
	main._sync_ads_banner()
	check(main.result_panel.visible and native.banner_visible, "Finish screen shows the banner")
	check(is_equal_approx(main.result_panel.offset_top, 120.0), "Finish screen moves down by the banner height")

	# Offer, countdown runs out: the run is paid once and finishes.
	native.rewarded_loaded.emit()
	await flush()
	main._start_solo_game()
	var coins1: int = main.coins
	_crash(main)
	check(main.revive_open and main.revive_panel.visible, "A fatal crash offers the revive")
	check(main.coins == coins1, "Nothing is paid while the revive is offered")
	main._sync_ads_banner()
	check(not native.banner_visible, "No banner over the revive offer")
	main._process(2.0)
	check(main.revive_count_label.text == "3", "The countdown shows the remaining seconds")
	main._process(3.1)
	check(not main.revive_open and main.coins > coins1, "The offer expires after 5 s and the run is paid")
	check(native.rewards_shown == 0, "An expired offer shows no ad")

	# Accept: the ad plays, the car rewinds and races on, once per run.
	main._start_solo_game()
	var coins2: int = main.coins
	_crash(main)
	check(main.revive_open, "The loaded ad is offered again in a new run")
	main._accept_revive()
	check(native.rewards_shown == 1, "Accepting shows the rewarded ad")
	main._process(10.0)
	check(main.revive_open, "The countdown stops while the ad plays")
	native.reward_earned.emit()
	native.rewarded_closed.emit()
	await flush()
	check(not main.revive_open and main.game.rewinding and main.coins == coins2, "The reward revives the run without paying it out")
	for _i in range(200):
		if not main.game.rewinding:
			break
		main.game._tick_rewind(0.05)
	check(main.game.running and not main.game.crashed and main.game._rewind_invuln > 0.0, "Revive rewinds like the Chrono-Shield, with invulnerability")
	check(not main.tutorial_panel.visible, "The rewind notice is gone once the run resumes")
	native.rewarded_loaded.emit()
	await flush()
	main.game._rewind_invuln = 0.0
	_crash(main)
	check(not main.revive_open and main.coins > coins2, "Revive is offered only once per run")

	# Ad closed without the reward: the run finishes.
	main._start_solo_game()
	var coins3: int = main.coins
	_crash(main)
	main._accept_revive()
	native.rewarded_closed.emit()
	await flush()
	check(not main.revive_open and not main.game.rewinding and main.coins > coins3, "Closing the ad early finishes the run")

	# Back declines the offer.
	native.rewarded_loaded.emit()
	await flush()
	main._start_solo_game()
	var coins4: int = main.coins
	_crash(main)
	main._on_back()
	check(not main.revive_open and main.coins > coins4, "Back declines the revive")

	# Quitting a run is not a crash: no offer.
	main._start_solo_game()
	main.game.rewind_frames.append(main.game._snapshot_state())
	main.game.finish_run()
	check(not main.revive_open, "Ending a run from the menu offers no revive")

	# Daily Challenge and duels: no revive (ghost fairness).
	main._sync_daily_date()
	main.active_challenge = ChallengeCodec.daily_challenge()
	main.start_game()
	_crash(main)
	check(not main.revive_open, "No revive in the Daily Challenge")
	main.game.challenge_config = {"type": "duel"}
	check(not main.game.can_revive(), "No revive in a duel")

	main.show_menu()
	main.queue_free()
	await flush()
