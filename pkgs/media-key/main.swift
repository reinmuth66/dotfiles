import AppKit

// Synthesizes and sends media keys for volume and mute, i.e. the same events as the keyboard's volume keys.
// The OS itself handles the key, so the volume changes and the standard volume popup appears below the notch.
// osascript's set volume does not show a popup even when the volume changes.
//
// One press changes the volume by 1/16, about 6%. fine is the same as holding shift + option: 1/64, about 1.6%.
//
// Sending requires the sketchybar that launched this command to have "Accessibility" permission in System Settings.

// NX_KEYTYPE_SOUND_UP / SOUND_DOWN / MUTE
let keys = ["up": 0, "down": 1, "mute": 7]

let args = Array(CommandLine.arguments.dropFirst())
guard let name = args.first, let key = keys[name] else {
	FileHandle.standardError.write(Data("usage: media-key <up|down|mute> [count] [fine]\n".utf8))
	exit(2)
}
let count = args.count > 1 ? max(Int(args[1]) ?? 1, 1) : 1
let fine = args.contains("fine")

// state 0xa00 is key down and 0xb00 is key up. The states of NX_KEYDOWN and NX_KEYUP.
func post(down: Bool) {
	let state = down ? 0xa00 : 0xb00
	var flags = NSEvent.ModifierFlags(rawValue: UInt(state))
	if fine {
		flags.formUnion([.shift, .option])
	}
	let event = NSEvent.otherEvent(
		with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
		windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | state, data2: -1)
	event?.cgEvent?.post(tap: .cghidEventTap)
}

for _ in 0..<count {
	post(down: true)
	post(down: false)
	usleep(20_000)
}

// Exiting right after posting makes the event get discarded before it reaches the OS. Verified on the actual device. Without waiting the volume does not change.
usleep(100_000)
