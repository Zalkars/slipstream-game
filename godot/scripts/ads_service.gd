extends Node

# Yandex Mobile Ads (autoload "AdsService"), ported from Last Hook's AdsService.
# The native side is the SlipstreamAds Android plugin (addons/slipstream_ads,
# source in tools/android-ads). On desktop, in the editor and in headless
# tests there is no plugin: supported stays false, the banner takes no room
# and no rewarded ad is ever offered.
#
# - One top banner slot ("menu") with one unit, shown on the main menu,
#   garage, finish screen and (0.8.0) during the race. UI moves down by its
#   real, measured height; the race reserves the height measured before it
#   starts, so a banner loading late or failing never moves the race HUD.
# - One rewarded ad: the revive after a fatal crash.
# Debug builds request Yandex's demo units, release builds the real ones.

signal availability_changed
signal fullscreen_changed(active: bool)
signal rewarded_finished(earned: bool)
signal banner_layout_changed

const CONFIG_PATH := "res://data/yandex_ads.json"
const SINGLETON := "SlipstreamAds"
const BANNER_SLOT := "menu"
const RETRY_SECONDS := 30.0
const LOAD_TIMEOUT := 45.0

var backend: Object
var supported := false
var initialized := false
var rewarded_ready := false
var fullscreen := false
var test_mode := true
var units: Dictionary = {}
# Height of the visible banner in physical screen pixels (0 = no room taken).
var banner_height := 0

var _banner_wanted := false
var _banner_requested := false
var _banner_native_height := 0
# Tallest banner measured this session (kept when a later load fails).
var _banner_seen_height := 0
var _reward_earned := false
var _showing := ""
var _loading: Dictionary = {}
var _retry_after: Dictionary = {}


func _ready() -> void:
	# Let the first frame appear before the SDK touches the Android UI.
	call_deferred("setup")


func setup() -> void:
	if supported or not OS.has_feature("android") or not Engine.has_singleton(SINGLETON):
		return
	attach_backend(Engine.get_singleton(SINGLETON), OS.is_debug_build())


static func load_units(use_demo_units: bool) -> Dictionary:
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (cfg is Dictionary):
		return {}
	return (cfg["demo_units"] if use_demo_units else cfg["ad_units"]).duplicate()


# Also takes a deterministic fake backend in tests, without SDK requests.
func attach_backend(native: Object, use_demo_units: bool) -> void:
	backend = native
	test_mode = use_demo_units
	units = load_units(use_demo_units)
	supported = true
	backend.connect("initialized", _on_initialized, CONNECT_DEFERRED)
	backend.connect("rewarded_loaded", _on_rewarded_loaded, CONNECT_DEFERRED)
	backend.connect("reward_earned", _on_reward_earned, CONNECT_DEFERRED)
	backend.connect("rewarded_closed", _on_rewarded_closed, CONNECT_DEFERRED)
	backend.connect("ad_failed", _on_failed, CONNECT_DEFERRED)
	backend.connect("banner_slot_height_changed", _on_banner_height, CONNECT_DEFERRED)
	# A screen asked for the banner before the plugin was attached.
	if _banner_wanted:
		backend.call("setBannerSlotVisible", BANNER_SLOT, not fullscreen)
	backend.call("initialize")


# Back to the "no plugin" state (tests restore the autoload with this).
func detach_backend() -> void:
	if is_instance_valid(backend):
		for sig in ["initialized", "rewarded_loaded", "reward_earned", "rewarded_closed", "ad_failed", "banner_slot_height_changed"]:
			for c in backend.get_signal_connection_list(sig):
				if c.callable.get_object() == self:
					backend.disconnect(sig, c.callable)
	backend = null
	supported = false
	initialized = false
	rewarded_ready = false
	fullscreen = false
	units = {}
	banner_height = 0
	_banner_requested = false
	_banner_native_height = 0
	_banner_seen_height = 0
	_reward_earned = false
	_showing = ""
	_loading.clear()
	_retry_after.clear()


func _on_initialized() -> void:
	if initialized:
		return
	initialized = true
	preload_rewarded()
	if _banner_wanted:
		_load_banner()
	availability_changed.emit()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _can_load(kind: String) -> bool:
	return initialized and not fullscreen and not _loading.has(kind) and _now() >= float(_retry_after.get(kind, 0.0))


func preload_rewarded() -> void:
	if supported and not rewarded_ready and _can_load("rewarded") and units.has("revive_rewarded"):
		_loading["rewarded"] = _now()
		backend.call("loadRewarded", str(units["revive_rewarded"]))


# --- banner -----------------------------------------------------------------

