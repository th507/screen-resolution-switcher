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

// from https://medium.com/swlh/f6ea6a2babf8
// for dealing with CGDisplayModeFromJSON.RefreshRate, which return String or Double 0 in various settings
// this can be retrieved by printing CGDisplayMode
struct CGDisplayModeFromJSON: Decodable {
  var BitsPerPixel = 32;
  var BitsPerSample = 8;
  var DepthFormat = 4;
  var Height = 2160;
  var IODisplayModeID = "-2147454976";
  var IOFlags = 1048579;
  var Mode = 0;
  var PixelEncoding = "--------RRRRRRRRGGGGGGGGBBBBBBBB";
  // making a type augmentation as program return String or 0 in various settings
  var RefreshRate:StringOrDouble// = "30.00001525878906";
  var SamplesPerPixel = 3;
  var UsableForDesktopGUI = 1;
  var Width = 3840;
  var kCGDisplayBytesPerRow = 15360;
  var kCGDisplayHorizontalResolution = 163;
  var kCGDisplayModeIsInterlaced = 0;
  var kCGDisplayModeIsSafeForHardware = 1;
  var kCGDisplayModeIsStretched = 0;
  var kCGDisplayModeIsTelevisionOutput = 1;
  var kCGDisplayModeIsUnavailable = 0;
  var kCGDisplayModeSuitableForUI = 1;
  var kCGDisplayPixelsHigh = 2160;
  var kCGDisplayPixelsWide = 3840;
  var kCGDisplayResolution = 1;
  var kCGDisplayVerticalResolution = 163;
  var frequency:Int?
}
// use the object as key in a later process of mode filtering/winnowing
extension CGDisplayModeFromJSON: Hashable & Equatable & Comparable {
  enum StringOrDouble: Decodable {
    case double(Double)//,string(String)
    
