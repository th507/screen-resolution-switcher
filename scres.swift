#!/usr/bin/env xcrun -sdk macosx swift

//
//  x2.swift
//  
//
//  Created by john on 20/1/2020.
//

import Foundation
import ApplicationServices
import CoreVideo

// Supported command calls:
// 1    width                   => 2
// 2    id, width
// 3    width, scale            => 6
// 4    width, height           => 5
// 5    id, width, height
// 6    id, width, scale
// 7    id, width, height, scale
struct DisplayProperty {
    var displayIndex = 0, width = 0
    var height, scale:Int?
    init(_ arr:[String]) {
        var args = arr.compactMap({ Int($0) })

        if args[0] > Screens.MAX_DISPLAYS {
            args.insert(0 /* displayIndex */, at:0)
        }

        if args.count < 2 { return }

        displayIndex = args[0]
        width = args[1]

        if args.count == 2 { return }

        if args[2] > DisplayInfo.MAX_SCALE {
            height = args[2]

            if args.count > 3 {
                scale = args[3]
            }
        }
        else {
            scale = args[2]
            if args.count > 3 {
                height = args[3]
            }
        }

    }

    // override a lesser used operator to performance diplay mode checks concisely
    static func ~= (lhs: DisplayProperty, rhs: DisplayInfo) -> Bool {
        var bool = lhs.width == rhs.width
        
        if lhs.height != nil {
            bool = bool && lhs.height == rhs.height
        }
        if lhs.scale != nil {
            bool = bool && lhs.scale == rhs.scale
        }
        return bool
    }
}

class Screens {
    // assume at most 8 display connected
    static let MAX_DISPLAYS = 8
    var maxDisplays = MAX_DISPLAYS
    // actual number of display
    var displayCount:Int = 0
    var dm = [DisplayManager]()
    
    init() {
        // actual number of display
        var displayCount32:UInt32 = 0
        var displayIDs = [CGDirectDisplayID](arrayLiteral: 0)

        guard CGGetOnlineDisplayList(UInt32(maxDisplays), &displayIDs, &displayCount32) == .success else {
            print("Error on getting online display List.")
            return
        }
        displayCount = Int( displayCount32 )
        dm = displayIDs.map { DisplayManager($0) }
    }

    // print a list of all displays
    // used by -l
    func listDisplays() {
        for (i, m) in dm.enumerated() {
            print("Display \(i):\(m.format())")
        }
    }
    
    func listModes(_ displayIndex:Int) -> Void {
        dm[displayIndex].printFormatForAllModes()
    }

    func set(props:DisplayProperty) {
        dm[props.displayIndex].set(props:props)
    }
}

class DisplayManager {
    var displayID:CGDirectDisplayID, displayInfo:[DisplayInfo], modes:[CGDisplayMode], modeIndex:Int

    init(_ _displayID:CGDirectDisplayID) {
        displayID = _displayID
        var modesArray:[CGDisplayMode]?

        if let modeList = CGDisplayCopyAllDisplayModes(displayID, [kCGDisplayShowDuplicateLowResolutionModes:1] as CFDictionary) {
            // https://github.com/FUKUZAWA-Tadashi/FHCCommander
            modesArray = (modeList as Array).map { unsafeBitCast($0, to:CGDisplayMode.self) }
        } else {
            print("Unable to get display modes")
        }
        modes = modesArray!
        displayInfo = modes.map { DisplayInfo(displayID:_displayID, mode:$0) }

        let mode = CGDisplayCopyDisplayMode(displayID)!
        modeIndex = modes.firstIndex(of:mode)!
    }
    
    private func _format(_ di:DisplayInfo, leadingString:String) -> String {
        // We assume that 5 digits are enough to hold dimensions.
        // 100K monitor users will just have to live with a bit of formatting misalignment.
        return String(
            format:"%@%5d x %4d @ %dx @ %dHz",
            leadingString,
            di.width,
            di.height,
            di.scale,
            di.frequency
        )
    }
    
    func format() -> String{
        return _format(displayInfo[modeIndex], leadingString:"")
    }
    
    func printFormatForAllModes() {
        for (i, di) in displayInfo.enumerated() {
            print(_format(di, leadingString:i == modeIndex ? "  --> " : "      "))
        }
    }
    
    private func _set(_ mi:Int) -> Void {
        if mi == modeIndex { return }
        guard mi < modes.count else { return }
        
        let mode:CGDisplayMode = modes[mi]
        
        guard mode.isUsableForDesktopGUI() != false else {
            print("This mode is unavailable for current desktop GUI")
            return
        }
        print("Setting display mode")

        var config:CGDisplayConfigRef?
        
        let error:CGError = CGBeginDisplayConfiguration(&config)
        if error == .success {
            CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
                        
            let afterCheck = CGCompleteDisplayConfiguration(config, CGConfigureOption.permanently)
            if afterCheck != .success {
                CGCancelDisplayConfiguration(config)
            }
        }
    }

