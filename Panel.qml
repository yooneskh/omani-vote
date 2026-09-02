import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Api.js" as Api

Panel {
  id: root
  moduleName: "yooneskh.omani-vote"
  ipcTarget: "yooneskh.omani-vote"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string apiBase: "https://khoshghadam.com"
  property string token: ""
  property var user: null
  readonly property bool signedIn: !!token && !!user

  property string screen: "today"
  property string previousScreen: "today"
  property var pendingAction: null

  property var featured: null
  property var ideas: []
  property var idea: null
  property string sortMode: "hot"
  property string filterText: ""
  readonly property var visibleIdeas: Model.filterIdeas(ideas, filterText)
  readonly property var sortModes: ["hot", "new", "top"]

  property string composeTitle: ""
  property string composeBody: ""

  property string loginUsername: ""
  property string loginPassword: ""
  property string registerName: ""
  property string registerUsername: ""
  property string registerPassword: ""
  property string captchaId: ""
  property string captchaImage: ""
  property string captchaCode: ""

  property string errorText: ""
  property bool busy: false
  property string requestKind: ""
  property int requestGen: 0
  property int activeGen: 0
  property var pendingRequest: null
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property string label: featured ? ("✦ " + featured.voteCount) : "✦"
  readonly property string tooltipText: featured ? (Model.ideaName(featured) || "Omani Vote") : "Omani Vote"
  readonly property bool formFocused: titleField.activeFocus || bodyField.activeFocus
    || loginUserField.activeFocus || loginPassField.activeFocus || loginCaptchaField.activeFocus
    || registerNameField.activeFocus || registerUserField.activeFocus || registerPassField.activeFocus
    || registerCaptchaField.activeFocus || commentField.activeFocus

  readonly property int todayActionCount: featured ? 5 : 3
  readonly property string screenLabel: root.screen === "today" ? "Featured"
    : root.screen === "browse" ? "Browse"
    : root.screen === "detail" ? "Idea"
    : root.screen === "submit" ? "Submit"
    : root.screen === "register" ? "Register"
    : "Sign in"

  function open() {
    root.screen = "today"
    root.errorText = ""
    root.controller.show()
    if (root.signedIn && !root.user) root.requestIdentity()
    else root.refreshSession()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function pluginFile(name) {
    return String(Qt.resolvedUrl(name)).replace(/^file:\/\//, "")
  }

  function saveState() {
    if (stateWriteProc.running) stateWriteProc.running = false
    stateWriteProc.stdinEnabled = true
    stateWriteProc.payload = Api.serializeState({
      apiBase: root.apiBase,
      token: root.token,
      user: root.user
    })
    stateWriteProc.command = ["/usr/bin/python3", pluginFile("secure-write.py"), stateFile.path]
    stateWriteProc.running = true
  }

  function applyState(raw) {
    var next = Api.parseState(raw)
    var sessionChanged = next.token !== root.token || next.apiBase !== root.apiBase
    root.apiBase = next.apiBase
    root.token = next.token
    root.user = next.user
    if (sessionChanged) root.refreshSession()
  }

  function go(nextScreen) {
    root.previousScreen = root.screen
    root.screen = nextScreen
    root.errorText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (nextScreen === "browse") root.refreshIdeas()
    if (nextScreen === "login" || nextScreen === "register") root.requestCaptcha()
  }

  function back() {
    if (root.screen === "browse" && root.filterText) {
      root.filterText = ""
      return
    }
    if (root.screen === "today") {
      root.close()
      return
    }
    if (root.screen === "register") {
      root.go("login")
      return
    }
    if (root.screen === "login" || root.screen === "submit" || root.screen === "browse") {
      root.screen = "today"
      root.errorText = ""
      root.selectedIndex = 0
      return
    }
    if (root.screen === "detail") {
      root.screen = root.previousScreen === "browse" ? "browse" : "today"
      root.errorText = ""
      root.selectedIndex = 0
    }
  }

  function requireAuth(action) {
    if (root.signedIn) return false
    root.pendingAction = action
    root.go("login")
    return true
  }

  function finishPending() {
    var action = root.pendingAction
    root.pendingAction = null
    if (!action) return
    if (action.type === "vote") root.voteIdea(action.ideaId)
    else if (action.type === "comment") {
      root.openIdea(action.ideaId)
      commentField.text = action.body || ""
      if (action.body) root.submitComment()
    } else if (action.type === "submit") {
      root.go("submit")
      if (Model.titleValid(root.composeTitle)) root.submitIdea()
    }
  }

  function signOut() {
    root.token = ""
    root.user = null
    root.saveState()
    if (root.featured) root.featured = Object.assign({}, root.featured, { myVote: false })
  }

  function request(kind, spec) {
    var config = Api.curlConfig(spec)
    if (!config) {
      root.errorText = "Could not build a safe request."
      return
    }
    root.requestGen += 1
    root.pendingRequest = { kind: kind, config: config, gen: root.requestGen }
    root.busy = true
    root.errorText = ""
    if (requestProc.running) {
      requestProc.running = false
      return
    }
    root.startPendingRequest()
  }

  function startPendingRequest() {
    var job = root.pendingRequest
    if (!job || job.gen !== root.requestGen) return
    root.pendingRequest = null
    root.activeGen = job.gen
    root.requestKind = job.kind
    requestProc.stdinEnabled = true
    requestProc.payload = job.config
    requestProc.command = Api.curlCommand()
    requestProc.running = true
  }

  function apiUrl(path, query) {
    return Api.joinUrl(root.apiBase, path, query)
  }

  function refreshFeatured() {
    root.request("featured", {
      url: apiUrl("/api/omani/featured"),
      token: root.token
    })
  }

  function refreshSession() {
    if (root.screen === "detail" && root.idea && root.idea._id) root.openIdea(root.idea._id)
    else if (root.screen === "browse") root.refreshIdeas()
    else root.refreshFeatured()
  }

  function refreshIdeas() {
    root.request("ideas", {
      url: apiUrl("/api/omani/ideas", {
        sort: Api.safeSort(root.sortMode),
        limit: 40
      }),
      token: root.token
    })
  }

  function openIdea(ideaId) {
    var path = Api.ideaPath(ideaId, "")
    if (!path) return
    root.request("idea", {
      url: apiUrl(path),
      token: root.token
    })
  }

  function voteIdea(ideaId) {
    var path = Api.ideaPath(ideaId, "/vote")
    if (!path) return
    if (root.requireAuth({ type: "vote", ideaId: ideaId })) return
    root.request("vote", {
      method: "POST",
      url: apiUrl(path),
      token: root.token
    })
  }

  function submitComment() {
    if (!root.idea) return
    var body = commentField.text
    if (!body) return
    var path = Api.ideaPath(root.idea._id, "/comments")
    if (!path) return
    if (root.requireAuth({ type: "comment", ideaId: root.idea._id, body: body })) return
    root.request("comment", {
      method: "POST",
      url: apiUrl(path),
      token: root.token,
      body: { body: body }
    })
  }

  function submitIdea() {
    if (!Model.titleValid(root.composeTitle)) {
      root.errorText = "Title needs 4 to 80 characters."
      return
    }
    if (root.requireAuth({ type: "submit" })) return
    var payload = { name: root.composeTitle }
    if (root.composeBody) payload.body = root.composeBody
    root.request("submit", {
      method: "POST",
      url: apiUrl("/api/omani/ideas"),
      token: root.token,
      body: payload
    })
  }

  function requestCaptcha() {
    root.captchaCode = ""
    loginCaptchaField.text = ""
    registerCaptchaField.text = ""
    root.request("captcha", {
      url: apiUrl("/api/authentication/captcha")
    })
  }

  function requestIdentity() {
    if (!root.token) return
    root.request("identity", {
      url: apiUrl("/api/authentication/identity"),
      token: root.token
    })
  }

  function submitLogin() {
    if (!root.loginUsername || !root.loginPassword || !root.captchaId || !root.captchaCode) {
      root.errorText = "Fill in username, password, and captcha."
      return
    }
    root.request("login", {
      method: "POST",
      url: apiUrl("/api/authentication/login"),
      headers: {
        "x-captcha-id": root.captchaId,
        "x-captcha-code": root.captchaCode
      },
      body: {
        username: root.loginUsername,
        password: root.loginPassword
      }
    })
  }

  function submitRegister() {
    if (!root.registerName || !root.registerUsername || !root.registerPassword || !root.captchaId || !root.captchaCode) {
      root.errorText = "Fill in name, username, password, and captcha."
      return
    }
    root.request("register", {
      method: "POST",
      url: apiUrl("/api/authentication/register"),
      headers: {
        "x-captcha-id": root.captchaId,
        "x-captcha-code": root.captchaCode
      },
      body: {
        name: root.registerName,
        username: root.registerUsername,
        password: root.registerPassword
      }
    })
  }

  function applyIdea(next) {
    var idea = Api.parseIdea(next)
    if (!idea) return
    if (root.featured && root.featured._id === idea._id) root.featured = idea
    var rows = root.ideas.slice()
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]._id === idea._id) {
        rows[i] = idea
        break
      }
    }
    root.ideas = rows
    if (root.idea && root.idea._id === idea._id)
      root.idea = Object.assign({}, root.idea, idea)
  }

  function handleResponse(raw) {
    if (root.activeGen !== root.requestGen) return
    var result = Api.parseCurl(raw)
    var kind = root.requestKind
    root.busy = false
    root.requestKind = ""

    if (!result.ok) {
      if (result.status === 401 && kind !== "login" && kind !== "register") {
        root.signOut()
        if (kind === "featured") root.refreshFeatured()
        else if (kind === "ideas") root.refreshIdeas()
        else if (kind === "idea" && root.idea) root.openIdea(root.idea._id)
        return
      }
      if (kind === "login" || kind === "register") {
        root.errorText = kind === "register" && result.status === 400
          ? "That username is taken."
          : "Invalid username, password, or captcha."
        root.requestCaptcha()
        return
      }
      if (kind === "identity" && result.status === 401) {
        root.signOut()
        return
      }
      root.errorText = result.error || "Something went wrong."
      return
    }

    if (kind === "featured") root.featured = Api.parseFeatured(result.data)
    else if (kind === "ideas") {
      root.ideas = Api.parseIdeaList(result.data)
      root.selectedIndex = Model.clampIndex(root.selectedIndex, root.visibleIdeas.length)
    } else if (kind === "idea") {
      var opened = Api.parseIdea(result.data)
      if (!opened) {
        root.errorText = "That idea could not be shown."
        return
      }
      root.idea = opened
      root.screen = "detail"
      root.selectedIndex = 0
      commentField.text = ""
    } else if (kind === "vote") root.applyIdea(result.data)
    else if (kind === "comment") {
      var comment = Api.parseComment(result.data)
      if (root.idea && comment) {
        var comments = (root.idea.comments || []).slice()
        if (comments.length >= 100) comments = comments.slice(comments.length - 99)
        comments.push(comment)
        root.idea = Object.assign({}, root.idea, {
          comments: comments,
          commentCount: (root.idea.commentCount || 0) + 1
        })
        if (root.featured && root.featured._id === root.idea._id)
          root.featured = Object.assign({}, root.featured, { commentCount: root.idea.commentCount })
      }
      commentField.text = ""
    } else if (kind === "submit") {
      var created = Api.parseIdea(result.data)
      if (!created) {
        root.errorText = "The idea was saved, but could not be shown."
        return
      }
      root.composeTitle = ""
      root.composeBody = ""
      titleField.text = ""
      bodyField.text = ""
      root.idea = Object.assign({}, created, { comments: [] })
      root.screen = "detail"
    } else if (kind === "captcha") {
      var captcha = Api.parseCaptcha(result.data)
      root.captchaId = captcha._id
      root.captchaImage = captcha.image
    } else if (kind === "login" || kind === "register") {
      var session = Api.parseSession(result.data)
      if (!session.token) {
        root.errorText = "Sign-in did not return a valid session."
        root.requestCaptcha()
        return
      }
      root.token = session.token
      root.saveState()
      root.requestIdentity()
    } else if (kind === "identity") {
      var user = Api.parseUser(result.data)
      if (!user) {
        root.signOut()
        return
      }
      root.user = user
      root.saveState()
      if (root.screen === "login" || root.screen === "register") {
        root.screen = "today"
        if (root.pendingAction) root.finishPending()
        else root.refreshFeatured()
      } else {
        root.refreshSession()
      }
    }
  }

  function moveCursor(dx, dy) {
    root.cursorActive = true
    if (root.screen === "today") {
      root.selectedIndex = Model.clampIndex(root.selectedIndex + dy + dx, root.todayActionCount)
      return
    }
    if (root.screen === "browse") {
      if (dx !== 0) {
        root.cycleSort(dx)
        return
      }
      root.selectedIndex = Model.clampIndex(root.selectedIndex + dy, root.visibleIdeas.length)
    }
    if (root.screen === "detail" && dy !== 0) commentField.forceActiveFocus()
  }

  function cycleSort(delta) {
    var index = root.sortModes.indexOf(root.sortMode)
    if (index < 0) index = 0
    root.sortMode = root.sortModes[(index + delta + root.sortModes.length) % root.sortModes.length]
    root.refreshIdeas()
  }

  function activateCursor() {
    if (root.screen === "today") root.activateToday()
    else if (root.screen === "browse") {
      var row = root.visibleIdeas[root.selectedIndex]
      if (row) root.openIdea(row._id)
    } else if (root.screen === "submit") root.submitIdea()
    else if (root.screen === "login") root.submitLogin()
    else if (root.screen === "register") root.submitRegister()
    else if (root.screen === "detail") commentField.forceActiveFocus()
  }

  function activateToday() {
    if (!root.featured) {
      if (root.selectedIndex === 0) root.go("submit")
      else if (root.selectedIndex === 1) root.go("browse")
      else root.signedIn ? root.signOut() : root.go("login")
      return
    }
    if (root.selectedIndex === 0) root.voteIdea(root.featured._id)
    else if (root.selectedIndex === 1) root.openIdea(root.featured._id)
    else if (root.selectedIndex === 2) root.go("browse")
    else if (root.selectedIndex === 3) root.go("submit")
    else root.signedIn ? root.signOut() : root.go("login")
  }

  function handleTextKey(text) {
    if (root.screen === "browse") {
      if (text === "v") {
        var row = root.visibleIdeas[root.selectedIndex]
        if (row) root.voteIdea(row._id)
        return
      }
      if (text === "n") {
        root.go("submit")
        return
      }
      if (text === "/") {
        root.filterText = ""
        return
      }
      if (text && text.length === 1 && text.charCodeAt(0) >= 32)
        root.filterText += text
      return
    }
    if (root.screen === "today" && text === "n") root.go("submit")
  }

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/yooneskh.omani-vote.json"
    watchChanges: true
    onLoaded: root.applyState(text())
    onLoadFailed: root.saveState()
  }

  Process {
    id: requestProc
    property string payload: ""
    stdinEnabled: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.activeGen !== root.requestGen) return
        root.handleResponse(this.text)
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      write(payload)
      payload = ""
      stdinEnabled = false
    }
    onExited: {
      if (root.pendingRequest && root.pendingRequest.gen === root.requestGen)
        root.startPendingRequest()
    }
  }

  Process {
    id: stateWriteProc
    property string payload: ""
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.errorText = "Could not save the session securely."
    }
  }

  Timer {
    interval: 5 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refreshFeatured()
  }

  Component.onCompleted: {
    if (root.token) root.refreshSession()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.formFocused
      onCloseRequested: root.back()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onTextKey: function(text) { root.handleTextKey(text) }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroller.width
          spacing: Style.space(14)

          Item {
            width: parent.width
            implicitHeight: headerLeft.implicitHeight

            Row {
              id: headerLeft
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "OMANI VOTE"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.6
              }

              Text {
                textFormat: Text.PlainText
                text: "·"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                text: Model.weekdayLabel(new Date()).toUpperCase()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.screenLabel.toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.6
            }
          }

          BorderSurface {
            visible: root.errorText !== ""
            width: parent.width
            implicitHeight: errorLabel.implicitHeight + Style.space(14)
            color: Style.hoverFillFor(root.foreground, Color.accent)
            radius: Style.cornerRadius
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

            Text {
              id: errorLabel
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              textFormat: Text.PlainText
              text: root.errorText
              color: root.foreground
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          // ---- Today
          Column {
            visible: root.screen === "today"
            width: parent.width
            spacing: Style.space(14)

            Text {
              visible: !root.featured
              width: parent.width
              topPadding: Style.space(28)
              bottomPadding: Style.space(12)
              textFormat: Text.PlainText
              text: "The board is quiet.\nSubmit the first idea."
              color: root.dim
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Column {
              visible: !!root.featured
              width: parent.width
              spacing: Style.space(14)

              Item {
                width: parent.width
                implicitHeight: Math.max(voteBlock.implicitHeight, featuredCopy.implicitHeight, featuredVote.implicitHeight)

                Column {
                  id: voteBlock
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(88)
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: root.featured ? String(root.featured.voteCount || 0) : "0"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 48
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: "VOTES"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.4
                  }
                }

                Column {
                  id: featuredCopy
                  anchors.left: voteBlock.right
                  anchors.leftMargin: Style.space(16)
                  anchors.right: featuredVote.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: "TODAY'S IDEA"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.4
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: Model.ideaName(root.featured)
                    color: root.foreground
                    wrapMode: Text.WordWrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: root.featured
                      ? (Model.authorName(root.featured) + "  ·  " + Model.relativeTime(root.featured.createdAt)).toUpperCase()
                      : ""
                    color: root.dim
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.0
                  }
                }

                Button {
                  id: featuredVote
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.featured && root.featured.myVote ? "Voted" : "Upvote"
                  selected: !!(root.featured && root.featured.myVote)
                  hasCursor: root.cursorActive && root.selectedIndex === 0
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: if (root.featured) root.voteIdea(root.featured._id)
                }
              }

              Text {
                visible: !!(root.featured && root.featured.body)
                width: parent.width
                textFormat: Text.PlainText
                text: root.featured ? Model.excerpt(root.featured.body, 180) : ""
                color: root.dim
                wrapMode: Text.WordWrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              CursorSurface {
                width: parent.width
                implicitHeight: commentRow.implicitHeight + Style.spacing.rowPaddingX
                hasCursor: root.cursorActive && root.selectedIndex === 1
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.cursorActive = true
                    root.selectedIndex = 1
                  }
                  onClicked: if (root.featured) root.openIdea(root.featured._id)
                }

                Text {
                  id: commentRow
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Comments"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.featured ? String(root.featured.commentCount || 0) : "0"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Browse"
                bordered: true
                hasCursor: root.cursorActive && root.selectedIndex === (root.featured ? 2 : 1)
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.go("browse")
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Submit"
                bordered: true
                hasCursor: root.cursorActive && root.selectedIndex === (root.featured ? 3 : 0)
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.go("submit")
              }
            }

            CursorSurface {
              width: parent.width
              implicitHeight: authCopy.implicitHeight + Style.spacing.rowPaddingX
              hasCursor: root.cursorActive && root.selectedIndex === (root.featured ? 4 : 2)
              foreground: root.foreground

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  root.cursorActive = true
                  root.selectedIndex = root.featured ? 4 : 2
                }
                onClicked: root.signedIn ? root.signOut() : root.go("login")
              }

              Column {
                id: authCopy
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.signedIn
                    ? ("Signed in as  " + (root.user.name || root.user.username))
                    : "Sign in"
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.signedIn ? "Sign out" : "Vote, comment, and submit ideas"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // ---- Browse
          Column {
            visible: root.screen === "browse"
            width: parent.width
            spacing: Style.space(12)

            Row {
              id: sortRow
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.sortModes

                Button {
                  required property string modelData
                  width: (sortRow.width - sortRow.spacing * 2) / 3
                  text: Model.sortLabel(modelData)
                  selected: root.sortMode === modelData
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: {
                    root.sortMode = modelData
                    root.refreshIdeas()
                  }
                }
              }
            }

            Text {
              visible: root.filterText !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: "Filter  ·  " + root.filterText
              color: root.dim
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 0.4
            }

            Text {
              visible: root.visibleIdeas.length === 0
              width: parent.width
              topPadding: Style.space(24)
              textFormat: Text.PlainText
              text: root.filterText ? "No matches for that filter." : "Nothing here yet.\nBe the first."
              color: root.dim
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.visibleIdeas

              CursorSurface {
                required property var modelData
                required property int index
                width: contentColumn.width
                implicitHeight: browseCopy.implicitHeight + Style.spacing.rowPaddingX
                hasCursor: root.cursorActive && root.screen === "browse" && root.selectedIndex === index
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.cursorActive = true
                    root.selectedIndex = index
                  }
                  onClicked: root.openIdea(modelData._id)
                }

                Column {
                  id: browseCopy
                  anchors.left: parent.left
                  anchors.right: voteMark.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: Model.ideaName(modelData)
                    color: root.foreground
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: Model.authorName(modelData) + "  ·  " + Model.relativeTime(modelData.createdAt)
                      + "  ·  " + (modelData.commentCount || 0) + " comments"
                    color: root.dim
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  id: voteMark
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(modelData.voteCount || 0)
                  color: modelData.myVote ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }
            }
          }

          // ---- Detail
          Column {
            visible: root.screen === "detail" && !!root.idea
            width: parent.width
            spacing: Style.space(14)

            Button {
              text: "Back"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.back()
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(detailVotes.implicitHeight, detailCopy.implicitHeight, detailVote.implicitHeight)

              Column {
                id: detailVotes
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(88)
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.idea ? String(root.idea.voteCount || 0) : "0"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 48
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: "VOTES"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.4
                }
              }

              Column {
                id: detailCopy
                anchors.left: detailVotes.right
                anchors.leftMargin: Style.space(16)
                anchors.right: detailVote.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: Model.ideaName(root.idea)
                  color: root.foreground
                  wrapMode: Text.WordWrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.idea
                    ? (Model.authorName(root.idea) + "  ·  " + Model.relativeTime(root.idea.createdAt)).toUpperCase()
                    : ""
                  color: root.dim
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.0
                }
              }

              Button {
                id: detailVote
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.idea && root.idea.myVote ? "Voted" : "Upvote"
                selected: !!(root.idea && root.idea.myVote)
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: if (root.idea) root.voteIdea(root.idea._id)
              }
            }

            Text {
              visible: !!(root.idea && root.idea.body)
              width: parent.width
              textFormat: Text.PlainText
              text: root.idea ? root.idea.body : ""
              color: root.dim
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            PanelSeparator { foreground: root.foreground }

            Item {
              width: parent.width
              implicitHeight: commentsHeader.implicitHeight

              PanelSectionHeader {
                id: commentsHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "COMMENTS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.idea ? String(root.idea.commentCount || 0) : "0"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }
            }

            Text {
              visible: !(root.idea && root.idea.comments && root.idea.comments.length)
              width: parent.width
              textFormat: Text.PlainText
              text: "No comments yet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.idea && root.idea.comments ? root.idea.comments : []

              Column {
                required property var modelData
                required property int index
                width: contentColumn.width
                spacing: Style.space(6)

                PanelSeparator {
                  visible: index > 0
                  foreground: root.foreground
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: (Model.authorName(modelData) + "  ·  " + Model.relativeTime(modelData.createdAt)).toUpperCase()
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.0
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.body
                  color: root.foreground
                  wrapMode: Text.WordWrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            TextField {
              id: commentField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Write a comment"
              onAccepted: root.submitComment()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            Button {
              width: parent.width
              text: "Post comment"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.submitComment()
            }
          }

          // ---- Submit
          Column {
            visible: root.screen === "submit"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "Title"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: titleField
              width: parent.width
              foreground: root.foreground
              placeholderText: "A short title"
              onTextChanged: root.composeTitle = text
              onAccepted: bodyField.forceActiveFocus()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            PanelSectionHeader {
              text: "DETAILS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: bodyField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Optional"
              onTextChanged: root.composeBody = text
              onAccepted: root.submitIdea()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            Button {
              width: parent.width
              text: "Submit idea"
              bordered: true
              hasCursor: root.cursorActive && !root.formFocused
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.submitIdea()
            }
          }

          // ---- Login
          Column {
            visible: root.screen === "login"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Use your Omani Vote account."
              color: root.dim
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: loginUserField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Username"
              onTextChanged: root.loginUsername = text
              onAccepted: loginPassField.forceActiveFocus()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            TextField {
              id: loginPassField
              width: parent.width
              foreground: root.foreground
              password: true
              placeholderText: "Password"
              onTextChanged: root.loginPassword = text
              onAccepted: loginCaptchaField.forceActiveFocus()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            CaptchaBlock {
              image: root.captchaImage
              onRefresh: root.requestCaptcha()
            }

            TextField {
              id: loginCaptchaField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Captcha"
              onTextChanged: root.captchaCode = text
              onAccepted: root.submitLogin()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            Button {
              width: parent.width
              text: "Sign in"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.submitLogin()
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Need an account?  Register"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.go("register")
              }
            }
          }

          // ---- Register
          Column {
            visible: root.screen === "register"
            width: parent.width
            spacing: Style.space(10)

            TextField {
              id: registerNameField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Name"
              onTextChanged: root.registerName = text
              onAccepted: registerUserField.forceActiveFocus()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            TextField {
              id: registerUserField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Username"
              onTextChanged: root.registerUsername = text
              onAccepted: registerPassField.forceActiveFocus()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            TextField {
              id: registerPassField
              width: parent.width
              foreground: root.foreground
              password: true
              placeholderText: "Password"
              onTextChanged: root.registerPassword = text
              onAccepted: registerCaptchaField.forceActiveFocus()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            CaptchaBlock {
              image: root.captchaImage
              onRefresh: root.requestCaptcha()
            }

            TextField {
              id: registerCaptchaField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Captcha"
              onTextChanged: root.captchaCode = text
              onAccepted: root.submitRegister()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.back()
                }
              }
            }

            Button {
              width: parent.width
              text: "Register"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.submitRegister()
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Already have an account?  Sign in"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.go("login")
              }
            }
          }
        }
      }
    }
  }

  component CaptchaBlock: BorderSurface {
    id: captcha
    property string image: ""
    signal refresh()

    width: parent ? parent.width : Style.space(200)
    implicitHeight: Style.space(64)
    color: Style.controlFill(false, false, root.foreground, Color.accent)
    radius: Style.cornerRadius
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

    Image {
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(12), Style.space(160))
      height: Style.space(48)
      fillMode: Image.PreserveAspectFit
      cache: false
      asynchronous: true
      sourceSize.width: Style.space(160)
      sourceSize.height: Style.space(48)
      source: captcha.image ? ("data:image/png;base64," + captcha.image) : ""
    }

    Text {
      visible: !captcha.image
      anchors.centerIn: parent
      text: "Tap to refresh captcha"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: captcha.refresh()
    }
  }
}
