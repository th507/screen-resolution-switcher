#!/usr/bin/env xcrun -sdk macosx swift

//
//  scres.swift
//  
//
//  Created by john on 20/1/2020.
//
//  WARNING: it contains concentrated dosage of Swift CGDisplayMode hacks and fuckery. 
//  CGDisplayMode in Swiftlang is not very well documented, perhaps rightfully so since it's rarely used.
//  Reader discretion is advised.

import Foundation
import CoreFoundation
import ApplicationServices
import CoreVideo
import OSAKit
import IOKit

// DisplayMode
struct MyDisplayMode {
    let mode:CGDisplayMode
    let modeFromJSON:CGDisplayModeFromJSON
    init(mode:CGDisplayMode, modeFromJSON:CGDisplayModeFromJSON) {
        self.mode = mode
        self.modeFromJSON = modeFromJSON
    }
}

// a custom data type that stores String or Double
// from https://medium.com/swlh/f6ea6a2babf8
enum StringOrDouble: Decodable {
    case double(Double)
    case string(String)
    
    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            self = .string(string)
            return
        }
        if let double = try? decoder.singleValueContainer().decode(Double.self) {
            self = .double(double)
            return
        }
        throw Error.couldNotFindStringOrDouble
    }
    enum Error: Swift.Error {
        case couldNotFindStringOrDouble
    }
}

// get computed refreshrate
fileprivate func _getAlternativeRefreshRate(by displayID:CGDirectDisplayID) -> Int {
    var link:CVDisplayLink?
    CVDisplayLinkCreateWithCGDisplay(displayID, &link)
    
    let time = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!)
    // timeValue is in fact already in Int64
    let timeScale = Int64(time.timeScale) + time.timeValue / 2
    
    return Int( timeScale / time.timeValue )
}
// for JSON hacking
fileprivate func _replaces(in str:String) throws -> String {
    let replacement = [
        // bracket: remove CGDisplayMode and [
        #"\<CGDisplayMode\s0x([0-9a-f]+)\>\s\["#: "",
        // bracket: remove last ]
        #"\](?!\n)"#: "",
        // assignment & quotation: replace = with :
        #"\ ="#: #"\"\ :"#,
        // quotation: insert " at every new line execpt following by }
        #"\n(?!\})\s*"#: "\n\"",
        // separator: replace ; with ,
        ";": ",",
    ]
    
    var out = str
    for (key, value) in replacement {
        let range = NSRange(out.startIndex..<out.endIndex, in:out)
        let r = try NSRegularExpression(pattern: key, options: [])
        out = r.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: value)
    }
    // TODO: investigate why replacement fails
    return out + "]"
}

