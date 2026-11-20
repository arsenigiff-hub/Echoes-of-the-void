extends Node
"""Local SQLite storage for offline profiles, saves, and completion records."""

const DB_PATH := "user://echoes_profiles.sqlite"
const HASH_ROUNDS := 12000

var db: Object
var _crypto := Crypto.new()
var active_profile_id := 0
var active_username := ""
var difficulty := "standard"
var resume_requested := false
var session_playtime := 0.0


func _ready() -> void:
	if not ClassDB.class_exists("SQLite"):
		push_error("ProfileDB: SQLite GDExtension is not available")
		return
	db = ClassDB.instantiate("SQLite")
	db.path = DB_PATH
	db.verbosity_level = 0
	db.foreign_keys = true
	if not db.open_db():
		push_error("ProfileDB: could not open local database: %s" % db.error_message)
		return
	_ensure_schema()


func _ensure_schema() -> void:
	var statements := [
		"CREATE TABLE IF NOT EXISTS profiles (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL COLLATE NOCASE UNIQUE, salt TEXT NOT NULL, password_hash TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)",
		"CREATE TABLE IF NOT EXISTS saves (id INTEGER PRIMARY KEY AUTOINCREMENT, profile_id INTEGER NOT NULL UNIQUE, chapter INTEGER NOT NULL DEFAULT 0, story_stage INTEGER NOT NULL DEFAULT 0, difficulty TEXT NOT NULL DEFAULT 'standard', playtime_seconds REAL NOT NULL DEFAULT 0, signals_found INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL DEFAULT '{}', updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(profile_id) REFERENCES profiles(id) ON DELETE CASCADE)",
		"CREATE TABLE IF NOT EXISTS records (id INTEGER PRIMARY KEY AUTOINCREMENT, profile_id INTEGER NOT NULL, completed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, playtime_seconds REAL NOT NULL, signals_found INTEGER NOT NULL, difficulty TEXT NOT NULL, FOREIGN KEY(profile_id) REFERENCES profiles(id) ON DELETE CASCADE)",
		"CREATE INDEX IF NOT EXISTS idx_records_score ON records(playtime_seconds ASC, signals_found DESC)"
	]
	for statement in statements:
		if not db.query(statement):
			push_error("ProfileDB schema error: %s" % db.error_message)


func list_profiles() -> Array[Dictionary]:
	if db == null:
		return []
	if not db.query("SELECT id, username, created_at FROM profiles ORDER BY username COLLATE NOCASE"):
		return []
	var result: Array[Dictionary] = []
	for row in db.query_result:
		result.append({"id": int(row.id), "username": String(row.username), "created_at": String(row.created_at)})
	return result


func register_profile(username: String, password: String) -> Dictionary:
	var clean_name := username.strip_edges()
	if clean_name.length() < 3 or clean_name.length() > 20:
		return {"ok": false, "error": "Имя должно содержать от 3 до 20 символов."}
	for character in clean_name:
		if not (character.is_valid_identifier() or "0123456789".contains(character) or character == " " or character == "-"):
			return {"ok": false, "error": "В имени допустимы буквы, цифры, пробел, _ и -."}
	if password.length() < 6 or password.length() > 128:
		return {"ok": false, "error": "Пароль должен содержать от 6 до 128 символов."}
	var salt := _crypto.generate_random_bytes(16)
	var salt_text := salt.hex_encode()
	var password_hash := _derive_password_hash(password, salt)
	if not db.query_with_bindings("INSERT INTO profiles(username, salt, password_hash) VALUES(?, ?, ?)", [clean_name, salt_text, password_hash]):
		if db.error_message.to_lower().contains("unique"):
			return {"ok": false, "error": "Такой профиль уже существует."}
		return {"ok": false, "error": "Не удалось создать профиль."}
	var new_id := int(db.last_insert_rowid)
	if not db.query_with_bindings("INSERT INTO saves(profile_id) VALUES(?)", [new_id]):
		push_error("ProfileDB: failed to create initial save row: %s" % db.error_message)
	return login(clean_name, password)


func login(username: String, password: String) -> Dictionary:
	if not db.query_with_bindings("SELECT id, username, salt, password_hash FROM profiles WHERE username = ?", [username.strip_edges()]):
		return {"ok": false, "error": "Не удалось проверить профиль."}
	if db.query_result.is_empty():
		return {"ok": false, "error": "Профиль или пароль не подходят."}
	var row: Dictionary = db.query_result[0]
	var salt := _hex_to_bytes(String(row.salt))
	var expected := String(row.password_hash)
	var candidate := _derive_password_hash(password, salt)
	if candidate != expected:
		return {"ok": false, "error": "Профиль или пароль не подходят."}
	active_profile_id = int(row.id)
	active_username = String(row.username)
	return {"ok": true, "id": active_profile_id, "username": active_username}


