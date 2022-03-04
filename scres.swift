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
import OSAKit
import IOKit

class DisplayManager {
    let displayID:CGDirectDisplayID, displayInfo:[DisplayInfo], modes:[CGDisplayMode]
    let modeID:Int32

    init(_ displayID:CGDirectDisplayID) {
        self.displayID = displayID
        
        let mode = CGDisplayCopyDisplayMode(displayID)!
        self.modeID = mode.ioDisplayModeID

        
        var option:CFDictionary?
        let subList = ( CGDisplayCopyAllDisplayModes(displayID, option) as! Array )
            .filter { ($0 as CGDisplayMode).isUsableForDesktopGUI() }
        
        
        option = [kCGDisplayShowDuplicateLowResolutionModes:kCFBooleanTrue] as CFDictionary
        let modeList = ( CGDisplayCopyAllDisplayModes(displayID, option) as! Array )
            .filter { ($0 as CGDisplayMode).isUsableForDesktopGUI() }
                

        self.modes = modeList.filter { !subList.contains($0) }
        self.displayInfo = Array(Set(
            modes.map { DisplayInfo(displayID:displayID, mode:$0) }
        )).sorted()
    }
    
    private func _format(_ di:DisplayInfo, leadingString:String, trailingString:String) -> String {
        // We assume that 5 digits are enough to hold dimensions.
        // 100K monitor users will just have to live with a bit of formatting misalignment.
        return String(
            format:"  %@ %5d x %4d @ %dx @ %dHz%@",
            leadingString,
            di.width, di.height,
            di.scale, di.frequency,
            trailingString
        )
    }
    
    func printForOneDisplay(_ leadingString:String) {
        let di = displayInfo.filter { $0.modeID == modeID }
        print(_format(di[0], leadingString:leadingString, trailingString:""))
    }
    
    func printFormatForAllModes() {
        displayInfo.forEach { di in
            let b = di.modeID == modeID
            print(_format(di, leadingString: b ? "\u{001B}[0;33m⮕" : " ", trailingString: b ? "\u{001B}[0;49m" : ""))
        }
    }
    
    private func _set(_ di:DisplayInfo) {
        let mode:CGDisplayMode = di.modeRef

        print("Setting display mode")

        var config:CGDisplayConfigRef?
        
        let error:CGError = CGBeginDisplayConfiguration(&config)
        if error == .success {
            CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
                        
            let afterCheck = CGCompleteDisplayConfiguration(config, CGConfigureOption.permanently)
            if afterCheck != .success { CGCancelDisplayConfiguration(config) }
        }
    }

    func set(with setting: DisplayUserSetting) {
        if let di = displayInfo.first(where: { setting == $0 }) {
            if di.modeID != modeID { _set(di) }
        } else {
            print("This mode is unavailable")
        }
    }
}

// return width, height and frequency info for corresponding displayID
struct DisplayInfo:Hashable & Comparable & Equatable {
    static let MAX_SCALE = 10
    var width, height, scale, frequency:Int
    var modeID:Int32
    var modeRef:CGDisplayMode
    //var colorDepth, resolution:Int

    init(displayID:CGDirectDisplayID, mode:CGDisplayMode) {
        width = mode.width
        height = mode.height
        scale = mode.pixelWidth / mode.width
        modeID = mode.ioDisplayModeID
        modeRef = mode
        //colorDepth = Int( mode.BitsPerSample )
        //resolution = Int( mode[kCGDisplayResolution] )
        
        frequency = Int( mode.refreshRate )
        if frequency == 0 {
            var link:CVDisplayLink?
            CVDisplayLinkCreateWithCGDisplay(displayID, &link)
            
            let time = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!)
            // timeValue is in fact already in Int64
            let timeScale = Int64(time.timeScale) + time.timeValue / 2
            
            frequency = Int( timeScale / time.timeValue )
        }
    }
    
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.scale < rhs.scale { return true }
        else if lhs.width < rhs.width { return true }
        else { return false }
    }

    static func == (lhs: Self, rhs: DisplayUserSetting) -> Bool {
        var bool = rhs.width == lhs.width

        if rhs.height != nil { bool = bool && rhs.height == lhs.height }
        if rhs.scale != nil { bool = bool && rhs.scale == lhs.scale }
        return bool

    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.width == rhs.width &&
            lhs.height == rhs.height &&
            lhs.scale == rhs.scale /*&&
            lhs.frequency == rhs.frequency*/
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(scale)
        //hasher.combine(frequency)
    }
}