// for dealing with CGDisplayModeFromJSON.RefreshRate, which return String or Double 0 in various settings
// this can be retrieved by printing CGDisplayMode
struct CGDisplayModeFromJSON: Decodable {
    //var BitsPerPixel = 32;
    var BitsPerSample = 8;
    var DepthFormat = 4;
    var Height = 2160;
    //var IODisplayModeID = "-2147454976";
    //var IOFlags = 1048579;
    //var Mode = 0;
    var PixelEncoding = "--------RRRRRRRRGGGGGGGGBBBBBBBB";
    /* making a type augmentation as program return String or 0 in various settings
     * case String: RefreshRate is a String with quotation marks but representing a Double
     * case Double: RefreshRate is 0 without quotation marks, and will decode into a Double
     */
    var RefreshRate:StringOrDouble// = "30.00001525878906";
    var SamplesPerPixel = 3;
    //var UsableForDesktopGUI = 1;
    var Width = 3840;
    //var kCGDisplayBytesPerRow = 15360;
    var kCGDisplayHorizontalResolution = 163;
    //var kCGDisplayModeIsInterlaced = 0;
    //var kCGDisplayModeIsSafeForHardware = 1;
    //var kCGDisplayModeIsStretched = 0;
    //var kCGDisplayModeIsTelevisionOutput = 1;
    //var kCGDisplayModeIsUnavailable = 0;
    //var kCGDisplayModeSuitableForUI = 1;
    var kCGDisplayPixelsHigh = 2160;
    var kCGDisplayPixelsWide = 3840;
    var kCGDisplayResolution = 1;
    var kCGDisplayVerticalResolution = 163;
    // additional mutating property that stores computed refreshrate
    var frequency:Int?
}
// use the object as key in a later process of mode filtering/winnowing
extension CGDisplayModeFromJSON: Hashable & Equatable & Comparable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(Width)
        hasher.combine(Height)
        hasher.combine(kCGDisplayPixelsWide)
        hasher.combine(kCGDisplayPixelsHigh)
    }
    // loose comparison for Diction Key
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.Width == rhs.Width && lhs.kCGDisplayPixelsWide == rhs.kCGDisplayPixelsWide &&
        lhs.Height == rhs.Height && lhs.kCGDisplayPixelsHigh == rhs.kCGDisplayPixelsHigh
    }
    // strict comparison
    static func ~=(lhs: Self, rhs: Self) -> Bool {
        return lhs == rhs && lhs["frequency"] == rhs["frequency"] &&
        lhs["kCGDisplayHorizontalResolution"] == rhs["kCGDisplayHorizontalResolution"]
    }
    
    // for sorting
    static func < (lhs: Self, rhs: Self) -> Bool {
        let ls = lhs["scale"]
        let rs = rhs["scale"]
        return ls != rs ? ls < rs : lhs.Width < rhs.Width
    }
    
    // for setting comparison
    static func == (lhs: Self, rhs: DisplayUserSetting) -> Bool {
        var bool = (lhs.Width == rhs.width)
        
        if rhs.height != nil { bool = bool && (rhs.height == lhs.Height) }
        if rhs.scale != nil { bool = bool && (rhs.scale == lhs["scale"]) }
        return bool
    }
    /*func debug() -> String {
        return "s:\(self["scale"]),w:\(self.Width),h:\(self.Height)"
    }*/
}

extension CGDisplayModeFromJSON {
    // this is a hack to read private members in CGDisplayMode
    static func decode(from modes:[CGDisplayMode], displayID:CGDirectDisplayID) -> [CGDisplayModeFromJSON]? {
        do {
            // first we operate the string to make it look like JSON String
            let modesJSONText = try _replaces(in: String(reflecting:modes))
            
            // then we try to decode it as JSON
            let decoder = JSONDecoder()
            var modesFromJSON = try decoder.decode([CGDisplayModeFromJSON].self, from: modesJSONText.data(using: .utf8)!)
            
            let displayRefreshRate = _getAlternativeRefreshRate(by: displayID)
            for i in 0..<modesFromJSON.count {
                modesFromJSON[i].updateRefreshRate(alternativeRate: displayRefreshRate)
            }
            
            // preliminary integrity check
            guard modesFromJSON.count == modes.count else { return nil }
            
            return modesFromJSON
        } catch {
            // TODO: catch error and warn user properly
            print(error)
            return nil
        }
    }
    
    mutating func updateRefreshRate(alternativeRate:Int) {
        if self.frequency != nil { return }
        
        let frequency:Int
        switch self.RefreshRate {
        case .string(let s): frequency = Int( Double(s)?.rounded() ?? 0)
        case .double(let d): frequency = Int( d.rounded() )
        }
        
        if frequency != 0 {
            self.frequency = frequency
        } else {
            self.frequency = alternativeRate
        }
    }

    // for property loop in mode filtering
    // and as a side effect, we could accomplish `RefreshRate` type coersion
    subscript(index:String) -> Int {
        get {
            switch index {
            case "kCGDisplayHorizontalResolution": return self.kCGDisplayHorizontalResolution
            case "DepthFormat": return self.DepthFormat
            case "BitsPerSample": return self.BitsPerSample
            case "scale":  return self.kCGDisplayPixelsWide / self.Width
            case "frequency": return self.frequency!
            default: return 0
            }
        }
    }
}

// utility functions in CGDisplayMode filtering
struct Sieve {
    let propertyList = ["frequency", "kCGDisplayHorizontalResolution", "DepthFormat", "BitsPerSample"]
    var largest:[String:Int]
    var filtered:[String:[Int]]
    
