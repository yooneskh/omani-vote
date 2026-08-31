function defaultState() {
  return {
    apiBase: "https://khoshghadam.com",
    token: "",
    user: null
  }
}

function parseState(raw) {
  var fallback = defaultState()
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return fallback
    return {
      apiBase: typeof data.apiBase === "string" && data.apiBase ? data.apiBase.replace(/\/$/, "") : fallback.apiBase,
      token: typeof data.token === "string" ? data.token : "",
      user: data.user && typeof data.user === "object" ? data.user : null
    }
  } catch (e) {
    return fallback
  }
}

function serializeState(state) {
  return JSON.stringify({
    apiBase: state.apiBase || "https://khoshghadam.com",
    token: state.token || "",
    user: state.user || null
  }, null, 2) + "\n"
}

function joinUrl(base, path, query) {
  var url = String(base || "").replace(/\/$/, "") + path
  if (!query) return url

  var parts = []
  for (var key in query) {
    if (query[key] === undefined || query[key] === null || query[key] === "") continue
    parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(query[key])))
  }
  return parts.length ? url + "?" + parts.join("&") : url
}

function escapeCurlConfig(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
}

function curlCommand() {
  return [
    "curl", "-sS", "--max-time", "8", "--max-filesize", "1048576",
    "-w", "\n__STATUS__%{http_code}",
    "-K", "-"
  ]
}

function curlConfig(args) {
  var lines = []
  if (args.method && args.method !== "GET")
    lines.push('request = "' + escapeCurlConfig(args.method) + '"')
  if (args.token)
    lines.push('header = "authorization: ' + escapeCurlConfig(args.token) + '"')
  if (args.headers) {
    for (var key in args.headers)
      lines.push('header = "' + escapeCurlConfig(key + ": " + args.headers[key]) + '"')
  }
  if (args.body !== undefined) {
    lines.push('header = "content-type: application/json"')
    lines.push('data-binary = "' + escapeCurlConfig(JSON.stringify(args.body)) + '"')
  }
  lines.push('url = "' + escapeCurlConfig(args.url) + '"')
  return lines.join("\n") + "\n"
}

function parseCurl(raw) {
  var text = String(raw || "")
  var marker = "\n__STATUS__"
  var index = text.lastIndexOf(marker)
  if (index === -1) {
    return { ok: false, status: 0, data: null, error: "Could not reach the server." }
  }

  var status = parseInt(text.slice(index + marker.length), 10)
  var body = text.slice(0, index).replace(/^\uFEFF/, "")
  var data = null
  if (body) {
    try { data = JSON.parse(body) } catch (e) { data = null }
  }

  var error = ""
  if (!(status >= 200 && status < 300)) {
    error = (data && (data.message || data.statusMessage)) || "Something went wrong."
  }

  return {
    ok: status >= 200 && status < 300,
    status: status,
    data: data,
    error: error
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultState: defaultState,
    parseState: parseState,
    serializeState: serializeState,
    joinUrl: joinUrl,
    curlCommand: curlCommand,
    curlConfig: curlConfig,
    parseCurl: parseCurl
  }
}