// Supported command calls:
// 1    width                   => 2
// 2    id, width
// 3    width, scale            => 6
// 4    width, height           =>
// 5    id, width, height
// 6    id, width, scale
// 7    id, width, height, scale
struct DisplayUserSetting {
    var displayIndex = 0, width = 0
    var height, scale:Int?
    init(_ arr:[String]) {
        var args = arr.compactMap { Int($0) }
        
        if args.count < 1 { return }
        
        if args[0] > Screens.MAX_DISPLAYS { args.insert(0 /* displayIndex */, at:0) }

        if args.count < 2 { return }

        displayIndex = args[0]
        width = args[1]

        if args.count == 2 { return }

        if args[2] > DisplayInfo.MAX_SCALE {
            height = args[2]
            if args.count > 3 { scale = args[3] }
        }
        else {
            scale = args[2]
            if args.count > 3 { height = args[3] }
        }
    }

    // override a lesser-used operator to simplify display mode checks
    static func == (lhs: Self, rhs: DisplayInfo) -> Bool {
        return rhs == lhs
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
        var displayIDs = [CGDirectDisplayID](repeating: 0, count:maxDisplays)

        guard CGGetOnlineDisplayList(UInt32(maxDisplays), &displayIDs, &displayCount32) == .success else {
            print("Error on getting online display List.")
            return
        }
        displayCount = Int( displayCount32 )
        dm = displayIDs
            .filter { $0 != 0 }
            .map { DisplayManager($0) }
    }

    // print a list of all displays
    // used by -l
    func listDisplays() {
        for (i, m) in dm.enumerated() {
           m.printForOneDisplay("Display \(i):")
        }
    }

    func listModes(_ displayIndex:Int) {
        dm[displayIndex].printFormatForAllModes()
    }

    func set(with setting:DisplayUserSetting) {
        dm[setting.displayIndex].set(with:setting)
    }
}

// darkMode toggle code with JXA ;-)
// Method from Stackoverflow User: bacongravy
// https://stackoverflow.com/questions/44209057
struct DarkMode {
    static let scriptString = """
    pref = Application(\"System Events\").appearancePreferences
    pref.darkMode = !pref.darkMode()
"""
    let script = OSAScript.init(source: scriptString, language: OSALanguage.init(forName: "JavaScript"))
    
    init() {
        var compileError: NSDictionary?

        script.compileAndReturnError(&compileError)
    }
    func toggle() {
        var scriptError: NSDictionary?

        if let result = script.executeAndReturnError(&scriptError)?.stringValue { print("Dark Mode:", result) }
    }
}

func sleepDisplay() {
    let r = IORegistryEntryFromPath(kIOMainPortDefault, strdup("IOService:/IOResources/IODisplayWrangler"))

    IORegistryEntrySetCFProperty(r, ("IORequestIdle" as CFString), kCFBooleanTrue)
    IOObjectRelease(r)
}

func seeHelp() {
print("""
Usage:
screen-resolution-switcher [-h|--help] [-l|--list|list] [-m|--mode|mode displayIndex]
[-s|--set|set displayIndex width scale] [-r|--set-retina|retina displayIndex width],

Here are some examples:
   -h               get help
   -l               list displays
   -m 0             list all mode from a certain display
   -m               shorthand for -m 0
   -s 0 800 600 1   set resolution of display 0 to 800 x 600 @ 1x [@ 60Hz]
   -s 0 800 600     set resolution of display 0 to 800 x 600 @(highest scale factor)
   -s 0 800 1       set resolution of display 0 to 800 [x 600] @ 1x [@ 60Hz]
   -s 0 800         shorthand for -s 0 800 2 (highest scale factor)
   -s 800           shorthand for -s 0 800 2 (highest scale factor)
   -r 0 800         shorthand for -s 0 800 2
   -r 800           shorthand for -s 0 800 2
   -d               toggle macOS Dark Mode
   -sl              sleep display
""")
}

func main() {
    let screens = Screens()

    let arguments = CommandLine.arguments
    let count = arguments.count
    guard count >= 2 else {
        seeHelp()
        return
    }
    switch arguments[1] {
    case "-l", "--list", "list":
        screens.listDisplays()
    case "-m", "--mode", "mode":
        var displayIndex = 0
        if count > 2, let index = Int(arguments[2]) {
            displayIndex = index
        }
        if displayIndex < screens.displayCount {
            print("Supported Modes for Display \(displayIndex):")
            screens.listModes(displayIndex)
        } else {
            print("Display index not found. List all available displays by:\n    screen-resolution-switcher -l")
        }
    case "-s", "--set", "set", "-r", "--set-retina", "retina":
        screens.set(with:DisplayUserSetting( arguments ))
    case "-d", "--toggle-dark-mode":
        DarkMode().toggle()
    case "-sl", "--sleep", "sleep":
        sleepDisplay()
    default:
        seeHelp()
    }
}

#if os(macOS)
    // run it
    main()
#else
    print("This script currently only runs on macOS")
#endif