    // invoking maxValue update & record-keeping
    init(in modesFromJSON:[CGDisplayModeFromJSON], withIndexArray arr:[Int]) {
        largest = [String:Int]()
        filtered = [String:[Int]]()
        for prop in propertyList {
            largest[prop] = 0
            filtered[prop] = []

            arr.forEach { i in
                switch modesFromJSON[i][prop] {
                    // update for new maxValue
                case let x where x > largest[prop]!:
                    largest[prop] = x
                    filtered[prop] = [i]
                    // add record of elements for current maxValue
                case let x where x == largest[prop]!:
                    filtered[prop]!.append(i)
                default: break
                }
                if filtered[prop]!.count == arr.count {
                    filtered[prop] = [arr[0]]
                }
            }
        }
    }
    // find the best mode for certain (but not all) condition
    // similar to Arrow's law, we DO NOT guarantee the mode is uniformly the best
    // but we do try to winnow out the bad modes ;)
    func computedBestMode() -> [Int] {
        let f = filtered["frequency"]!.filter { look(for: $0) }
        let r = filtered["kCGDisplayHorizontalResolution"]!.filter { look(for: $0) }
        
        switch (f.count, r.count) {
        case (0, 0): return []
        case (_, 0): return [ f[0] ]
        case (0, _): return [ r[0] ]
        default: return Array(Set(r).intersection(f))
        }
    }
    func computedBestMode(in modesFromJSON:[CGDisplayModeFromJSON], including index:Int?) -> [Int] {
        var bestMode = self.computedBestMode()
        if let modeIndex = index {
            if bestMode.allSatisfy({ modesFromJSON[modeIndex] ~= modesFromJSON[$0] }) {
                bestMode = [modeIndex]
            } else if !bestMode.contains(modeIndex) {
                bestMode.append(modeIndex)
            }
        }

        return bestMode
    }
    static func computedBestMode(in modesFromJSON:[CGDisplayModeFromJSON], withIndexArray arr:[Int], including index:Int?) -> [Int] {
        let sieve = Sieve.init(in: modesFromJSON, withIndexArray: arr)
        return sieve.computedBestMode(in: modesFromJSON, including: index)
    }

    private func look(for element:Int) -> Bool {
        return filtered["DepthFormat"]!.contains(element) && filtered["BitsPerSample"]!.contains(element)
    }
}



// DisplayMode & DisplayID management center
class DisplayManager {
    let displayID:CGDirectDisplayID,
        displayInfo:[MyDisplayMode],
        mode: CGDisplayMode
    
    init(_ displayID:CGDirectDisplayID) {
        self.displayID = displayID
        
        /* TODO: try memeory manipulation
         * https://stackoverflow.com/questions/8210824/
         * https://opensource.apple.com/source/IOGraphics/IOGraphics-406/IOGraphicsFamily/IOKit/graphics/IOGraphicsTypes.h.auto.html
         */
        self.mode = CGDisplayCopyDisplayMode(displayID)!

        let option = [kCGDisplayShowDuplicateLowResolutionModes:kCFBooleanTrue] as CFDictionary?
        let modes = (CGDisplayCopyAllDisplayModes(displayID, option) as! [CGDisplayMode])
            .filter { $0.isUsableForDesktopGUI() }
        
        let modeIndex = modes.firstIndex(of: mode)!
        
        guard let modesFromJSON = CGDisplayModeFromJSON.decode(from: modes, displayID: displayID) else {
            self.displayInfo = []
            return
        }
        let cursor = modesFromJSON[modeIndex]

        // group modes by `scale, width, height` and then carefully winnow out improper modes in each group
        let category = Dictionary(grouping: modesFromJSON.indices, by: { modesFromJSON[$0] })

        // key is only used to identify current mode setting
        let list = category.reduce(into:[]) { (list: inout [Int], arg) in
            list += Sieve.computedBestMode(in: modesFromJSON,
                                           withIndexArray: arg.1,
                                           including: arg.0 == cursor ? modeIndex : nil)
        }
      
        self.displayInfo = list
            .map { MyDisplayMode.init(mode:modes[$0],
                                      modeFromJSON:modesFromJSON[$0]) }
            .sorted { $0.modeFromJSON < $1.modeFromJSON }
    }
    
