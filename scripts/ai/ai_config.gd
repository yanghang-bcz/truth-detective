class_name AiConfig
extends RefCounted
## AI 配置：key 从哪来、模型叫什么、等多久、答多长。
##
## **这个文件里永远不出现 key。** 仓库是公开的，写进去等于把 key 发给陌生人。
## key 的来源只有两条路，按优先级：
##   1) 系统环境变量 DEEPSEEK_API_KEY —— 推荐，本地和 CI 都能用，不落盘；
##   2) config/local.env 里的 DEEPSEEK_API_KEY=... —— 本地方便，已在 .gitignore 里，
##      仓库只提供 config/local.env.example。
##
## 刻意不做的事：不读 user://、不读命令行参数。少一条路径就少一处会泄漏的地方。

const ENV_KEY := "DEEPSEEK_API_KEY"
const LOCAL_ENV_PATH := "res://config/local.env"

const ENDPOINT := "https://api.deepseek.com/chat/completions"
const MODEL := "deepseek-chat"
const TIMEOUT_SEC := 10.0   ## 玩家不会等模型半分钟；超时就退回离线答复
const MAX_TOKENS := 400     ## 50–100 词 / 70–150 字，两段以内

## ── Web 版：走同域后端代理 ───────────────────────────────────────────
##
## 浏览器里的 .pck 是**公开文件**，任何人下载后都能翻出里面的字符串。
## 所以网页版绝不能自带密钥 —— 那样等于把 key 挂在网页上。
##
## 网页版改成请求同域后端 /api/analyst：后端持有密钥、加限流与配额、
## 校验输出后再回传。前端从头到尾不知道密钥长什么样。
##
## 桌面版（跑在自己机器上）行为**完全不变**：仍然直连 DeepSeek，
## 仍然从环境变量 / config/local.env 读密钥。
const PROXY_PATH := "/api/analyst"

## 本地调试用：设了这个环境变量就能让桌面版也走代理，
## 不必为了测代理去跑一次 Web 导出。
const ENV_FORCE_PROXY := "TD_AI_PROXY"


static func api_key() -> String:
	var from_env := OS.get_environment(ENV_KEY).strip_edges()
	if from_env != "":
		return from_env
	return _from_local_env()


static func has_key() -> bool:
	return api_key() != ""


## 是否经由同域后端代理。网页版恒为真。
static func use_proxy() -> bool:
	if OS.has_feature("web"):
		return true
	return OS.get_environment(ENV_FORCE_PROXY).strip_edges() != ""


## 真正要请求的地址。代理模式下是**绝对地址**，原因见 _proxy_url()。
static func endpoint() -> String:
	return _proxy_url() if use_proxy() else ENDPOINT


## 代理地址必须是绝对的。Godot Web 的 HTTPRequest 不会拿相对路径去套文档基址
## —— 传 "/api/analyst" 进去会直接判定为无效参数、连网络都不发，
## 表现是"AI 永远答不出来"，而服务端日志里一条记录都没有。
## 所以向浏览器要一下 location.origin 自己拼。同域，因此仍然不需要处理 CORS。
static func _proxy_url() -> String:
	if OS.has_feature("web"):
		var origin := str(JavaScriptBridge.eval("location.origin", true)).strip_edges()
		if origin != "" and origin != "null" and origin.begins_with("http"):
			return origin + PROXY_PATH
	return PROXY_PATH


## "能不能调模型" —— 与"手里有没有钥匙"是两件事。
## 代理模式下钥匙在后端，前端什么都没有，但依然可以调。
static func can_call_model() -> bool:
	return use_proxy() or has_key()


## 极简 .env 解析：只认 KEY=VALUE，忽略空行和 # 开头的注释。
## 不做变量插值、不做 export 语法 —— 少一种语法就少一种「为什么没读到」。
static func _from_local_env() -> String:
	if not FileAccess.file_exists(LOCAL_ENV_PATH):
		return ""
	var f := FileAccess.open(LOCAL_ENV_PATH, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		if line.substr(0, eq).strip_edges() != ENV_KEY:
			continue
		var value := line.substr(eq + 1).strip_edges()
		return value.trim_prefix("\"").trim_suffix("\"")
	return ""
