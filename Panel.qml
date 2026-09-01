import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "adamjohnlea.passgen"
  ipcTarget: "adamjohnlea.passgen"

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string enginePath: pluginDir + "/passgen"
  readonly property string clearHelperPath: pluginDir + "/clipboard-clear"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy-passgen"
  readonly property string statePath: stateDir + "/settings.json"

  // Generation settings. Persisted to statePath; everything else is transient.
  property string type: "random"
  property int length: 12
  property bool upper: true
  property bool numbers: true
  property bool symbols: true
  property bool excludeAmbiguous: false
  property int pronounceableLength: 12
  property bool pronounceableCapitalize: true
  property bool pronounceableNumbers: true
  property int words: 4
  property string separator: "-"
  property bool passphraseCapitalize: true
  property bool passphraseNumber: false
  property int pinLength: 6
  property bool pinNoRepeat: true
  property int hexLength: 16
  property bool hexUpper: true

  // The password lives here and nowhere else — never written to disk, never
  // passed as a command-line argument, and dropped when the panel closes.
  property string password: ""
  // What is currently on the clipboard awaiting its auto-clear. Held separately
  // from `password` because closing the panel must not cancel a pending clear:
  // copy-then-close is the normal way to use this.
  property string copiedPassword: ""
  property bool revealed: true
  property string feedback: ""
  property int wordCount: 521
  property bool restoring: false

  readonly property bool autoClear: setting("autoClearClipboard", true) === true
  readonly property int clearSeconds: Math.max(5, Number(setting("clipboardClearSeconds", 30)) || 30)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var strengthResult: Model.strength(root.stateObject(), root.wordCount)
  readonly property string strengthLabel: Model.label(strengthResult.score)
  readonly property color strengthColor: {
    var s = strengthResult.score
    // Semantic red-to-green, independent of the active theme: a strength
    // meter that reads "green" only in some themes is not a meter.
    if (s < 0.3) return "#c65454"
    if (s < 0.6) return "#cc8b3f"
    if (s < 0.8) return "#c9b455"
    return "#5fa564"
  }

  function stateObject() {
    return {
      type: root.type,
      length: root.length,
      upper: root.upper,
      numbers: root.numbers,
      symbols: root.symbols,
      excludeAmbiguous: root.excludeAmbiguous,
      pronounceableLength: root.pronounceableLength,
      pronounceableCapitalize: root.pronounceableCapitalize,
      pronounceableNumbers: root.pronounceableNumbers,
      words: root.words,
      separator: root.separator,
      passphraseCapitalize: root.passphraseCapitalize,
      passphraseNumber: root.passphraseNumber,
      pinLength: root.pinLength,
      pinNoRepeat: root.pinNoRepeat,
      hexLength: root.hexLength,
      hexUpper: root.hexUpper
    }
  }

  function applyState(saved) {
    root.restoring = true
    var current = root.stateObject()
    for (var key in current) {
      if (saved[key] === undefined) continue
      if (typeof saved[key] !== typeof current[key]) continue
      root[key] = saved[key]
    }
    root.restoring = false
  }

  function persist() {
    if (root.restoring) return
    saveDebounce.restart()
  }

  function generate() {
    generator.running = false
    generator.command = Model.command(root.enginePath, root.stateObject())
    generator.running = true
  }

  function copyPassword() {
    if (root.password === "") return
    copier.running = false
    copier.running = true
  }

  function showFeedback(message) {
    root.feedback = message
    feedbackTimer.restart()
  }

  function forget() {
    root.password = ""
    root.revealed = true
    root.feedback = ""
    feedbackTimer.stop()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      root.feedback = ""
      // A password is ready the moment the panel opens, matching the macOS popover.
      root.generate()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      // Nothing sensitive survives a closed panel.
      root.forget()
    }
  }

  onTypeChanged: { root.persist(); if (root.opened) root.generate() }
  onLengthChanged: root.persist()
  onUpperChanged: root.persist()
  onNumbersChanged: root.persist()
  onSymbolsChanged: root.persist()
  onExcludeAmbiguousChanged: root.persist()
  onPronounceableLengthChanged: root.persist()
  onPronounceableCapitalizeChanged: root.persist()
  onPronounceableNumbersChanged: root.persist()
  onWordsChanged: root.persist()
  onSeparatorChanged: root.persist()
  onPassphraseCapitalizeChanged: root.persist()
  onPassphraseNumberChanged: root.persist()
  onPinLengthChanged: root.persist()
  onPinNoRepeatChanged: root.persist()
  onHexLengthChanged: root.persist()
  onHexUpperChanged: root.persist()

  Component.onCompleted: stateDirProcess.running = true

  // ---- processes -------------------------------------------------------

  Process {
    id: stateDirProcess
    command: ["mkdir", "-p", root.stateDir]
    onExited: stateFile.reload()
  }

  Process {
    id: generator
    stdout: StdioCollector {
      onStreamFinished: {
        var out = String(text || "").trim()
        if (out === "") return
        root.password = out
        root.revealed = true
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err !== "") root.showFeedback("Generator failed")
      }
    }
  }

  // wl-copy --sensitive offers the x-kde-passwordManagerHint MIME type, which
  // Omarchy's own clipboard history greps for and skips. The password goes in
  // over stdin because argv is world-readable through /proc and wl-copy stays
  // resident to serve the selection.
  Process {
    id: copier
    command: ["wl-copy", "--sensitive"]
    stdinEnabled: true
    onStarted: {
      write(root.password)
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.showFeedback("Copy failed")
        return
      }
      root.copiedPassword = root.password
      if (root.autoClear) {
        root.showFeedback("Copied — clears in " + Model.clearDelayText(root.clearSeconds))
        clearTimer.restart()
      } else {
        root.showFeedback("Copied")
      }
    }
  }

  Process {
    id: clearer
    command: [root.clearHelperPath]
    stdinEnabled: true
    onStarted: {
      write(root.copiedPassword)
      stdinEnabled = false
    }
    onExited: {
      root.copiedPassword = ""
      root.revealed = false
      root.showFeedback("Clipboard cleared")
    }
  }

  Timer {
    id: clearTimer
    interval: root.clearSeconds * 1000
    onTriggered: {
      if (root.copiedPassword === "") return
      clearer.running = false
      clearer.running = true
    }
  }

  Timer {
    id: feedbackTimer
    interval: 3000
    onTriggered: root.feedback = ""
  }

  Timer {
    id: saveDebounce
    interval: 400
    onTriggered: stateFile.setText(JSON.stringify(root.stateObject(), null, 2) + "\n")
  }

  FileView {
    id: stateFile
    path: root.statePath
    preload: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        root.applyState(JSON.parse(text()))
      } catch (e) {
        // A corrupt or absent settings file just means defaults.
      }
    }
  }

  // The word list is the single source of truth for passphrase entropy, so the
  // strength meter counts the same words the engine draws from.
  FileView {
    id: wordlistFile
    path: root.pluginDir + "/wordlist.txt"
    preload: true
    watchChanges: false
    printErrors: false
    onLoaded: {
      var lines = String(text() || "").split("\n").filter(function(w) { return w.trim() !== "" })
      if (lines.length > 0) root.wordCount = lines.length
    }
  }

  // ---- bar button ------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Text {
        text: "󰌆"
        color: root.barForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
    onPressed: root.toggle()
  }

  // ---- panel -----------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onReturnRequested: root.generate()
      onActivateRequested: root.generate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = t.toLowerCase()
        if (key === "c") root.copyPassword()
        else if (key === "h") root.revealed = !root.revealed
        else if (key === "g") root.generate()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          title: "Password Generator"
          meta: root.typeLabel(root.type)
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰌆"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        // ---- type -------------------------------------------------------

        LabelledRow {
          label: "Type"

          Dropdown {
            width: Style.spacing.dropdownWidth
            showLabel: false
            fontFamily: root.fontFamily
            options: [
              { value: "random", label: "Random" },
              { value: "pronounceable", label: "Pronounceable" },
              { value: "passphrase", label: "Passphrase" },
              { value: "pin", label: "PIN" },
              { value: "hex", label: "Hex" }
            ]
            value: root.type
            onChanged: function(v) { root.type = v }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- random -----------------------------------------------------

        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.type === "random"

          SliderRow {
            label: "Length"
            from: 8
            to: 32
            value: root.length
            onPicked: function(v) { root.length = v }
          }

          LabelledRow {
            label: "Include"

            Row {
              spacing: Style.space(6)

              Chip {
                text: "123"
                tip: "Digits 0-9"
                selected: root.numbers
                onClicked: root.numbers = !root.numbers
              }
              Chip {
                text: "ABC"
                tip: "Uppercase A-Z"
                selected: root.upper
                onClicked: root.upper = !root.upper
              }
              Chip {
                text: "@#!"
                tip: "Symbols !@#%^&*()-_=+<>?"
                selected: root.symbols
                onClicked: root.symbols = !root.symbols
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Exclude ambiguous"
            description: "Leave out 0 O 1 l I | `"
            checked: root.excludeAmbiguous
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.excludeAmbiguous = !root.excludeAmbiguous
          }
        }

        // ---- pronounceable ----------------------------------------------

        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.type === "pronounceable"

          SliderRow {
            label: "Length"
            from: 6
            to: 32
            value: root.pronounceableLength
            onPicked: function(v) { root.pronounceableLength = v }
          }

          Toggle {
            width: parent.width
            label: "Capitalize"
            description: "Uppercase the first letter"
            checked: root.pronounceableCapitalize
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.pronounceableCapitalize = !root.pronounceableCapitalize
          }

          Toggle {
            width: parent.width
            label: "Add numbers"
            description: "Append two digits"
            checked: root.pronounceableNumbers
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.pronounceableNumbers = !root.pronounceableNumbers
          }
        }

        // ---- passphrase --------------------------------------------------

        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.type === "passphrase"

          SliderRow {
            label: "Words"
            from: 3
            to: 8
            value: root.words
            onPicked: function(v) { root.words = v }
          }

          LabelledRow {
            label: "Separator"

            Row {
              spacing: Style.space(6)

              Chip {
                text: "-"
                tip: "Hyphen"
                selected: root.separator === "-"
                onClicked: root.separator = "-"
              }
              Chip {
                text: "_"
                tip: "Underscore"
                selected: root.separator === "_"
                onClicked: root.separator = "_"
              }
              Chip {
                text: "."
                tip: "Period"
                selected: root.separator === "."
                onClicked: root.separator = "."
              }
              Chip {
                text: "space"
                tip: "Space"
                selected: root.separator === " "
                onClicked: root.separator = " "
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Capitalize"
            description: "Uppercase each word"
            checked: root.passphraseCapitalize
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.passphraseCapitalize = !root.passphraseCapitalize
          }

          Toggle {
            width: parent.width
            label: "Add number"
            description: "Append a number to the phrase"
            checked: root.passphraseNumber
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.passphraseNumber = !root.passphraseNumber
          }
        }

        // ---- pin ---------------------------------------------------------

        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.type === "pin"

          SliderRow {
            label: "Digits"
            from: 4
            to: 12
            value: root.pinLength
            onPicked: function(v) { root.pinLength = v }
          }

          Toggle {
            width: parent.width
            label: "Avoid repeating digits"
            description: "Never repeat a digit back to back"
            checked: root.pinNoRepeat
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.pinNoRepeat = !root.pinNoRepeat
          }
        }

        // ---- hex ---------------------------------------------------------

        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.type === "hex"

          SliderRow {
            label: "Length"
            from: 8
            to: 64
            stepSize: 2
            value: root.hexLength
            onPicked: function(v) { root.hexLength = v }
          }

          Toggle {
            width: parent.width
            label: "Uppercase"
            description: "A-F instead of a-f"
            checked: root.hexUpper
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.hexUpper = !root.hexUpper
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- result ------------------------------------------------------

        Rectangle {
          width: parent.width
          implicitHeight: Math.max(Style.space(44), passwordRow.implicitHeight + Style.space(16))
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.foreground, Color.accent)
          border.width: Math.max(1, Style.normalBorderWidth)
          border.color: Qt.alpha(root.foreground, 0.18)

          RowLayout {
            id: passwordRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: root.password === ""
                    ? "Press Generate"
                    : (root.revealed ? root.password : "•".repeat(Math.min(root.password.length, 40)))
              color: root.password === "" ? root.dim : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              wrapMode: Text.WrapAnywhere
              maximumLineCount: 3
              elide: Text.ElideRight
            }

            PanelActionButton {
              Layout.alignment: Qt.AlignVCenter
              iconText: root.revealed ? "󰈉" : "󰈈"
              tooltipText: root.revealed ? "Hide password" : "Show password"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.password !== ""
              onClicked: root.revealed = !root.revealed
            }

            PanelActionButton {
              Layout.alignment: Qt.AlignVCenter
              iconText: "󰆏"
              tooltipText: "Copy to clipboard"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.password !== ""
              onClicked: root.copyPassword()
            }
          }
        }

        // ---- strength ----------------------------------------------------

        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            height: strengthText.implicitHeight

            Text {
              id: strengthText
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: root.strengthLabel
              color: root.strengthColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: Model.bitsText(root.strengthResult)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(5)
            radius: height / 2
            color: Qt.alpha(root.foreground, 0.12)

            Rectangle {
              width: parent.width * root.strengthResult.score
              height: parent.height
              radius: parent.radius
              color: root.strengthColor

              Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
              }
              Behavior on color {
                ColorAnimation { duration: 220 }
              }
            }
          }
        }

        // ---- generate ------------------------------------------------------

        Button {
          width: parent.width
          text: "Generate"
          iconText: "󰑐"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.generate()
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          visible: root.feedback !== ""
          text: root.feedback
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  function typeLabel(t) {
    switch (t) {
    case "random": return "Random characters"
    case "pronounceable": return "Pronounceable"
    case "passphrase": return "Passphrase"
    case "pin": return "PIN"
    case "hex": return "Hexadecimal"
    }
    return ""
  }

  // ---- local components -------------------------------------------------

  component LabelledRow: Item {
    property string label: ""
    default property alias content: holder.data

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, holder.childrenRect.height)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      id: holder
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
  }

  component SliderRow: Item {
    property string label: ""
    property int from: 0
    property int to: 100
    property int stepSize: 1
    property int value: 0
    signal picked(int value)

    width: parent ? parent.width : 0
    implicitHeight: Style.spacing.controlHeight

    Text {
      id: sliderLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: sliderValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: String(parent.value)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      horizontalAlignment: Text.AlignRight
      width: Style.space(24)
    }

    PanelSlider {
      anchors.left: sliderLabel.right
      anchors.right: sliderValue.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(14)
      anchors.rightMargin: Style.space(12)
      bar: root.bar
      minimum: parent.from
      maximum: parent.to
      step: parent.stepSize
      integer: true
      value: parent.value
      onMoved: function(v) { parent.picked(Math.round(v)) }
      onReleased: function(v) { parent.picked(Math.round(v)) }
    }
  }

  component Chip: Button {
    property string tip: ""

    text: ""
    tooltipText: tip
    selected: false
    bordered: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
  }
}
