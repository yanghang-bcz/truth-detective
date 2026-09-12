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


static func api_key() -> String:
	var from_env := OS.get_environment(ENV_KEY).strip_edges()
	if from_env != "":
		return from_env
	return _from_local_env()


static func has_key() -> bool:
	return api_key() != ""


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
