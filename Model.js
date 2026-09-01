.pragma library

// Strength scoring, ported from the macOS app so both versions rate a
// given setting identically. `score` is the 0..1 bar fill; `bits` is the
// entropy the settings actually buy you.

var LOWERCASE = 26
var UPPERCASE = 26
var NUMBERS = 10
var SYMBOLS = 16

// "0O1lI|`" intersected with each set: l / O,I / 0,1 / none.
var AMBIGUOUS_IN = { lower: 1, upper: 2, numbers: 2, symbols: 0 }

// A consonant cluster (43 options) plus a vowel (11) averages 3.1 characters,
// so each character is worth about log2(43 * 11) / 3.1 bits. Truncation to the
// requested length shaves a little off, hence the conservative rounding down.
var PRONOUNCEABLE_BITS_PER_CHAR = 2.8

function randomPool(upper, numbers, symbols, excludeAmbiguous) {
  var pool = LOWERCASE - (excludeAmbiguous ? AMBIGUOUS_IN.lower : 0)
  if (upper) pool += UPPERCASE - (excludeAmbiguous ? AMBIGUOUS_IN.upper : 0)
  if (numbers) pool += NUMBERS - (excludeAmbiguous ? AMBIGUOUS_IN.numbers : 0)
  if (symbols) pool += SYMBOLS - (excludeAmbiguous ? AMBIGUOUS_IN.symbols : 0)
  return Math.max(1, pool)
}

function clamp01(v) {
  return Math.max(0, Math.min(1, v))
}

// Returns { score, bits, approximate }.
function strength(state, wordCount) {
  switch (state.type) {
  case "random": {
    var pool = randomPool(state.upper, state.numbers, state.symbols, state.excludeAmbiguous)
    var bits = state.length * (Math.log(pool) / Math.LN2)
    // 120 bits fills the bar, matching the macOS normalization.
    return { score: clamp01(bits / 120), bits: bits, approximate: false }
  }
  case "pronounceable": {
    var score = clamp01((state.pronounceableLength - 8) / 16) * 0.6
    if (state.pronounceableCapitalize) score += 0.1
    if (state.pronounceableNumbers) score += 0.2
    return {
      score: clamp01(score),
      bits: state.pronounceableLength * PRONOUNCEABLE_BITS_PER_CHAR
            + (state.pronounceableNumbers ? Math.log(90) / Math.LN2 : 0),
      approximate: true
    }
  }
  case "passphrase": {
    var perWord = Math.log(Math.max(2, wordCount)) / Math.LN2
    var total = perWord * state.words
    var s = clamp01(total / 72)
    if (state.passphraseNumber) s = clamp01(s + 0.05)
    return {
      score: s,
      bits: total + (state.passphraseNumber ? Math.log(990) / Math.LN2 : 0),
      approximate: false
    }
  }
  case "pin":
    return {
      score: clamp01((state.pinLength - 4) / 8) * 0.4,
      bits: state.pinLength * (Math.log(10) / Math.LN2),
      approximate: false
    }
  case "hex":
    return {
      score: clamp01((state.hexLength - 8) / 16) * 0.65,
      bits: state.hexLength * 4,
      approximate: false
    }
  }
  return { score: 0, bits: 0, approximate: false }
}

function label(score) {
  if (score < 0.3) return "Weak"
  if (score < 0.6) return "Fair"
  if (score < 0.8) return "Good"
  return "Strong"
}

function bitsText(result) {
  var rounded = Math.round(result.bits)
  return (result.approximate ? "~" : "") + rounded + " bits"
}

// The argv for the engine. The password itself never travels this way —
// it comes back on stdout.
function command(binary, state) {
  switch (state.type) {
  case "random":
    return [binary, "random", "--length", String(state.length),
            state.upper ? "--upper" : "--no-upper",
            state.numbers ? "--numbers" : "--no-numbers",
            state.symbols ? "--symbols" : "--no-symbols"]
           .concat(state.excludeAmbiguous ? ["--exclude-ambiguous"] : [])
  case "pronounceable":
    return [binary, "pronounceable", "--length", String(state.pronounceableLength),
            state.pronounceableCapitalize ? "--capitalize" : "--no-capitalize",
            state.pronounceableNumbers ? "--numbers" : "--no-numbers"]
  case "passphrase":
    return [binary, "passphrase", "--words", String(state.words),
            "--separator", state.separator,
            state.passphraseCapitalize ? "--capitalize" : "--no-capitalize",
            state.passphraseNumber ? "--number" : "--no-number"]
  case "pin":
    return [binary, "pin", "--length", String(state.pinLength),
            state.pinNoRepeat ? "--no-repeat" : "--allow-repeat"]
  case "hex":
    return [binary, "hex", "--length", String(state.hexLength),
            state.hexUpper ? "--upper" : "--no-upper"]
  }
  return [binary, "random"]
}

function clearDelayText(seconds) {
  return seconds >= 60 ? (Math.round(seconds / 60) + "m") : (seconds + "s")
}
