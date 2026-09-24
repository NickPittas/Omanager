import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "npittas.omanager"
  ipcTarget: "npittas.omanager"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var apps: []
  property var windows: []
  property string selectedAppId: ""
  property string appQuery: ""
  property string windowQuery: ""
  property string draftMode: "default"
  property bool draftCentered: false
  property bool draftMaximized: false
  property bool draftFullscreen: false
  property bool draftPinned: false
  property string draftWidth: ""
  property string draftHeight: ""
  property string draftX: ""
  property string draftY: ""
  property string draftWorkspace: ""
  property bool draftWorkspaceSilent: true
  property string draftClass: ""
  property string draftInitialTitle: ""
  property string pickedAddress: ""
  property string statusMessage: ""
  property string backendPath: resolvedPath("omanager.py")
  property bool appsLoading: false
  property bool windowsLoading: false
  property bool saving: false
  property bool pickingWindow: false
  property int selectedAppIndex: 0
  property int selectedWindowIndex: 0

  readonly property color foreground: Color.popups.text
  readonly property color dim: Color.muted
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property var visibleApps: {
    var query = appQuery.trim().toLowerCase()
    if (!query) return apps
    return apps.filter(function(app) {
      return String(app.name).toLowerCase().indexOf(query) >= 0
        || String(app.id).toLowerCase().indexOf(query) >= 0
    })
  }
  readonly property var visibleWindows: {
    var query = windowQuery.trim().toLowerCase()
    if (!query) return windows
    return windows.filter(function(window) {
      return [window.title, window.class, window.initial_title, window.workspace]
        .join(" ").toLowerCase().indexOf(query) >= 0
    })
  }
  readonly property var selectedApp: appForId(selectedAppId)
  readonly property bool terminalTarget: selectedApp && selectedApp.uses_terminal && isTerminalClass(draftClass)
  readonly property bool targetAvailable: !!pickedAddress
    || (!!selectedApp && !!selectedApp.wm_class && draftClass === selectedApp.wm_class)
    || (!!selectedApp && selectedApp.setting && selectedApp.setting.class === draftClass && !/\s/.test(draftClass))
    || windows.some(function(window) {
      return window.class === draftClass && (!draftInitialTitle || window.initial_title === draftInitialTitle)
    })
  readonly property bool hasRuleOptions: draftMode !== "default" || draftMaximized || draftFullscreen || draftPinned
    || draftWidth.trim() !== "" || draftHeight.trim() !== "" || draftX.trim() !== "" || draftY.trim() !== "" || draftWorkspace.trim() !== ""
  readonly property bool sizeValid: validPair(draftWidth, draftHeight, 1, 16384)
  readonly property bool positionValid: validPair(draftX, draftY, 0, 32767)
  readonly property bool workspaceValid: draftWorkspace.trim() === ""
    || /^(?:[1-9][0-9]{0,3}|[A-Za-z][A-Za-z0-9_.:-]{0,63})$/.test(draftWorkspace.trim())
  readonly property bool canSave: !!selectedApp && !saving && sizeValid && positionValid && workspaceValid
    && (!hasRuleOptions || (!!draftClass && targetAvailable && !terminalTarget))

  function resolvedPath(relativePath) {
    var value = String(Qt.resolvedUrl(relativePath))
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.substring(7))
    return value
  }

  function appForId(id) {
    for (var i = 0; i < apps.length; i++) if (apps[i].id === id) return apps[i]
    return null
  }

  function validPair(first, second, minimum, maximum) {
    var a = String(first).trim()
    var b = String(second).trim()
    if (!a && !b) return true
    if (!a || !b || !/^\d+$/.test(a) || !/^\d+$/.test(b)) return false
    var x = Number(a)
    var y = Number(b)
    return x >= minimum && x <= maximum && y >= minimum && y <= maximum
  }

  function modeLabel(app) {
    var setting = app && app.setting ? app.setting : ({})
    var floating = setting.mode === "floating" || setting.mode === "floating-center"
    if ((floating || setting.maximize || setting.fullscreen || setting.pin || setting.workspace || setting.size || setting.move)
        && (!setting.class || /\s/.test(String(setting.class)) || (app.uses_terminal && isTerminalClass(setting.class))))
      return "PICK TARGET"
    var labels = [floating ? (setting.mode === "floating-center" ? "FLOAT · CENTERED" : "FLOATING") : (setting.mode === "default" && (setting.maximize || setting.fullscreen || setting.workspace) ? "TILED" : "DEFAULT LAYOUT")]
    if (setting.maximize) labels.push("MAXIMIZED")
    if (setting.fullscreen) labels.push("FULLSCREEN")
    if (setting.pin) labels.push("PINNED")
    if (setting.size) labels.push(setting.size[0] + "×" + setting.size[1])
    if (setting.move) labels.push("CUSTOM POSITION")
    if (setting.workspace) labels.push("WS " + setting.workspace)
    return labels.join(" · ")
  }

  function ensureVisibleApp() {
    for (var i = 0; i < visibleApps.length; i++) {
      if (visibleApps[i].id === selectedAppId) {
        selectedAppIndex = i
        return
      }
    }
    if (visibleApps.length) {
      selectedAppIndex = 0
      selectApp(visibleApps[0])
    }
  }

  function positionAppsAtSelection() {
    Qt.callLater(function() {
      if (visibleApps.length) appListView.positionViewAtIndex(selectedAppIndex, ListView.Beginning)
    })
  }

  function selectFirstMatchingApp(query) {
    var value = String(query || "").trim().toLowerCase()
    for (var i = 0; i < apps.length; i++) {
      var app = apps[i]
      if (!value || String(app.name).toLowerCase().indexOf(value) >= 0
          || String(app.id).toLowerCase().indexOf(value) >= 0) {
        selectedAppIndex = 0
        selectApp(app)
        return
      }
    }
  }

  function isTerminalClass(className) {
    var value = String(className || "").toLowerCase()
    return ["com.mitchellh.ghostty", "alacritty", "kitty", "foot", "wezterm", "konsole", "xterm"].indexOf(value) >= 0
      || value.indexOf("terminal") >= 0
  }

  function run(process, args) {
    if (process.running) return false
    process.command = ["python3", backendPath].concat(args)
    process.running = true
    return true
  }

  function refreshApps() {
    if (!run(appsProcess, ["apps"])) return
    appsLoading = true
  }

  function refreshWindows() {
    if (!run(windowsProcess, ["windows"])) return
    windowsLoading = true
  }

  function acceptApps(raw) {
    appsLoading = false
    try {
      var result = JSON.parse(String(raw || ""))
      if (!result.ok) throw new Error(result.error || "Could not read installed applications")
      apps = result.apps || []
      if (!appForId(selectedAppId) && apps.length) selectApp(apps[0])
    } catch (error) {
      statusMessage = String(error)
    }
  }

  function acceptWindows(raw) {
    windowsLoading = false
    try {
      var result = JSON.parse(String(raw || ""))
      if (!result.ok) throw new Error(result.error || "Could not read open windows")
      windows = result.windows || []
    } catch (error) {
      statusMessage = String(error)
    }
  }

  function selectApp(app) {
    if (!app) return
    selectedAppId = app.id
    var setting = app.setting || ({})
    draftMode = setting.mode === "floating" || setting.mode === "floating-center" ? "floating" : "default"
    draftCentered = setting.mode === "floating-center"
    draftClass = setting.class || app.wm_class || ""
    draftInitialTitle = setting.initial_title || ""
    draftMaximized = setting.maximize === true
    draftFullscreen = setting.fullscreen === true
    draftPinned = setting.pin === true
    draftWidth = setting.size && setting.size.length === 2 ? String(setting.size[0]) : ""
    draftHeight = setting.size && setting.size.length === 2 ? String(setting.size[1]) : ""
    draftX = setting.move && setting.move.length === 2 ? String(setting.move[0]) : ""
    draftY = setting.move && setting.move.length === 2 ? String(setting.move[1]) : ""
    draftWorkspace = setting.workspace || ""
    draftWorkspaceSilent = setting.workspace_silent !== false
    pickedAddress = ""
    pickingWindow = false
    statusMessage = ""
    for (var i = 0; i < visibleApps.length; i++) if (visibleApps[i].id === app.id) selectedAppIndex = i
    Qt.callLater(function() { detailScroll.contentY = 0 })
  }

  function setMode(mode) {
    draftMode = mode
    if (mode === "default") {
      draftCentered = false
      draftPinned = false
      draftWidth = ""
      draftHeight = ""
      draftX = ""
      draftY = ""
    }
    statusMessage = ""
  }

  function requireFloating() {
    if (draftMode !== "floating") setMode("floating")
  }

  function openWindowPicker() {
    pickingWindow = true
    windowQuery = ""
    selectedWindowIndex = 0
    refreshWindows()
  }

  function chooseWindow(window) {
    if (!window) return
    draftClass = window.class
    draftInitialTitle = window.initial_title || ""
    pickedAddress = window.address
    pickingWindow = false
    statusMessage = terminalTarget
      ? "This is a terminal window, not a separate application window."
      : "Window selected. Apply to save this match."
  }

  function saveCurrent() {
    if (!selectedApp) return
    if (terminalTarget && hasRuleOptions) {
      statusMessage = "This selection would configure the terminal, not the app inside it."
      return
    }
    if (hasRuleOptions && (!draftClass || !targetAvailable)) {
      statusMessage = "Launch the app and pick its actual window before applying a rule."
      return
    }
    if (!sizeValid || !positionValid || !workspaceValid) {
      statusMessage = "Enter a complete, valid size, position, and workspace."
      return
    }
    var mode = draftMode === "default" ? "default" : (draftCentered ? "floating-center" : "floating")
    var payload = {
      id: selectedApp.id,
      mode: mode,
      class: hasRuleOptions ? (draftClass || selectedApp.wm_class) : "",
      initial_title: hasRuleOptions ? draftInitialTitle : "",
      maximize: draftMaximized,
      fullscreen: draftFullscreen,
      pin: draftPinned,
      size: draftWidth.trim() ? [Number(draftWidth), Number(draftHeight)] : null,
      move: draftX.trim() ? [Number(draftX), Number(draftY)] : null,
      workspace: draftWorkspace.trim(),
      workspace_silent: draftWorkspaceSilent
    }
    saving = true
    saveProcess.command = ["python3", backendPath, "save", JSON.stringify(payload)]
    saveProcess.running = true
  }

  function acceptSave(raw) {
    saving = false
    try {
      var result = JSON.parse(String(raw || ""))
      if (!result.ok) throw new Error(result.error || result.message || "Could not save the rule")
      statusMessage = "Saved. New windows will use this layout."
      refreshApps()
    } catch (error) {
      statusMessage = String(error)
    }
  }

  function appRow(index) {
    if (visibleApps.length === 0) return
    selectedAppIndex = Math.max(0, Math.min(visibleApps.length - 1, index))
    selectApp(visibleApps[selectedAppIndex])
  }

  function windowRow(index) {
    if (visibleWindows.length === 0) return
    selectedWindowIndex = Math.max(0, Math.min(visibleWindows.length - 1, index))
  }

  onVisibleAppsChanged: { ensureVisibleApp(); positionAppsAtSelection() }
  onOpenedChanged: if (opened) { refreshApps(); refreshWindows() }

  Process {
    id: appsProcess
    command: []
    running: false
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.acceptApps(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: function(text) { if (text.trim()) root.statusMessage = "Application scan failed." } }
    onExited: function(exitCode) { root.appsLoading = false }
  }

  Process {
    id: windowsProcess
    command: []
    running: false
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.acceptWindows(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: function(text) { if (text.trim()) root.statusMessage = "Window scan failed." } }
    onExited: function(exitCode) { root.windowsLoading = false }
  }

  Process {
    id: saveProcess
    command: []
    running: false
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.acceptSave(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: function(text) { if (text.trim()) root.statusMessage = "Save failed." } }
    onExited: function(exitCode) { root.saving = false }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖯"
    tooltipText: "Omanager · App window behavior"
    onPressed: function(_buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(1080), Style.space(1240))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: appSearch.activeFocus || windowSearch.activeFocus || workspaceField.activeFocus
        || widthField.activeFocus || heightField.activeFocus || xField.activeFocus || yField.activeFocus
      onMoveRequested: function(_dx, dy) {
        if (dy === 0) return
        if (root.pickingWindow) root.windowRow(root.selectedWindowIndex + dy)
        else root.appRow(root.selectedAppIndex + dy)
      }
      onActivateRequested: {
        if (root.pickingWindow && root.visibleWindows.length)
          root.chooseWindow(root.visibleWindows[root.selectedWindowIndex])
        else if (!root.pickingWindow && root.visibleApps.length)
          root.selectApp(root.visibleApps[root.selectedAppIndex])
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") { root.refreshApps(); root.refreshWindows() }
        else if (text === "/" && !root.pickingWindow) appSearch.forceActiveFocus()
        else if (text === "/" && root.pickingWindow) windowSearch.forceActiveFocus()
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scrollArea.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            foreground: root.foreground
            title: "Omanager"
            meta: "APPLICATION WINDOW SETTINGS"
            detail: root.apps.length ? root.apps.length + " APPS" : ""
            iconComponent: Component {
              Text {
                text: "󰖯"
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }
            }
          }

          Row {
            id: mainRow
            width: parent.width
            height: Style.space(610)
            spacing: Style.space(14)

            BorderSurface {
              id: appPane
              width: Style.space(350)
              height: parent.height
              color: Color.popups.background
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              Item {
                anchors.fill: parent
                anchors.margins: Style.space(12)

                TextField {
                  id: appSearch
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: Style.space(38)
                  placeholderText: "Search installed apps…"
                  text: root.appQuery
                  onTextChanged: {
                    root.appQuery = text
                    root.selectFirstMatchingApp(text)
                    root.positionAppsAtSelection()
                  }
                }

                Row {
                  id: appHeader
                  anchors.top: appSearch.bottom
                  anchors.topMargin: Style.space(8)
                  width: parent.width
                  height: Style.space(24)
                  Text {
                    width: parent.width - countLabel.implicitWidth - Style.space(8)
                    text: "INSTALLED APPLICATIONS"
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                  }
                  Text {
                    id: countLabel
                    text: root.visibleApps.length + " shown"
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                ListView {
                  id: appListView
                  anchors.top: appHeader.bottom
                  anchors.topMargin: Style.space(8)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(2)
                  clip: true
                  spacing: Style.space(4)
                  model: root.visibleApps
                  currentIndex: root.selectedAppIndex
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  delegate: CursorSurface {
                    required property var modelData
                    required property int index
                    width: appListView.width - Style.space(10)
                    height: Style.space(68)
                    foreground: root.foreground
                    accent: root.accent
                    current: modelData.id === root.selectedAppId
                    hasCursor: index === root.selectedAppIndex
                    fill: Style.hoverFillFor(root.foreground, root.accent)
                    currentFill: Style.selectedFillFor(root.foreground, root.accent)

                    Column {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: modelData.name
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: modelData.id === root.selectedAppId
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: modelData.id + "  ·  " + root.modeLabel(modelData)
                        color: root.dim
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.selectedAppIndex = index
                      onClicked: root.selectApp(modelData)
                    }
                  }
                }
                Text {
                  visible: root.visibleApps.length === 0
                  anchors.centerIn: appListView
                  text: "No installed apps match."
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }

            BorderSurface {
              id: detailPane
              width: parent.width - appPane.width - parent.spacing
              height: parent.height
              color: Color.popups.background
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              Flickable {
                id: detailScroll
                anchors.fill: parent
                anchors.margins: Style.space(20)
                clip: true
                contentWidth: width
                contentHeight: detailContent.implicitHeight
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                visible: !root.pickingWindow && !!root.selectedApp
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                  id: detailContent
                  width: detailScroll.width
                  spacing: Style.space(12)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.selectedApp ? root.selectedApp.name : "Choose an app"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  wrapMode: Text.WordWrap
                  maximumLineCount: 3
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.selectedApp ? root.selectedApp.id : ""
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                PanelSeparator { foreground: root.foreground }
                PanelSectionHeader { text: "Opening behavior"; foreground: root.foreground }

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Button {
                    text: "Normal layout"
                    selected: root.draftMode === "default"
                    bordered: true
                    onClicked: root.setMode("default")
                  }
                  Button {
                    text: "Floating"
                    selected: root.draftMode === "floating"
                    bordered: true
                    onClicked: root.setMode("floating")
                  }
                }

                Row {
                  width: parent.width
                  visible: root.draftMode === "floating"
                  spacing: Style.space(10)
                  ToggleSwitch {
                    checked: root.draftCentered
                    interactive: true
                    onToggled: root.draftCentered = !root.draftCentered
                  }
                  Text {
                    text: "Center the floating window"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                PanelSeparator { foreground: root.foreground }
                Row {
                  width: parent.width
                  height: Style.space(34)
                  PanelSectionHeader { text: "Window target"; foreground: root.foreground; anchors.verticalCenter: parent.verticalCenter }
                  Item { width: parent.width - pickButton.width - Style.space(180); height: 1 }
                  Button {
                    id: pickButton
                    text: "Pick running window"
                    bordered: true
                    onClicked: root.openWindowPicker()
                  }
                }

                BorderSurface {
                  width: parent.width
                  implicitHeight: matchInfo.implicitHeight + Style.space(18)
                  color: Style.normalFillFor(root.foreground, root.accent)
                  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
                  radius: Style.cornerRadius
                  Column {
                    id: matchInfo
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(10)
                    spacing: Style.space(4)
                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: root.draftClass ? "Class  ·  " + root.draftClass : "No window class selected"
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                    }
                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: root.draftInitialTitle ? "Opens as  ·  " + root.draftInitialTitle : "Initial title  ·  not set"
                      color: root.dim
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                  }
                }

                PanelSeparator { foreground: root.foreground }
                PanelSectionHeader { text: "Start state"; foreground: root.foreground }
                Row {
                  width: parent.width
                  spacing: Style.space(10)
                  ToggleSwitch {
                    checked: root.draftMaximized
                    interactive: true
                    onToggled: root.draftMaximized = !root.draftMaximized
                  }
                  Text {
                    text: "Start maximized"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
                Row {
                  width: parent.width
                  spacing: Style.space(10)
                  ToggleSwitch {
                    checked: root.draftFullscreen
                    interactive: true
                    onToggled: root.draftFullscreen = !root.draftFullscreen
                  }
                  Text {
                    text: "Start fullscreen"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                PanelSeparator { foreground: root.foreground }
                PanelSectionHeader { text: "Workspace"; foreground: root.foreground }
                TextField {
                  id: workspaceField
                  width: parent.width
                  height: Style.space(38)
                  placeholderText: "Workspace number or name, e.g. 3 or name:Design"
                  text: root.draftWorkspace
                  onTextChanged: { root.draftWorkspace = text; root.statusMessage = "" }
                }
                Text {
                  visible: !root.workspaceValid
                  width: parent.width
                  text: "Use a positive number or a simple name (letters, numbers, . _ : -)."
                  color: root.urgent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                Row {
                  width: parent.width
                  visible: root.draftWorkspace.trim() !== ""
                  spacing: Style.space(10)
                  ToggleSwitch {
                    checked: root.draftWorkspaceSilent
                    interactive: true
                    onToggled: root.draftWorkspaceSilent = !root.draftWorkspaceSilent
                  }
                  Text {
                    text: "Keep the current workspace active"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Column {
                  width: parent.width
                  visible: root.draftMode === "floating"
                  spacing: Style.space(8)
                  PanelSeparator { foreground: root.foreground }
                  PanelSectionHeader { text: "Floating options"; foreground: root.foreground }
                  Row {
                    width: parent.width
                    spacing: Style.space(10)
                    ToggleSwitch {
                      checked: root.draftPinned
                      interactive: true
                      onToggled: {
                        if (!root.draftPinned) root.requireFloating()
                        root.draftPinned = !root.draftPinned
                      }
                    }
                    Text {
                      text: "Pin across workspaces"
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                  Row {
                    width: parent.width
                    spacing: Style.space(8)
                    TextField {
                      id: widthField
                      width: (parent.width - Style.space(8)) / 2
                      height: Style.space(38)
                      placeholderText: "Width (px)"
                      validator: IntValidator { bottom: 1; top: 16384 }
                      text: root.draftWidth
                      onTextChanged: { root.draftWidth = text; root.statusMessage = "" }
                    }
                    TextField {
                      id: heightField
                      width: (parent.width - Style.space(8)) / 2
                      height: Style.space(38)
                      placeholderText: "Height (px)"
                      validator: IntValidator { bottom: 1; top: 16384 }
                      text: root.draftHeight
                      onTextChanged: { root.draftHeight = text; root.statusMessage = "" }
                    }
                  }
                  Row {
                    width: parent.width
                    spacing: Style.space(8)
                    TextField {
                      id: xField
                      width: (parent.width - Style.space(8)) / 2
                      height: Style.space(38)
                      placeholderText: "X position (px)"
                      validator: IntValidator { bottom: 0; top: 32767 }
                      text: root.draftX
                      onTextChanged: {
                        root.draftX = text
                        if (text.trim()) root.draftCentered = false
                        root.statusMessage = ""
                      }
                    }
                    TextField {
                      id: yField
                      width: (parent.width - Style.space(8)) / 2
                      height: Style.space(38)
                      placeholderText: "Y position (px)"
                      validator: IntValidator { bottom: 0; top: 32767 }
                      text: root.draftY
                      onTextChanged: {
                        root.draftY = text
                        if (text.trim()) root.draftCentered = false
                        root.statusMessage = ""
                      }
                    }
                  }
                  Text {
                    width: parent.width
                    text: "Size and position are monitor-local. Manual position overrides centering."
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    visible: !root.sizeValid || !root.positionValid
                    width: parent.width
                    text: "Enter width and height together, and X and Y together."
                    color: root.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }

                Text {
                  visible: !!root.selectedApp && root.selectedApp.uses_terminal
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "This launcher runs through a terminal. Picking that terminal would float the terminal window, not the app inside it. Choose a separate app window if one is open."
                  color: root.urgent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
                Text {
                  visible: root.draftMode === "floating" && !root.targetAvailable && !root.terminalTarget
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "This saved target is not verified against an app class or open window. Launch the app and pick its actual window to repair the rule."
                  color: root.urgent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Item { width: 1; height: Style.space(2) }
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Button {
                    text: root.saving ? "Applying…" : "Apply changes"
                    active: true
                    enabled: root.canSave
                    onClicked: root.saveCurrent()
                  }
                  Button {
                    text: "Refresh"
                    bordered: true
                    enabled: !root.appsLoading
                    onClicked: { root.refreshApps(); root.refreshWindows() }
                  }
                }
                Text {
                  visible: root.statusMessage !== ""
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.statusMessage
                  color: root.terminalTarget ? root.urgent : root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                }
              }

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(18)
                spacing: Style.space(10)
                visible: root.pickingWindow

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Button {
                    text: "← Back"
                    bordered: true
                    onClicked: root.pickingWindow = false
                  }
                  Text {
                    width: parent.width - Style.space(100)
                    text: "Choose the app's open window"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Select a real window. Omanager uses its class and initial title, so unrelated windows stay untouched."
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
                TextField {
                  id: windowSearch
                  width: parent.width
                  height: Style.space(38)
                  placeholderText: "Filter by title, class, or workspace…"
                  text: root.windowQuery
                  onTextChanged: { root.windowQuery = text; root.selectedWindowIndex = 0 }
                }
                Button {
                  text: root.windowsLoading ? "Refreshing windows…" : "Refresh open windows"
                  bordered: true
                  enabled: !root.windowsLoading
                  onClicked: root.refreshWindows()
                }
                ListView {
                  id: windowListView
                  width: parent.width
                  height: parent.height - windowSearch.height - Style.space(130)
                  clip: true
                  spacing: Style.space(6)
                  model: root.visibleWindows
                  currentIndex: root.selectedWindowIndex
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  delegate: CursorSurface {
                    required property var modelData
                    required property int index
                    width: windowListView.width - Style.space(8)
                    height: Style.space(84)
                    foreground: root.foreground
                    accent: root.accent
                    current: index === root.selectedWindowIndex
                    hasCursor: index === root.selectedWindowIndex
                    bordered: true
                    Column {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.margins: Style.space(10)
                      spacing: Style.space(3)
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: modelData.title || "Untitled window"
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: "Class: " + modelData.class + "  ·  Opens as: " + (modelData.initial_title || "(unknown)") + "  ·  Workspace: " + (modelData.workspace || "?")
                        color: root.dim
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.selectedWindowIndex = index
                      onClicked: root.chooseWindow(modelData)
                    }
                  }
                }
                Text {
                  visible: root.visibleWindows.length === 0
                  width: parent.width
                  text: root.windowsLoading ? "Reading open windows…" : "No windows found. Launch the app, then refresh."
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }
      }
    }
  }

  Component.onCompleted: { refreshApps(); refreshWindows() }
}
