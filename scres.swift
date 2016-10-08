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



// Swift String is quite powerless at the moment
// http://stackoverflow.com/questions/24044851
// http://openradar.appspot.com/radar?id=6373877630369792
extension String {
    func substringFromLastOcurrenceOf(needle:String) -> String {
        var substring = String.init()
        for (_, c) in self.characters.enumerated() {
            substring.append(c)
            
            if (c == "/") {
                substring.removeAll()
            }
        }

        return substring
    }

    func toUInt() -> UInt? {
        if let num = Int(self) {
            return UInt(num)
        }
        return nil
    }
}

// assume at most 8 display connected 
var maxDisplays:UInt32 = 8
// actual number of display
var displayCount32:UInt32 = 0

// store displayID in an raw array
var onlineDisplayIDs = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity:Int(maxDisplays))

func main () -> Void {
    let error:CGError = CGGetOnlineDisplayList(maxDisplays, onlineDisplayIDs, &displayCount32)
    
    if (error != .success) {
		print("Error on getting online display List.");
        return
    }

    let displayCount:Int = Int(displayCount32)
    
    let argv = CommandLine.arguments
    let argc = argv.count

    // strip path and leave filename
    let binary_name = argv[0].substringFromLastOcurrenceOf(needle:"/")

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
    

    if argc > 1 {
        if argv[1] == "-l" || argv[1] == "--list" {
            listDisplays(displayIDs:onlineDisplayIDs, count:displayCount)
            return
        }

        if argv[1] == "-m" || argv[1] == "--mode" {
            if argc < 3 {
                print("Specify a display to see its supported modes. \(help_display_list)")
                return
            }

            if let displayIndex = Int(argv[2]) {
                if displayIndex < displayCount {
                    let _info = listModesByDisplayID(_displayID:onlineDisplayIDs[displayIndex])
                    PrintDisplayModes(_display:onlineDisplayIDs[displayIndex], index:displayIndex, _modes:_info)
                    
                } else {
                    print("Display index: \(displayIndex) not found. \(help_display_list)")
                }
            } else {
                print("Display index should be a number. \(help_display_list)")
            }
            return
        }

        
        
        if argv[1] == "-s" || argv[1] == "--set" {
            if argc < 3 {
                print("Specify a display to set its mode. \(help_display_list)")
                return
            }

            var singleDisplayMode = false

            
            if  var displayIndex = Int(argv[2]) {
                if argc < 4 {
                    if displayIndex < 10 {
                        print("Specify display width")
                        return
                    } else {
                        if (displayCount == 1) {
                            singleDisplayMode = true
                        } else {
                            print("Specify display index")
                            return
                        }
                    }
                }
                let designatedWidthOptional: UInt?
                
                if singleDisplayMode == true {
                    displayIndex = 0
                    designatedWidthOptional = argv[2].toUInt()
                    
                }
                
                else {
                    if displayIndex >= displayCount {
                        print("Display index: \(displayIndex) not found. \(help_display_list)")
                        return
                    }
                    
                    designatedWidthOptional = argv[3].toUInt()
                }
                
                if let designatedWidth = designatedWidthOptional {
                    if let modesArray = listModesByDisplayID(_displayID:onlineDisplayIDs[displayIndex]) {
                        var designatedWidthIndex:Int?
                        for i in 0..<modesArray.count {
                            if let di = displayInfo(display:onlineDisplayIDs[displayIndex], mode:modesArray[i]) {
                                if di.width == designatedWidth {
                                    designatedWidthIndex = i
                                    break
                                }
                            }
                        }
                        if designatedWidthIndex != nil {
                            print("setting display mode")
                            setDisplayMode(display:onlineDisplayIDs[displayIndex], mode:modesArray[designatedWidthIndex!], designatedWidth:designatedWidth)
                        }
                        else {
                            print("This mode is unavailable for current desktop GUI")
                        }
                    }
                }
            }
            
            return
        }

        
    }
        
    print(help_msg)
}

func setDisplayMode(display:CGDirectDisplayID, mode:CGDisplayMode, designatedWidth:UInt) -> Void {
    if mode.isUsableForDesktopGUI() {
    
        let config = UnsafeMutablePointer<CGDisplayConfigRef?>.allocate(capacity:1);
    
        let error = CGBeginDisplayConfiguration(config)
        if error == .success {
            let option:CGConfigureOption = CGConfigureOption(rawValue:2) //XXX: permanently
            
            CGConfigureDisplayWithDisplayMode(config.pointee, display, mode, nil)
            let afterCheck = CGCompleteDisplayConfiguration(config.pointee, option)
            if afterCheck != .success {
                CGCancelDisplayConfiguration(config.pointee)
            }
        }
    } else {
        print("This mode is unavailable for current desktop GUI")
    }
}

// list mode by display id
func listModesByDisplayID(_displayID:CGDirectDisplayID?) -> [CGDisplayMode]? {
    if let displayID = _displayID {
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
    }
    return nil
}

func PrintDisplayModes(_display:CGDirectDisplayID?, index:Int, _modes:[CGDisplayMode]?) -> Void {
    if let display = _display {
        if let modes = _modes {
            print("Supported Modes for Display \(index):")
            
            let nf = NumberFormatter()
            nf.paddingPosition = NumberFormatter.PadPosition.beforePrefix
            nf.paddingCharacter = " " // XXX: Swift does not support padding yet
            nf.minimumIntegerDigits = 3 // XXX

            for i in 0..<modes.count {
                if let di = displayInfo(display:display, mode:modes[i]) {
                    print("       \(di.width) * \(di.height) @ \(di.frequency)Hz")
                }
            }
        }
    }
}

// print a list of all displays
// used by -l
func listDisplays(displayIDs:UnsafeMutablePointer<CGDirectDisplayID>, count:Int) -> Void {
    for i in 0..<count {
        if let di = displayInfo(display:displayIDs[i], mode:nil) {
            print("Display \(i):  \(di.width) * \(di.height) @ \(di.frequency)Hz")
        }
    }
}


struct DisplayInfo {
    var width:UInt, height:UInt, frequency:UInt
}
// return with, height and frequency info for corresponding displayID
func displayInfo(display:CGDirectDisplayID, mode:CGDisplayMode?) -> DisplayInfo? {
    var mode_ = mode
    if mode_ == nil {
        mode_ = CGDisplayCopyDisplayMode(display)
    }
    
    if let mode__ = mode_ {
        let width = UInt( mode__.width )
        let height = UInt( mode__.height )
        var frequency = UInt( mode__.refreshRate )
        
        if frequency == 0 {
            var link:CVDisplayLink?
            
            CVDisplayLinkCreateWithCGDisplay(display, &link)
            
            let time:CVTime = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!)
            
            // timeValue is in fact already in Int64
            let timeValue = time.timeValue as Int64
            
            // a hack-y way to do ceil
            let timeScale = Int64(time.timeScale) + timeValue / 2
            
            frequency = UInt( timeScale / timeValue )
        }
        
        return DisplayInfo(width:width, height:height, frequency:frequency)
    }
    return nil
}

// run it
main()
