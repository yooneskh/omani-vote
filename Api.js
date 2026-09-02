var DEFAULT_ORIGIN = "https://khoshghadam.com"
var UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
var HOST_PATTERN = /^(\[[0-9a-f:]+\]|localhost|[a-z0-9]([a-z0-9.-]*[a-z0-9])?)(:[1-9][0-9]{0,4})?$/i
var BASE64_PATTERN = /^[A-Za-z0-9+/]+=*$/
var ALLOWED_METHODS = { GET: true, POST: true }
var ALLOWED_SORTS = { hot: true, new: true, top: true }
var ALLOWED_HEADERS = { "x-captcha-id": true, "x-captcha-code": true }
var MAX_TOKEN = 64
var MAX_HEADER = 80
var MAX_NAME = 80
var MAX_BODY = 2000
var MAX_COMMENT = 500
var MAX_IDEAS = 40
var MAX_COMMENTS = 100
var MAX_CAPTCHA_IMAGE = 48000

function defaultState() {
  return {
    apiBase: DEFAULT_ORIGIN,
    token: "",
    user: null
  }
}

function hasControl(value) {
  var text = String(value == null ? "" : value)
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code < 32 || code === 127) return true
  }
  return false
}

function isUuid(value) {
  return typeof value === "string" && value.length <= MAX_TOKEN && UUID_PATTERN.test(value)
}

function cleanText(value, max, allowNewline) {
  var text = String(value == null ? "" : value)
  var out = ""
  for (var i = 0; i < text.length && out.length < max; i++) {
    var code = text.charCodeAt(i)
    if (allowNewline && code === 10) out += "\n"
    else if (code >= 32 && code !== 127) out += text.charAt(i)
  }
  return out
}

function pinOrigin(raw) {
  var value = String(raw || "").replace(/\/$/, "")
  if (!value || hasControl(value) || value.indexOf("@") !== -1 || value.indexOf("\\") !== -1)
    return DEFAULT_ORIGIN
  var match = value.match(/^(https?):\/\/([^\/?#]+)(?:[\/?#].*)?$/i)
  if (!match || !HOST_PATTERN.test(match[2])) return DEFAULT_ORIGIN
  return match[1].toLowerCase() + "://" + match[2]
}

function safeToken(value) {
  return isUuid(value) && !hasControl(value) ? value : ""
}

function safeHeaderValue(value) {
  var text = String(value == null ? "" : value)
  if (!text || text.length > MAX_HEADER || hasControl(text)) return ""
  return text
}

function safeSort(value) {
  return ALLOWED_SORTS[value] ? value : "hot"
}

function parseAuthor(raw) {
  if (!raw || typeof raw !== "object") return { name: "Someone" }
  return {
    _id: isUuid(raw._id) ? raw._id : undefined,
    name: cleanText(raw.name, MAX_NAME, false),
    username: cleanText(raw.username, MAX_NAME, false)
  }
}

function parseUser(raw) {
  if (!raw || typeof raw !== "object") return null
  var user = {
    _id: isUuid(raw._id) ? raw._id : "",
    name: cleanText(raw.name, MAX_NAME, false),
    username: cleanText(raw.username, MAX_NAME, false)
  }
  return user._id ? user : null
}

function parseIdea(raw) {
  if (!raw || typeof raw !== "object" || !isUuid(raw._id)) return null
  return {
    _id: raw._id,
    name: cleanText(raw.name || raw.title, MAX_NAME, false),
    body: raw.body == null ? "" : cleanText(raw.body, MAX_BODY, true),
    author: parseAuthor(raw.author),
    voteCount: Math.max(0, Math.min(1000000000, Math.floor(Number(raw.voteCount) || 0))),
    commentCount: Math.max(0, Math.min(1000000000, Math.floor(Number(raw.commentCount) || 0))),
    featuredOn: typeof raw.featuredOn === "string" && !hasControl(raw.featuredOn) && raw.featuredOn.length <= 32
      ? raw.featuredOn
      : "",
    createdAt: Math.max(0, Math.floor(Number(raw.createdAt) || 0)),
    myVote: !!raw.myVote,
    comments: raw.comments ? parseComments(raw.comments) : undefined
  }
}

function parseComments(raw) {
  if (!raw || Object.prototype.toString.call(raw) !== "[object Array]") return []
  var out = []
  for (var i = 0; i < raw.length && out.length < MAX_COMMENTS; i++) {
    var comment = parseComment(raw[i])
    if (comment) out.push(comment)
  }
  return out
}

function parseComment(raw) {
  if (!raw || typeof raw !== "object" || !isUuid(raw._id)) return null
  var body = cleanText(raw.body, MAX_COMMENT, true)
  if (!body) return null
  return {
    _id: raw._id,
    body: body,
    author: parseAuthor(raw.author),
    createdAt: Math.max(0, Math.floor(Number(raw.createdAt) || 0))
  }
}

function parseIdeaList(raw) {
  if (!raw || Object.prototype.toString.call(raw) !== "[object Array]") return []
  var out = []
  for (var i = 0; i < raw.length && out.length < MAX_IDEAS; i++) {
    var idea = parseIdea(raw[i])
    if (idea) {
      delete idea.comments
      out.push(idea)
    }
  }
  return out
}

function parseFeatured(raw) {
  return raw == null ? null : parseIdea(raw)
}

function parseCaptcha(raw) {
  if (!raw || typeof raw !== "object") return { _id: "", image: "" }
  var image = String(raw.image == null ? "" : raw.image)
  if (image.length > MAX_CAPTCHA_IMAGE || !BASE64_PATTERN.test(image)) image = ""
  return {
    _id: safeHeaderValue(raw._id),
    image: image
  }
}

function parseSession(raw) {
  if (!raw || typeof raw !== "object") return { token: "" }
  return { token: safeToken(raw.token) }
}

function parseState(raw) {
  var fallback = defaultState()
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return fallback
    return {
      apiBase: pinOrigin(data.apiBase),
      token: safeToken(data.token),
      user: parseUser(data.user)
    }
  } catch (e) {
    return fallback
  }
}

function serializeState(state) {
  return JSON.stringify({
    apiBase: pinOrigin(state && state.apiBase),
    token: safeToken(state && state.token),
    user: parseUser(state && state.user)
  }, null, 2) + "\n"
}

function joinUrl(base, path, query) {
  var origin = pinOrigin(base)
  var suffix = String(path || "")
  if (!suffix || suffix.charAt(0) !== "/" || hasControl(suffix) || suffix.indexOf("\\") !== -1)
    return ""
  var url = origin + suffix
  if (!query) return url
  var parts = []
  for (var key in query) {
    if (query[key] === undefined || query[key] === null || query[key] === "") continue
    if (hasControl(key) || hasControl(query[key])) continue
    parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(query[key])))
  }
  return parts.length ? url + "?" + parts.join("&") : url
}