    init(from decoder: Decoder) throws {
      // RefreshRate is a String with quotation marks but representing a Double
      if let string = try? decoder.singleValueContainer().decode(String.self) {
        self = .double(Double(string) ?? 0)
        return
      }
      // RefreshRate is 0 without quotation marks, and will decode into a Double
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

  func hash(into hasher: inout Hasher) {
    hasher.combine(Width)
    hasher.combine(Height)
    hasher.combine(kCGDisplayPixelsWide)
    hasher.combine(kCGDisplayPixelsHigh)
  }
  func debug() -> String {
    return "s:\(self["scale"]),w:\(self.Width),h:\(self.Height)"
  }
  static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.Width == rhs.Width && lhs.kCGDisplayPixelsWide == rhs.kCGDisplayPixelsWide &&
          lhs.Height == rhs.Height && lhs.kCGDisplayPixelsHigh == rhs.kCGDisplayPixelsHigh
  }
  static func ~=(lhs: Self, rhs: Self) -> Bool {
    return lhs == rhs && lhs["frequency"] == rhs["frequency"] && 
      lhs["kCGDisplayHorizontalResolution"] == rhs["kCGDisplayHorizontalResolution"]
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    let ls = lhs["scale"]
    let rs = rhs["scale"]
    return ls != rs ? ls < rs : lhs.Width < rhs.Width
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
        case "frequency":
          return self.frequency!
          /*if let frequency = self.frequency { return frequency }
          switch self.RefreshRate {
          //case StringOrDouble.string(let s): return Int( Double(s)?.rounded() ?? 0)
          case StringOrDouble.double(let d): return Int( d.rounded() )
          }*/
        //case "displayID": return self.displayID
        default: return 0
      }
    }
  }
  
  func getRefreshRate(by displayID:CGDirectDisplayID) -> Int {
    if let f = self.frequency { return f }
    
    let frequency:Int
    switch self.RefreshRate {
      //case StringOrDouble.string(let s): return Int( Double(s)?.rounded() ?? 0)
      case StringOrDouble.double(let d): frequency = Int( d.rounded() )
    }

    guard frequency != 0 else { return frequency }

    var link:CVDisplayLink?
    CVDisplayLinkCreateWithCGDisplay(displayID, &link)
    
    let time = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!)
    // timeValue is in fact already in Int64
    let timeScale = Int64(time.timeScale) + time.timeValue / 2
    
    return Int( timeScale / time.timeValue )
  }

  // this is a hack to read private members in CGDisplayMode
  static func decode(from modes:[CGDisplayMode]) -> [CGDisplayModeFromJSON]? {
    do {
      // first we operate the string to make it look like JSON String
      let modesJSONText = try CGDisplayModeFromJSON.replaces(in: String(reflecting:modes), replacement: self.replacement)

      // then we try to decode it as JSON
      let decoder = JSONDecoder()
      let modesObject = try decoder.decode([CGDisplayModeFromJSON].self, from: modesJSONText.data(using: .utf8)!)


      // preliminary integrity check
      guard modesObject.count == modes.count else { return nil }

      return modesObject
    } catch {
      // TODO: catch error and warn user properly
      print(error)
      return nil
    }
  }

  // for JSON hacking
  static private let replacement = [
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
  // for JSON hacking
  static private func replaces(in str:String, replacement: [String:String]) throws -> String {
    var out = str
    for (key, value) in replacement {
        let range = NSRange(out.startIndex..<out.endIndex, in:out)
        let r = try NSRegularExpression(pattern: key, options: [])
        out = r.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: value)
    }
    // TODO: investigate why replacement fails
    return out + "]"
  }

}
  // utility functions in CGDisplayMode filtering
  struct Sieve {
    let propertyList = ["frequency", "kCGDisplayHorizontalResolution", "DepthFormat", "BitsPerSample"]
    var largest:[String:Int]
    var filtered:[String:[Int]]
    
    init() {
      largest = [String:Int]()
      filtered = [String:[Int]]()
      for prop in propertyList {
        largest[prop] = 0
        filtered[prop] = []
      }
    }

    // invoking maxValue update & record-keeping
    mutating func findMaxValueAndIndices(in modesObject:[CGDisplayModeFromJSON], withIndexArray arr:[Int]) {
      for prop in propertyList {
        arr.forEach { i in
          switch modesObject[i][prop] {
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

    private func look(for element:Int) -> Bool {
      return filtered["DepthFormat"]!.contains(element) && filtered["BitsPerSample"]!.contains(element)
    }

    // find the best mode for certain (but not all) condition
    // similar to Arrow's law, we DO NOT guarantee the mode is uniformly the best
    // but we do try to winnow out the bad modes ;)
    subscript(index:String) -> [Int] {
      get {
        switch index {
        case "bestModeByRefreshRate": return filtered["frequency"]!.filter { look(for: $0) }
        case "bestModeByResolution": return filtered["kCGDisplayHorizontalResolution"]!.filter { look(for: $0) }
        case "bestMode": return Array(Set(self["bestModeByResolution"]).intersection(self["bestModeByRefreshRate"]))
        default: return [0]
        }
      }
    }
  }

// return width, height and frequency info for corresponding displayID
// TODO: eliminate the use of DisplayInfo in favor of the newer, and more informative CGDisplayModeFromJSON
struct DisplayInfo: Comparable & Equatable {
  var width, height, scale, frequency, resolution:Int
  var bps, depth:Int
  var modeID:Int32
  var mode:CGDisplayMode
  //var colorDepth, resolution:Int

  init(displayID:CGDirectDisplayID, modeFromJSON:CGDisplayModeFromJSON, mode:CGDisplayMode) {
    width = modeFromJSON.Width
    height = modeFromJSON.Height
    resolution = modeFromJSON.kCGDisplayHorizontalResolution
    modeID = Int32(modeFromJSON.IODisplayModeID)!
    depth = modeFromJSON.DepthFormat
    bps = modeFromJSON.BitsPerSample
    
    self.mode = mode
    scale = modeFromJSON["scale"]        
    frequency = modeFromJSON["frequency"]
  }
  // TODO: get rid of it,since we are not comparing DisplayInfo
  static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.scale != rhs.scale ? lhs.scale < rhs.scale : lhs.width < rhs.width
  }

  static func == (lhs: Self, rhs: DisplayUserSetting) -> Bool {
    var bool = rhs.width == lhs.width

    if rhs.height != nil { bool = bool && rhs.height == lhs.height }
    if rhs.scale != nil { bool = bool && rhs.scale == lhs.scale }
    return bool
  }

}


// DisplayMode & DisplayID management center
class DisplayManager {
  let displayID:CGDirectDisplayID,
      displayInfo:[DisplayInfo],
      modeID:Int32,
      mode: CGDisplayMode

  init(_ displayID:CGDirectDisplayID) {
    self.displayID = displayID
    
    /*
     //https://stackoverflow.com/questions/8210824/how-to-avoid-cgdisplaymodecopypixelencoding-to-get-bpp
     */
    //omitting `self.` prefix
    mode = CGDisplayCopyDisplayMode(displayID)!
    modeID = mode.ioDisplayModeID

    let option = [kCGDisplayShowDuplicateLowResolutionModes:kCFBooleanTrue] as CFDictionary?
    let modes = (CGDisplayCopyAllDisplayModes(displayID, option) as! [CGDisplayMode])
        .filter { $0.isUsableForDesktopGUI() }
    
    let modeIndex = modes.firstIndex(of: mode)!
     
    guard var modesObject = CGDisplayModeFromJSON.decode(from: modes) else {
      self.displayInfo = []
      return
    }

    for i in 0..<modesObject.count {
      modesObject[i].frequency = modesObject[i].getRefreshRate(by:displayID)
    }
   

    //print(modes[0], displayID)

    //let mfd = ModesForDisplay(displayID, modesFromJSON:modesObject, currentModeIndex:modeIndex)

    // group modes by `scale, width, height` and then carefully winnow out improper modes in each group            
    let category = Array(0..<modesObject.count).reduce(into:[:]) { (category: inout [CGDisplayModeFromJSON:[Int]], i) in
      category[modesObject[i], default: []].append(i)
    }
    
    let cursor = modesObject[modeIndex]
    
    var shortlist = [CGDisplayModeFromJSON:[Int]]()
    // key is only used to identify current mode setting
    for (key, arr) in category {
      var sieve = Sieve.init()

      sieve.findMaxValueAndIndices(in: modesObject, withIndexArray: arr)

      var bestMode = sieve["bestMode"]
      if key == cursor {
        if bestMode.allSatisfy({ modesObject[modeIndex] == modesObject[$0] }) {
          bestMode = [modeIndex]
        } else if !bestMode.contains(modeIndex) {
          bestMode.append(modeIndex)
        }
      }
      shortlist[key] = bestMode
    }

    self.displayInfo = shortlist.values
      .flatMap {$0}
      .map { DisplayInfo(displayID: displayID, modeFromJSON: modesObject[$0], mode: modes[$0]) }
      .sorted()
  }
  
  private func _format(_ di:DisplayInfo, leadingString:String, trailingString:String) -> String {
    // We assume that 5 digits are enough to hold dimensions.
    // 100K monitor users will just have to live with a bit of formatting misalignment.
    return String(
      format:"  %@ %6d x %5d  @ %1dx %5dHz %7d %9d%@",
      leadingString,
      di.width, di.height,
      di.scale, di.frequency,
      di.resolution, di.depth, 
      trailingString
    )
  }
  
  func printForOneDisplay(_ leadingString:String) {
    let di = displayInfo.filter { $0.modeID == modeID }
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
    guard let di = displayInfo.last(where: { setting == $0 }) else{
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
    CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
                
    let afterCheck = CGCompleteDisplayConfiguration(config, CGConfigureOption.permanently)
    if afterCheck != .success { CGCancelDisplayConfiguration(config) }
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
