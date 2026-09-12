class_name DeepSeekClient
extends Node
## 一次问答。上层只调 ask()。
##
## 这里是**唯一**知道 provider 是谁的地方：URL、鉴权头、报文格式、超时、错误码
## 全部关在这个文件里。以后想换 OpenAI / Gemini / Claude / 本地模型，
## 只换这个文件，游戏逻辑一行不动。
##
## 回调式而不是 await 式：调用方拿到的永远是同一件事（一个结果字典），
## 测试里的假 client 也能同步立刻回调 —— 不需要伪造协程，测试因此简单得多。

const ERR_NO_KEY := "no_key"
const ERR_BUSY := "busy"
const ERR_NETWORK := "network"
const ERR_TIMEOUT := "timeout"
const ERR_AUTH := "auth"
const ERR_RATE := "rate_limit"
const ERR_SERVER := "server"

var _http: HTTPRequest
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = AiConfig.TIMEOUT_SEC
	add_child(_http)


## 结果通过 sink 回调：{ok: bool, text: String, code: String}。
## code 只在 ok == false 时有意义，取值是上面那组 ERR_*。
func ask(system: String, user: String, sink: Callable) -> void:
	if _busy:
		sink.call(_result(false, "", ERR_BUSY))
		return
	if not AiConfig.has_key():
		sink.call(_result(false, "", ERR_NO_KEY))
		return

	_busy = true
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + AiConfig.api_key(),
	])
	var payload := {
		"model": AiConfig.MODEL,
		"messages": [
			{"role": "system", "content": system},
			{"role": "user", "content": user},
		],
		# 0.3 而不是 1.0：这是分析，不是创作。要的是稳定，不是惊喜。
		"temperature": 0.3,
		"max_tokens": AiConfig.MAX_TOKENS,
		"stream": false,
	}
	var err := _http.request(AiConfig.ENDPOINT, headers, HTTPClient.METHOD_POST,
		JSON.stringify(payload))
	if err != OK:
		_busy = false
		sink.call(_result(false, "", ERR_NETWORK))
		return

	var got: Array = await _http.request_completed
	_busy = false
	sink.call(_interpret(got))


## 把 HTTP 世界翻译成四种「然后该怎么办」。上层据此挑文案，
## 它不需要知道状态码是什么，更不该把 500 显示给玩家。
func _interpret(got: Array) -> Dictionary:
	var transport := int(got[0])
	var status := int(got[1])
	var body: PackedByteArray = got[3]

	if transport == HTTPRequest.RESULT_TIMEOUT:
		return _result(false, "", ERR_TIMEOUT)
	if transport != HTTPRequest.RESULT_SUCCESS:
		return _result(false, "", ERR_NETWORK)
	if status == 401 or status == 403:
		return _result(false, "", ERR_AUTH)
	if status == 429:
		return _result(false, "", ERR_RATE)
	if status != 200:
		return _result(false, "", ERR_SERVER)

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _result(false, "", ERR_SERVER)
	var choices: Array = parsed.get("choices", [])
	if choices.is_empty():
		return _result(false, "", ERR_SERVER)
	var message: Dictionary = choices[0].get("message", {})
	var text := str(message.get("content", "")).strip_edges()
	if text == "":
		return _result(false, "", ERR_SERVER)
	return _result(true, text, "")


static func _result(ok: bool, text: String, code: String) -> Dictionary:
	return {"ok": ok, "text": text, "code": code}
