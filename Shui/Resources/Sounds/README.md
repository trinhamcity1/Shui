# Shui sounds

`generate.wav` is the sound that plays when someone taps **Generate** on the
New Lesson screen. Whatever file is named `generate` in this folder is the
one the app plays.

## Listen

Open any `.wav` here (or in `Library/`) to hear it. Every sound here was
synthesized from scratch for Shui, so there's no licensing to worry about.

| File | What it is |
|---|---|
| `generate.wav` | The live Generate sound (currently a copy of `Library/shimmer.wav`) |
| `Library/shimmer.wav` | A soft glass arpeggio rising over an airy breath, 1.4s |
| `Library/bloom.wav` | A warm low swell opening into one soft bell, 1.3s |
| `Library/droplet.wav` | A single water-drop pop with a short sparkle tail, 0.9s |

`Library/` is a listening room only. It isn't bundled into the app.

## Swap in a different sound

1. Copy the sound you want into this folder and name it `generate.wav`,
   replacing the old one. It can be from `Library/` or one of your own.
2. Rebuild the app in Xcode.

Keep only one file named `generate` in this folder.

**Formats:** `.wav`, `.caf`, or `.aiff`, under 30 seconds (1 to 2 seconds
feels right). iOS's system-sound player only accepts those formats, and it's
what keeps the sound quiet when the phone's silent switch is on. To convert
an `.mp3` or `.m4a` on a Mac, run this in Terminal:

```
afconvert -f WAVE -d LEI16 my-sound.mp3 generate.wav
```

If you use `.caf` or `.aiff` instead of `.wav`, run `xcodegen generate` once
before rebuilding so Xcode picks up the new file.

**Rights:** only add sounds you're allowed to use in a commercial app, such
as ones you made, bought a license for, or got from a royalty-free library
that permits app use.