func logout() -> void:
	active_profile_id = 0
	active_username = ""


func rename_profile(new_username: String) -> Dictionary:
	if active_profile_id == 0:
		return {"ok": false, "error": "Сначала войди в профиль."}
	var clean_name := new_username.strip_edges()
	if clean_name.length() < 3 or clean_name.length() > 20:
		return {"ok": false, "error": "Имя должно содержать от 3 до 20 символов."}
	if not db.query_with_bindings("UPDATE profiles SET username = ? WHERE id = ?", [clean_name, active_profile_id]):
		return {"ok": false, "error": "Не удалось изменить имя профиля."}
	active_username = clean_name
	return {"ok": true}


func delete_profile(profile_id: int, password: String) -> Dictionary:
	if not db.query_with_bindings("SELECT salt, password_hash FROM profiles WHERE id = ?", [profile_id]) or db.query_result.is_empty():
		return {"ok": false, "error": "Профиль не найден."}
	var row: Dictionary = db.query_result[0]
	if _derive_password_hash(password, _hex_to_bytes(String(row.salt))) != String(row.password_hash):
		return {"ok": false, "error": "Пароль не подходит."}
	if not db.query_with_bindings("DELETE FROM profiles WHERE id = ?", [profile_id]):
		return {"ok": false, "error": "Не удалось удалить профиль."}
	if profile_id == active_profile_id:
		logout()
	return {"ok": true}


func save_progress(chapter: int, story_stage: int, playtime: float, signals_found: int, payload: Dictionary) -> bool:
	if active_profile_id == 0:
		return false
	var serialized := JSON.stringify(payload)
	return db.query_with_bindings("INSERT INTO saves(profile_id, chapter, story_stage, difficulty, playtime_seconds, signals_found, payload, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP) ON CONFLICT(profile_id) DO UPDATE SET chapter=excluded.chapter, story_stage=excluded.story_stage, difficulty=excluded.difficulty, playtime_seconds=excluded.playtime_seconds, signals_found=excluded.signals_found, payload=excluded.payload, updated_at=CURRENT_TIMESTAMP", [active_profile_id, chapter, story_stage, difficulty, playtime, signals_found, serialized])


func load_progress() -> Dictionary:
	if active_profile_id == 0:
		return {}
	if not db.query_with_bindings("SELECT chapter, story_stage, difficulty, playtime_seconds, signals_found, payload, updated_at FROM saves WHERE profile_id = ?", [active_profile_id]) or db.query_result.is_empty():
		return {}
	var row: Dictionary = db.query_result[0]
	var parsed: Variant = JSON.parse_string(String(row.payload))
	return {"chapter": int(row.chapter), "story_stage": int(row.story_stage), "difficulty": String(row.difficulty), "playtime_seconds": float(row.playtime_seconds), "signals_found": int(row.signals_found), "payload": parsed if parsed is Dictionary else {}, "updated_at": String(row.updated_at)}


func add_completion_record(playtime: float, signals_found: int) -> bool:
	if active_profile_id == 0:
		return false
	return db.query_with_bindings("INSERT INTO records(profile_id, playtime_seconds, signals_found, difficulty) VALUES(?, ?, ?, ?)", [active_profile_id, playtime, signals_found, difficulty])


func leaderboard(limit: int = 20) -> Array[Dictionary]:
	if not db.query_with_bindings("SELECT p.username, r.playtime_seconds, r.signals_found, r.difficulty, r.completed_at FROM records r JOIN profiles p ON p.id = r.profile_id ORDER BY r.playtime_seconds ASC, r.signals_found DESC LIMIT ?", [clampi(limit, 1, 100)]):
		return []
	var result: Array[Dictionary] = []
	for row in db.query_result:
		result.append(row.duplicate())
	return result


func _derive_password_hash(password: String, salt: PackedByteArray) -> String:
	# PBKDF2-HMAC-SHA256: local accounts are offline; plaintext is never written to storage.
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := _crypto.hmac_digest(HashingContext.HASH_SHA256, password.to_utf8_buffer(), block)
	var accumulator := u.duplicate()
	for _round in range(1, HASH_ROUNDS):
		u = _crypto.hmac_digest(HashingContext.HASH_SHA256, password.to_utf8_buffer(), u)
		for index in accumulator.size():
			accumulator[index] = accumulator[index] ^ u[index]
	return accumulator.hex_encode()


func _hex_to_bytes(value: String) -> PackedByteArray:
	var bytes := PackedByteArray()
	for index in range(0, value.length(), 2):
		bytes.append(value.substr(index, 2).hex_to_int())
	return bytes
