extends AudioStreamPlayer

# Бесшовный гул корабля: настраиваем зацикливание в рантайме (импортёр WAV
# в этой сборке не всегда сохраняет loop_mode из .import) и играем.

func _ready() -> void:
	if stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		stream = wav
	play()


func _exit_tree() -> void:
	# Чтобы плеер не держал ресурс при выходе из игры.
	stop()
