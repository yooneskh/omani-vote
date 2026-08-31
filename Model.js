function ideaName(idea) {
  return String(idea && (idea.name || idea.title) || "")
}

function excerpt(text, max) {
  var value = String(text || "").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  var limit = max || 140
  if (value.length <= limit) return value
  return value.slice(0, limit - 1).replace(/\s+\S*$/, "") + "…"
}

function weekdayLabel(date) {
  var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  return days[(date || new Date()).getDay()]
}

function relativeTime(timestamp) {
  var value = Number(timestamp)
  if (!value) return ""
  var delta = Math.max(0, Date.now() - value)
  var minutes = Math.floor(delta / 60000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 7) return days + "d ago"
  return Math.floor(days / 7) + "w ago"
}

function matchesFilter(idea, filterText) {
  var query = String(filterText || "").toLowerCase()
  if (!query) return true
  var name = ideaName(idea).toLowerCase()
  var body = String(idea && idea.body || "").toLowerCase()
  return name.indexOf(query) !== -1 || body.indexOf(query) !== -1
}

function filterIdeas(ideas, filterText) {
  var rows = ideas || []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    if (matchesFilter(rows[i], filterText)) out.push(rows[i])
  }
  return out
}

function clampIndex(index, count) {
  if (count <= 0) return 0
  return Math.max(0, Math.min(count - 1, index))
}

function authorName(entity) {
  if (!entity || !entity.author) return "Someone"
  return entity.author.name || entity.author.username || "Someone"
}

function titleValid(value) {
  var text = String(value || "")
  return text.length >= 4 && text.length <= 80
}

function sortLabel(mode) {
  if (mode === "new") return "New"
  if (mode === "top") return "Top"
  return "Hot"
}

function voteLabel(idea) {
  var count = idea && idea.voteCount ? idea.voteCount : 0
  return (idea && idea.myVote ? "Voted  " : "Upvote  ") + count
}

if (typeof module !== "undefined") {
  module.exports = {
    ideaName: ideaName,
    excerpt: excerpt,
    weekdayLabel: weekdayLabel,
    relativeTime: relativeTime,
    matchesFilter: matchesFilter,
    filterIdeas: filterIdeas,
    clampIndex: clampIndex,
    authorName: authorName,
    titleValid: titleValid,
    sortLabel: sortLabel,
    voteLabel: voteLabel
  }
}