    private func _getIndex(props:DisplayProperty) -> Int? {
        return displayInfo.firstIndex(where: { props ~= $0 })
    }

    func set(props: DisplayProperty) {
        if let mi = _getIndex(props: props) {
            _set(mi)
        } else {
            print("This mode is unavailable for current desktop GUI")
        }
    }
}

// return width, height and frequency info for corresponding displayID
struct DisplayInfo {
    static let MAX_SCALE = 10
    var width, height, scale, frequency:Int

    init(displayID:CGDirectDisplayID, mode:CGDisplayMode) {
        width = mode.width
        height = mode.height
        scale = mode.pixelWidth / mode.width;
        
        frequency = Int( mode.refreshRate )
        if frequency == 0 {
            var link:CVDisplayLink?
            CVDisplayLinkCreateWithCGDisplay(displayID, &link)
            
            let time:CVTime = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!)
            // timeValue is in fact already in Int64
            let timeScale = Int64(time.timeScale) + time.timeValue / 2
            
            frequency = Int( timeScale / time.timeValue )
        }
    }

    static func ~= (lhs: DisplayInfo, rhs: DisplayProperty) -> Bool {
        return rhs ~= lhs
    }
}

// from Sindre Sorhus
// https://github.com/sindresorhus/dark-mode/blob/master/Sources/DarkMode.swift
struct DarkMode {
    private static let prefix = "tell application \"System Events\" to tell appearance preferences to"

    static var isEnabled: Bool {
        get {
            UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
        set {
            toggle(force: newValue)
        }
    }

    static func toggle(force: Bool? = nil) {
        let value = force.map(String.init) ?? "not dark mode"
        NSAppleScript(source: "\(prefix) set dark mode to \(value)")?.executeAndReturnError(nil)
    }
}

struct UserInput {
    enum Intention {
        case listDisplays
        case listModes(Int)
        case setMode
        case darkMode
        case seeHelp
    }
    
    var intention:Intention
    var arguments:[String]
    var count:Int
    
    init(_ args:[String]) {
        arguments = args
        count = arguments.count
        guard count >= 2 else {
            intention = Intention.seeHelp
            return
        }
        switch arguments[1] {
        case "-l", "--list", "list":
            intention = Intention.listDisplays
        case "-m", "--mode", "mode":
            var index = 0
            if count > 2, let displayIndex = Int(arguments[2]) {
                index = displayIndex
            }
            intention = Intention.listModes(index)
        case "-s", "--set", "set", "-r", "--set-retina", "retina":
            intention = Intention.setMode
        case "-d", "--toggle-dark-mode":
            intention = Intention.darkMode
        default:
            intention = Intention.seeHelp
        }
    }
}

let help_display_list = "List all available displays by:\n    screen-resolution-switcher -l"
let help_msg = """
Usage:
screen-resolution-switcher [-h|--help] [-l|--list|list] [-m|--mode|mode displayIndex]
[-s|--set|set displayIndex width scale] [-r|--set-retina|retina displayIndex width],

Here are some examples:
   -h          get help
   -l          list displays
   -m 0        list all mode from a certain display
   -m          shorthand for -m 0
   -s 0 800 1  set resolution of display 0 to 800 [x 600] @ 1x [@ 60Hz]
   -s 0 800    shorthand for -s 0 800 2 (highest scale factor)
   -s 800      shorthand for -s 0 800 2 (highest scale factor)
   -r 0 800    shorthand for -s 0 800 2
   -r 800      shorthand for -s 0 800 2
   -d          toggle macOS Dark Mode
"""

func main () {
    let screens = Screens()
    let input = UserInput(CommandLine.arguments)
    
    // dipatch functions
    switch input.intention {
    case .listDisplays:
        screens.listDisplays()
        
    case let .listModes(displayIndex):
        guard displayIndex < screens.displayCount else {
            print("Display index( \(displayIndex) ) not found. \(help_display_list)")
            return
        }
        
        print("Supported Modes for Display \(displayIndex):")
        screens.listModes(displayIndex)

    case .setMode:
        screens.set(props:
            DisplayProperty( input.arguments )
        )

    case .darkMode:
        DarkMode.toggle()
    default:
        print(help_msg)
    }
}

#if os(macOS)
    // run it
    main()
#else
    print("This script currently only runs on macOS")
#endif
