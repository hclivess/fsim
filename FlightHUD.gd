# FlightHUD.gd
extends Control

var speed_label: Label
var altitude_label: Label
var throttle_label: Label
var stall_warning: Label
var damage_bar: ProgressBar

func _ready():
	# Create speed label
	speed_label = Label.new()
	speed_label.position = Vector2(20, 20)
	speed_label.add_theme_color_override("font_color", Color.WHITE)
	speed_label.add_theme_constant_override("outline_size", 2)
	speed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(speed_label)
	
	# Create altitude label
	altitude_label = Label.new()
	altitude_label.position = Vector2(20, 50)
	altitude_label.add_theme_color_override("font_color", Color.WHITE)
	altitude_label.add_theme_constant_override("outline_size", 2)
	altitude_label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(altitude_label)
	
	# Create throttle label
	throttle_label = Label.new()
	throttle_label.position = Vector2(20, 80)
	throttle_label.add_theme_color_override("font_color", Color.WHITE)
	throttle_label.add_theme_constant_override("outline_size", 2)
	throttle_label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(throttle_label)
	
	# Create stall warning
	stall_warning = Label.new()
	stall_warning.text = "STALL"
	stall_warning.add_theme_font_size_override("font_size", 32)
	stall_warning.add_theme_color_override("font_color", Color.RED)
	stall_warning.add_theme_constant_override("outline_size", 2)
	stall_warning.add_theme_color_override("font_outline_color", Color.BLACK)
	stall_warning.position = Vector2(get_viewport().get_visible_rect().size.x/2 - 50, 50)
	stall_warning.hide()
	add_child(stall_warning)
	
	# Create damage bar
	damage_bar = ProgressBar.new()
	damage_bar.position = Vector2(20, 110)
	damage_bar.size = Vector2(180, 20)
	damage_bar.max_value = 100
	add_child(damage_bar)

func update_hud(data):
	speed_label.text = "SPD: %.1f km/h" % (data.speed * 3.6)
	altitude_label.text = "ALT: %.0f m" % data.altitude
	throttle_label.text = "THR: %.0f%%" % (data.throttle * 100)
	
	# Update stall warning
	if data.stalling:
		stall_warning.show()
		stall_warning.modulate = Color(1, 0, 0, sin(Time.get_ticks_msec() * 0.01) * 0.5 + 0.5)
	else:
		stall_warning.hide()
	
	# Update damage bar
	damage_bar.value = data.damage
	damage_bar.modulate = Color(1, 1 - data.damage/100.0, 1 - data.damage/100.0)
