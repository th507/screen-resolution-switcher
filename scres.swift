#!/usr/bin/env xcrun swift

//
//  scres.swift
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

    let input = UserInput(CommandLine.arguments)
    
    // strip path and leave filename
    let binary_name = input.binary_name()
    
    // help message
    let help_msg = ([
        "usage: ",
        "\(binary_name) ",
        "[-h|--help] [-l|--list|list] [-m|--mode|mode displayIndex] \n",
        "[-s|--set|set displayIndex width scale]",
        "[-r|--set-retina|retina displayIndex width]",
        "\n\n",
        
        "Here are some examples:\n",
        "   -h          get help\n",
        "   -l          list displays\n",
        "   -m 0        list all mode from a certain display\n",
        "   -s 0 800    set resolution of display 0 to 800 [x 600] \n",
        "   -s 800      shorthand for -s 0 800 \n",
        "   -s 0 800 2  set resolution of display 0 to 800 [x 600] @ 2x [@ 60Hz]\n",
        "   -r 0 800    shorthand for -s 0 800 2\n",
        "   -r 800      shorthand for -s 0 800 2\n",
        ]).joined(separator:"")
    let help_display_list = "List all available displays by:\n    \(binary_name) -l"
    
    var defaultDesignatedScale = "1";
    
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
        screens.display(at:displayIndex).showModes()
        
    case .setRetina:
        defaultDesignatedScale = "2"
        fallthrough
    case .setMode:
        guard input.count > 2 else {
            print("Specify a display to set its mode. \(help_display_list)")
            return
        }

        // allow user to omit displayIndex if only one display is attached
        var displayIndex = input.argument(at:2)
        var designatedWidth = input.argument(at:3)
        var designatedScale = input.argument(at:4)
        
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

        if designatedScale == nil {
            designatedScale = defaultDesignatedScale
        }

        guard let index = Int(displayIndex!), let width = Int(designatedWidth!), let scale = Int(designatedScale!) else {
            print("Unable to get display")
            return
        }

        let display = screens.display(at:index)

        print("Attempting to set resolution matching: \(width) x ____ @ \(scale)x @ __Hz")
        
        guard let modeIndex = display.mode(width:width, scale:scale) else {
            print("This mode is unavailable for current desktop GUI")
            return
        }
        
        print("Setting display mode")

        display.set(modeIndex:modeIndex)
        
    default:
        print(help_msg)
    }
}

struct UserInput {
    enum Intention {
        case listDisplays
        case listModes(Int)
        case setMode
        case setRetina
        case seeHelp
    }
    
    var intention:Intention
    
    var arguments:[String]
    var count:Int
    
    init(_ arguments:[String]) {
        self.arguments = arguments
        self.count = arguments.count
        if self.count < 2 {
            intention = Intention.seeHelp
            return
        }
        switch arguments[1] {
        case "-l", "--list", "list":
            intention = Intention.listDisplays
        case "-m", "--mode", "mode":
            if self.count == 2 {
                intention = Intention.listModes(0)
            }
            else {
                if let displayIndex = Int(self.arguments[2]) {
                    intention = Intention.listModes(displayIndex)
                }
                else {
                    intention = Intention.listModes(0)
                }
            }
            
        case "-s", "--set", "set":
            intention = Intention.setMode
        case "-r", "--set-retina", "retina":
            intention = Intention.setRetina
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
        let absolutePath = self.argument(at:0)!

        if let range = absolutePath.range(of: "/", options: .backwards) {
            return String( absolutePath[range] )
        }
        return absolutePath
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
                print("Display \(i):  \(di.format())")
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
            for (_, m) in modes.enumerated() {
                let di = DisplayInfo(displayID:displayID, mode:m)
                print("       \(di.format())")
            }
        }
    }
    
    func modes() -> [CGDisplayMode]? {

        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes as String : 1] as CFDictionary

        if let modeList = CGDisplayCopyAllDisplayModes(displayID, options) {
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
    
    func mode(width:Int, scale:Int) -> Int? {
        var index:Int?
        if let modesArray = self.modes() {
            for (i, m) in modesArray.enumerated() {
                let di = DisplayInfo(displayID:displayID, mode:m)
                if di.width == width && di.scale == scale {
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

    func format() -> String {
        // We assume that 4 digits are enough to hold dimensions.
        // 10K monitor users will just have to live with a bit of formatting misalignment.
        return String(
            format:"%4d x %4d @ %dx @ %dHz",
            width,
            height,
            scale,
            frequency
        )
    }
}


// run it
main()