func set_banner_visible(visible: bool) -> void:
	_banner_wanted = visible
	_apply_banner_height()
	if not supported:
		return
	backend.call("setBannerSlotVisible", BANNER_SLOT, visible and not fullscreen)
	if visible and not _banner_requested:
		_load_banner()


func is_banner_wanted() -> bool:
	return _banner_wanted


# Loads the banner without showing it, so the next screen that wants it (a
# race that starts without one) already knows its height.
func prefetch_banner() -> void:
	if supported and initialized and not _banner_requested:
		_load_banner()


# Height in physical pixels of a banner that has loaded at least once this
# session, shown or not; 0 when none has (no network, no fill, desktop).
func known_banner_height() -> int:
	return _banner_seen_height if supported else 0


func _load_banner() -> void:
	if not _can_load("banner") or not units.has("menu_banner"):
		return
	_banner_requested = true
	_loading["banner"] = _now()
	backend.call("loadBannerSlot", BANNER_SLOT, str(units["menu_banner"]))


# Banner height converted to the UI's design units (viewport pixels).
func banner_height_in(viewport: Viewport) -> float:
	return px_to_design(viewport, banner_height)


# Physical screen pixels to the UI's design units.
static func px_to_design(viewport: Viewport, pixels: int) -> float:
	if pixels <= 0 or viewport == null:
		return 0.0
	var ratio := 1.0
	var window := DisplayServer.window_get_size()
	if OS.has_feature("mobile") and window.y > 0:
		ratio = viewport.get_visible_rect().size.y / float(window.y)
	return float(pixels) * ratio


func _on_banner_height(slot_name: String, height: int) -> void:
	if slot_name != BANNER_SLOT:
		return
	if height > 0:
		_loading.erase("banner")
		_banner_requested = true
	_banner_native_height = maxi(0, height)
	_banner_seen_height = maxi(_banner_seen_height, _banner_native_height)
	_apply_banner_height()


func _apply_banner_height() -> void:
	var h := _banner_native_height if _banner_wanted and not fullscreen and supported else 0
	if h == banner_height:
		return
	banner_height = h
	banner_layout_changed.emit()


# --- rewarded ---------------------------------------------------------------

# True only when an ad is loaded and can be shown right now: the game never
# waits for a load before offering the revive.
func can_show_rewarded() -> bool:
	return supported and initialized and rewarded_ready and not fullscreen


func request_rewarded() -> bool:
	if not can_show_rewarded():
		preload_rewarded()
		return false
	rewarded_ready = false
	_reward_earned = false
	_showing = "rewarded"
	_set_fullscreen(true)
	backend.call("showRewarded")
	return true


func _set_fullscreen(active: bool) -> void:
	fullscreen = active
	if is_instance_valid(backend):
		backend.call("setBannerSlotVisible", BANNER_SLOT, _banner_wanted and not active)
	_apply_banner_height()
	fullscreen_changed.emit(active)
	availability_changed.emit()


func _on_rewarded_loaded() -> void:
	_loading.erase("rewarded")
	rewarded_ready = true
	availability_changed.emit()


func _on_reward_earned() -> void:
	if _showing == "rewarded" and fullscreen:
		_reward_earned = true


func _on_rewarded_closed() -> void:
	if _showing != "rewarded":
		return
	var earned := _reward_earned
	_reward_earned = false
	_showing = ""
	_set_fullscreen(false)
	rewarded_finished.emit(earned)
	preload_rewarded()


func _on_failed(kind: String, message: String) -> void:
	print("Yandex Ads / %s: %s" % [kind, message])
	var format := kind.get_slice("_", 0)
	_loading.erase(format)
	_retry_after[format] = _now() + RETRY_SECONDS
	if format == "rewarded":
		rewarded_ready = false
	if kind == "banner" + BANNER_SLOT + "_load" or kind == "banner_load":
		_loading.erase("banner")
		_retry_after["banner"] = _now() + RETRY_SECONDS
		_banner_requested = false
		_banner_native_height = 0
		_apply_banner_height()
	if kind.ends_with("_show") and _showing == format:
		_showing = ""
		_reward_earned = false
		_set_fullscreen(false)
		rewarded_finished.emit(false)
	availability_changed.emit()


func _process(_delta: float) -> void:
	if not supported:
		return
	# A failed banner retries on its own while its screen stays open, and a
	# failed rewarded load retries so the next crash can offer a revive.
	if initialized and not fullscreen:
		if _banner_wanted and not _banner_requested:
			_load_banner()
		if not rewarded_ready:
			preload_rewarded()
	for kind in _loading.keys():
		if _now() - float(_loading[kind]) > LOAD_TIMEOUT:
			_on_failed(str(kind) + "_load", "Loading timed out")


func _exit_tree() -> void:
	if is_instance_valid(backend):
		backend.call("setBannerSlotVisible", BANNER_SLOT, false)
