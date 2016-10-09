#!/usr/bin/env xcrun swift

//
//  res.swift
//
//
//  Created by John Liu on 2014/10/02.
//0.	Program arguments: /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift -frontend -interpret ./scres.swift -target x86_64-apple-darwin13.4.0 -target-cpu core2 -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.10.sdk -color-diagnostics -module-name scres -- -s 0 1440
//

import Foundation

import ApplicationServices

import CoreVideo

func main () -> Void {
    let screens = ScreenAssets()
    
    guard screens.displayIDs != nil else {
        print("Unable to get displayIDs")
        return
    }
    
    let input = UserInput(arguments:CommandLine.arguments)
    
    // strip path and leave filename
    let binary_name = input.binary_name()
    
    // help message
    let help_msg = ([
        "usage: ",
        "\(binary_name) ",
        "[-h|--help] [-l|--list] [-m|--mode displayIndex] \n",
        "[-s|--set displayIndex width]",
        "\n\n",
        
        "Here are some examples:\n",
        "   -h          get help\n",
        "   -l          list displays\n",
        "   -m 0        list all mode from a certain display\n",
        "   -s 0 800    set resolution of display 0 to 800*600\n",
        ]).joined(separator:"")
    let help_display_list = "List all available displays by:\n    \(binary_name) -l"
    
    
    // dipatch functions
    switch input.intention {
    case .listDisplays:
        screens.listDisplays()
        return
    case .listModes:
        let displayIndex = Int( input.argument(at:2) ?? "0" )!
        
        guard displayIndex < screens.displayCount else {
            print("Display index( \(displayIndex) ) not found. \(help_display_list)")
            return
        }
        
        print("Supported Modes for Display \(displayIndex):")
        screens.display(at:displayIndex).showModes()
        
        return
    case .setMode:
        guard input.count > 2 else {
            print("Specify a display to set its mode. \(help_display_list)")
            return
        }

        // allow user to omit displayIndex if only one display is attached
        var displayIndex = input.argument(at:2)
        var designatedWidth = input.argument(at:3)
        
        guard let _index = UInt32(displayIndex!) else {
            print("Illegal display index")
            return
        }

        if designatedWidth == nil {
            if _index < screens.maxDisplays {
                print("Specify display width")
                return
            }
            else {
                guard screens.displayCount == 1 else {
                    print("Specify display index")
                    return
                }
                
                designatedWidth = displayIndex
                displayIndex = "0"
            }
        }
        
        guard let index = Int(displayIndex!), let width = Int(designatedWidth!) else {
            print("Unable to get display")
            return
        }

        let display = screens.display(at:index)
        
        guard let modeIndex = display.mode(width:width) else {
            print("This mode is unavailable for current desktop GUI")
            return
        }
        
        print("setting display mode")

        display.set(modeIndex:modeIndex)
        return
    default:
        print(help_msg)
    }
}

struct UserInput {
    enum Intention {
        case listDisplays
        case listModes
        case setMode
        case seeHelp
    }
    
    var intention:Intention
    
    var arguments:[String]
    var count:Int
    
    init(arguments:[String]) {
        self.arguments = arguments
        self.count = arguments.count
        if self.count < 2 {
            intention = Intention.seeHelp
            return
        }
        switch arguments[1] {
        case "-l", "--list":
            intention = Intention.listDisplays
        case "-m", "--mode":
            intention = Intention.listModes
        case "-s", "--set":
            intention = Intention.setMode
        default:
            intention = Intention.seeHelp
        }
    }
    
    func argument(at:Int) -> String? {
        if at < self.count {
            return self.arguments[at]
        }
        
        return nil
    }
    
    // Swift String is quite powerless at the moment
    // http://stackoverflow.com/questions/24044851
    // http://openradar.appspot.com/radar?id=6373877630369792
    func binary_name() -> String {
        var raw_name = self.argument(at:0)!
        
        var substring = ""
        for (_, c) in raw_name.characters.reversed().enumerated() {
            if (c == "/") {
                break
            }
            substring = String(c) + substring
        }
        
        return substring
    }
}


class ScreenAssets {
    // assume at most 8 display connected
    var maxDisplays:UInt32 = 8
    // actual number of display
    var displayCount:Int = 0
    
