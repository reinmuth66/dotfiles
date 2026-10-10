import AppKit

// 音量と mute のメディアキー、つまりキーボードの音量キーと同じイベントを合成して送る。
// OS 自身がキーを処理するので、音量が変わり、標準の音量ポップアップがノッチ下に出る。
// osascript の set volume は、音量が変わってもポップアップを出さない。
//
// 1 回で音量は 1/16、約 6% 変わる。fine は shift + option を押した状態と同じで、1/64、約 1.6%。
//
// 送信には、このコマンドを起動した側の sketchybar に、システム設定の "アクセシビリティ" の許可が要る。

// NX_KEYTYPE_SOUND_UP / SOUND_DOWN / MUTE
let keys = ["up": 0, "down": 1, "mute": 7]

let args = Array(CommandLine.arguments.dropFirst())
guard let name = args.first, let key = keys[name] else {
	FileHandle.standardError.write(Data("usage: media-key <up|down|mute> [count] [fine]\n".utf8))
	exit(2)
}
let count = args.count > 1 ? max(Int(args[1]) ?? 1, 1) : 1
let fine = args.contains("fine")

// state の 0xa00 はキーを押した、0xb00 は離した。NX_KEYDOWN と NX_KEYUP の状態。
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

// 投稿の直後に終了すると、イベントが OS に届く前に捨てられる。実機で確認した。待たないと音量が変わらない。
usleep(100_000)
