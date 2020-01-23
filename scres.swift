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

class Screens {
    // assume at most 8 display connected
    var maxDisplays:Int = 8
    // actual number of display
    var displayCount:Int = 0
    
    //var displayIDs:UnsafeMutablePointer<CGDirectDisplayID>?
    var dm = [DisplayManager]()
    
    init() {
        // actual number of display
        var displayCount32:UInt32 = 0
        let displayIDsPrealloc = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity:maxDisplays)

        guard CGGetOnlineDisplayList(UInt32(maxDisplays), displayIDsPrealloc, &displayCount32) == .success else {
            print("Error on getting online display List.")
            return
        }
        displayCount = Int( displayCount32 )
        
        for i in 0..<displayCount {
            let m = DisplayManager(displayIDsPrealloc[i])
            dm.append( m )
        }
    }

    // print a list of all displays
    // used by -l
    func listDisplays() {
        for (i,m) in dm.enumerated() {
            print("Display \(i):  \(m.currentInfo.formatter())")
        }
    }
    
    func listModes(_ displayIndex:Int) -> Void {
        let cd = dm[displayIndex]
        let ci = cd.currentInfo
        cd.displayInfo.forEach { di in print(di.formatter(matchWith:ci)) }
    }

    func set(displayIndex:Int, width:Int) -> Void {
        dm[displayIndex].set(width)
    }
    func set(displayIndex:Int, width:Int, scale:Int) -> Void {
        dm[displayIndex].set(width, scale:scale)
    }
    func set(width:Int) -> Void {
        guard displayCount == 1 else {
            print("Specify display index")
            return
        }
        set(displayIndex:0, width:width)
    }
    func set(width:Int, scale:Int) -> Void {
        guard displayCount == 1 else {
            print("Specify display index")
            return
        }
        set(displayIndex:0, width:width, scale:scale)
    }
}

class DisplayManager {
    var displayID:CGDirectDisplayID, displayInfo:[DisplayInfo], currentInfo:DisplayInfo, modes:[CGDisplayMode]
    
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

        currentInfo = DisplayInfo(_displayID)
    }
    
    private func _set(modeIndex:Int) -> Void {
        guard modeIndex < modes.count else { return }
        
        let mode:CGDisplayMode = modes[modeIndex]
        
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

    private func _checkMode(_ width:Int) -> Int? {
        return displayInfo.firstIndex(where: { $0.width == width })
    }
    private func _checkMode(_ width:Int, scale:Int) -> Int? {
        return displayInfo.firstIndex(where: { $0.width == width && $0.scale == scale })
    }

    func set(_ width:Int) -> Void {
        guard let modeIndex = _checkMode(width) else {
            print("This mode is unavailable for current desktop GUI")
            return
        }
        // the modes are sorted with higher scale factor in front
        // so we select the higher scale factor (a.k.a retina) mode by default
        _set(modeIndex:modeIndex)
    }
    func set(_ width:Int, scale:Int) -> Void {
        guard let modeIndex = _checkMode(width, scale:scale) else {
            print("This mode is unavailable for current desktop GUI")
            return
        }
        print("Setting display mode")
        _set(modeIndex:modeIndex)
    }
}

// return width, height and frequency info for corresponding displayID
struct DisplayInfo: Hashable {
    var width, height, scale, frequency:Int
    
    init() {
        width = 0
        height = 0
        scale = 0
        frequency = 0
    }
    
    init(_ displayID:CGDirectDisplayID) {
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            self.init(displayID:displayID, mode:mode)
        }
        else {
            self.init()
        }
    }
    
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
            let timeValue = time.timeValue as Int64
            // a hack-y way to do ceil
            let timeScale = Int64(time.timeScale) + timeValue / 2
            
            frequency = Int( timeScale / timeValue )
        }
    }

    func formatter(matchWith:DisplayInfo?) -> String {
        // We assume that 5 digits are enough to hold dimensions.
        // 100K monitor users will just have to live with a bit of formatting misalignment.
        return String(
            format:" %@ %5d x %4d @ %dx @ %dHz",
            matchWith == self ? "--> " : "    ",
            width,
            height,
            scale,
            frequency
        )
    }
    func formatter() -> String {
        formatter(matchWith:nil)
    }

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        return lhs.width == rhs.width && lhs.height == rhs.height && lhs.scale == rhs.scale && lhs.frequency == rhs.frequency
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(scale)
        hasher.combine(frequency)
    }

    // Hasher is not available in XCode 9 yet. :-(
    // https://developer.apple.com/documentation/swift/hashable?changes=_9
    var hashValue: Int {
        // Overflows a little, but works.
        return width + 10000 * (height * 10000 * (scale + 10 * frequency))
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
    
    func argAsInt(at:Int) -> Int {
        guard at < count else {
            return -1
        }
        return Int(arguments[at])!
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
        guard input.count > 2 else {
            print("Specify a display to set its mode. \(help_display_list)")
            return
        }
        // input.count > 2 guarantees arg2 is non-nil
        let arg2 = input.argAsInt(at:2)

        switch input.count {
        case 3:
            screens.set(width:arg2)
        case 4:
            let arg3 = input.argAsInt(at:3)
            
            if (arg2 < screens.maxDisplays) {
                screens.set(displayIndex:arg2, width:arg3 )
            }
            else {
                screens.set(width:arg2, scale:arg3)
            }
        /*case 5:
            fallthrough*/
        default:
            let arg3 = input.argAsInt(at:3)
            let arg4 = input.argAsInt(at:4)

            screens.set(displayIndex:arg2, width:arg3, scale:arg4)
        }
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