function ideaPath(ideaId, suffix) {
  if (!isUuid(ideaId)) return ""
  return "/api/omani/ideas/" + encodeURIComponent(ideaId) + (suffix || "")
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
  if (!args || !args.url) return ""
  var url = String(args.url)
  var origin = pinOrigin(url)
  if (!url || hasControl(url) || url.indexOf(origin) !== 0) return ""

  var lines = []
  if (args.method && args.method !== "GET") {
    if (!ALLOWED_METHODS[args.method]) return ""
    lines.push('request = "' + args.method + '"')
  }

  var token = safeToken(args.token)
  if (args.token && !token) return ""
  if (token) lines.push('header = "authorization: ' + token + '"')

  if (args.headers) {
    for (var key in args.headers) {
      if (!ALLOWED_HEADERS[key]) return ""
      var header = safeHeaderValue(args.headers[key])
      if (!header) return ""
      lines.push('header = "' + escapeCurlConfig(key + ": " + header) + '"')
    }
  }

  if (args.body !== undefined) {
    var body = JSON.stringify(args.body)
    if (!body || hasControl(body)) return ""
    lines.push('header = "content-type: application/json"')
    lines.push('data-binary = "' + escapeCurlConfig(body) + '"')
  }

  lines.push('url = "' + escapeCurlConfig(url) + '"')
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
    pinOrigin: pinOrigin,
    isUuid: isUuid,
    safeToken: safeToken,
    safeSort: safeSort,
    joinUrl: joinUrl,
    ideaPath: ideaPath,
    curlCommand: curlCommand,
    curlConfig: curlConfig,
    parseCurl: parseCurl,
    parseFeatured: parseFeatured,
    parseIdea: parseIdea,
    parseIdeaList: parseIdeaList,
    parseComment: parseComment,
    parseCaptcha: parseCaptcha,
    parseSession: parseSession,
    parseUser: parseUser
  }
}