    private func _format(_ di:MyDisplayMode, leadingString:String, trailingString:String) -> String {
        let mo = di.modeFromJSON
        // We assume that 5 digits are enough to hold dimensions.
        // 100K monitor users will just have to live with a bit of formatting misalignment.
        return String(
            format:"  %@ %6d x %5d  @ %1dx %5dHz %7d %9d%@",
            leadingString,
            mo.Width, mo.Height,
            mo["scale"], mo["frequency"],
            mo["kCGDisplayHorizontalResolution"], mo["DepthFormat"],
            trailingString
        )
    }
    
    func printForOneDisplay(_ leadingString:String) {
        let di = displayInfo.filter { $0.mode == self.mode }
        print(_format(di[0], leadingString:leadingString, trailingString:""))
    }
    
    func printFormatForAllModes() {
        print("     Width x Height @ Scale Refresh Resolution  ColorDepth")
        
        displayInfo.forEach { di in
            let b = (di.mode == self.mode)
            print(_format(di, leadingString: b ? "\u{001B}[0;33m⮕" : " ", trailingString: b ? "\u{001B}[0;49m" : ""))
        }
    }
    
    func set(with setting: DisplayUserSetting) {
        print("setting", setting)
        // comparing DisplayUserSetting with DisplayInfo
        guard let di = displayInfo.last(where: { $0.modeFromJSON == setting }) else{
            print("This mode is unavailable")
            return
        }
        guard di.mode != self.mode else {
            //print("Setting the same mode.")
            return
        }
        print("Setting display mode")
        
        var config:CGDisplayConfigRef?
        
        let error:CGError = CGBeginDisplayConfiguration(&config)
        guard error == .success else {
            print(error)
            return
        }
        CGConfigureDisplayWithDisplayMode(config, displayID, di.mode, nil)
        
        let afterCheck = CGCompleteDisplayConfiguration(config, CGConfigureOption.permanently)
        if afterCheck != .success {
            print("setting failed")
            CGCancelDisplayConfiguration(config)
        }
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
    static let MAX_SCALE = 10
    
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
        
        if args[2] > DisplayUserSetting.MAX_SCALE {
            height = args[2]
            if args.count > 3 { scale = args[3] }
        }
        else {
            scale = args[2]
            if args.count > 3 { height = args[3] }
        }
    }
    
    // override a lesser-used operator to simplify display mode checks
    static func == (lhs: Self, rhs: CGDisplayModeFromJSON) -> Bool {
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
            let text = "(\(CGDisplayIsBuiltin(m.displayID) == 1 ? "Built-in" : "External") Display)"
            m.printForOneDisplay("Display \(i) \(text):")
        }
    }
    
    func listModes(_ i:Int) {
        let text = "(\(CGDisplayIsBuiltin(dm[i].displayID) == 1 ? "Built-in" : "External") Display)"
        print("Supported Modes for Display \(i) \(text):")
        dm[i].printFormatForAllModes()
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
    let wrangler = strdup("IOService:/IOResources/IODisplayWrangler")
    // for legacy system
    // current compile threshold is a ballpark guess, tested on Catalina only
#if compiler(<5.5)
    let flag = kIOMasterPortDefault
#else
    let flag = kIOMainPortDefault
#endif
    // https://github.com/glfw/glfw/issues/1985
    let r = IORegistryEntryFromPath(flag, wrangler)
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
            screens.listModes(displayIndex)
        } else {
            print("Display index not found. List all available displays by:\n    screen-resolution-switcher -l")
        }
    case "-s", "--set", "set", "-r", "--set-retina", "retina":
        screens.set(with:DisplayUserSetting( arguments ))
    case "-d", "--toggle-dark-mode":
        DarkMode().toggle()
    case "-sl", "--sleep", "sleep":
        //if #available(macOS 12.0, *) {
        sleepDisplay()
        //}
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