    var displayIDs:UnsafeMutablePointer<CGDirectDisplayID>?
    //var onlineDisplayIDs = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity:Int(maxDisplays))
    
    init() {
        // actual number of display
        var displayCount32:UInt32 = 0
        let displayIDsPrealloc = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity:Int(maxDisplays))

        
        let error:CGError = CGGetOnlineDisplayList(maxDisplays, displayIDsPrealloc, &displayCount32)
        
        if (error != .success) {
            print("Error on getting online display List.")
            return
        }
        
        displayCount = Int(displayCount32)
        displayIDs = displayIDsPrealloc
    }
    
    // print a list of all displays
    // used by -l
    func listDisplays() {
        if let displayIDs = self.displayIDs {
            for i in 0..<self.displayCount {
                let di = DisplayInfo(displayIDs[i])
                print("Display \(i):  \(di.width) * \(di.height) @ \(di.frequency)Hz")
            }
        }
    }
    
    func display(at:Int) -> DisplayUtil {
        return DisplayUtil(displayIDs![at])
    }
}

class DisplayUtil {
    var displayID:CGDirectDisplayID
    
    init(_ _displayID:CGDirectDisplayID) {
        displayID = _displayID
    }
    
    func showModes() {
        if let modes = self.modes() {
            let nf = NumberFormatter()
            nf.paddingPosition = NumberFormatter.PadPosition.beforePrefix
            nf.paddingCharacter = " " // XXX: Swift does not support padding yet
            nf.minimumIntegerDigits = 3 // XXX
            
            for (_, m) in modes.enumerated() {
                let di = DisplayInfo(displayID:displayID, mode:m)
                print("       \(di.width) * \(di.height) @ \(di.frequency)Hz")
            }
        }
    }
    
    func modes() -> [CGDisplayMode]? {
        if let modeList = CGDisplayCopyAllDisplayModes(displayID, nil) {
            var modesArray = [CGDisplayMode]()
            
            let count = CFArrayGetCount(modeList)
            for i in 0..<count {
                let modeRaw = CFArrayGetValueAtIndex(modeList, i)
                // https://github.com/FUKUZAWA-Tadashi/FHCCommander
                let mode = unsafeBitCast(modeRaw, to:CGDisplayMode.self)
                
                modesArray.append(mode)
            }
            
            return modesArray
        }
        
        return nil
    }
    
    func mode(width:Int) -> Int? {
        var index:Int?
        if let modesArray = self.modes() {
            for (i, m) in modesArray.enumerated() {
                let di = DisplayInfo(displayID:displayID, mode:m)
                if di.width == width {
                    index = i
                    break
                }
            }
        }
        
        return index
    }
    
    func set(mode:CGDisplayMode) -> Void {
        if mode.isUsableForDesktopGUI() == false {
            print("This mode is unavailable for current desktop GUI")
            return
        }
        
        let config = UnsafeMutablePointer<CGDisplayConfigRef?>.allocate(capacity:1)
        
        let error = CGBeginDisplayConfiguration(config)
        if error == .success {
            let option:CGConfigureOption = CGConfigureOption(rawValue:2) //XXX: permanently
            
            CGConfigureDisplayWithDisplayMode(config.pointee, displayID, mode, nil)
            
            let afterCheck = CGCompleteDisplayConfiguration(config.pointee, option)
            if afterCheck != .success {
                CGCancelDisplayConfiguration(config.pointee)
            }
        }
    }
    
    func set(modeIndex:Int) {
        guard let modes = self.modes(), modeIndex < modes.count else {
            return
        }
        
        self.set(mode:modes[modeIndex])
    }
    
}

// return with, height and frequency info for corresponding displayID
struct DisplayInfo {
    var width, height, frequency:Int
    
    init() {
        width = 0
        height = 0
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
        
        var _frequency = Int( mode.refreshRate )
        
        if _frequency == 0 {
            var link:CVDisplayLink?
            
            CVDisplayLinkCreateWithCGDisplay(displayID, &link)
            
            let time:CVTime = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!)
            
            // timeValue is in fact already in Int64
            let timeValue = time.timeValue as Int64
            
            // a hack-y way to do ceil
            let timeScale = Int64(time.timeScale) + timeValue / 2
            
            _frequency = Int( timeScale / timeValue )
        }
        
        frequency = _frequency
    }
}


// run it
main()
