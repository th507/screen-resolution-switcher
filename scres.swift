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
        var str = self
        while let range = str.rangeOfString(needle) {
            let index2 = range.startIndex.advancedBy(1)
            let range2 = Range<String.Index>(index2..<str.endIndex)
            str = str.substringWithRange(range2)
        }
        return str
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
var onlineDisplayIDs = UnsafeMutablePointer<CGDirectDisplayID>.alloc(Int(maxDisplays))

func main () -> Void {
    let error:CGError = CGGetOnlineDisplayList(maxDisplays, onlineDisplayIDs, &displayCount32)
    
    if (error != .Success) {
		print("Error on getting online display List.");
        return
    }

    let displayCount:Int = Int(displayCount32)


    // strip path and leave filename
    let binary_name = Process.arguments[0].substringFromLastOcurrenceOf("/")

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
                ]).joinWithSeparator("")
    let help_display_list = "List all available displays by:\n    \(binary_name) -l"
    

    let argc = Process.arguments.count
    if argc > 1 {
        if Process.arguments[1] == "-l" || Process.arguments[1] == "--list" {
            listDisplays(onlineDisplayIDs, count:displayCount)
            return
        }

        if Process.arguments[1] == "-m" || Process.arguments[1] == "--mode" {
            if argc < 3 {
                print("Specify a display to see its supported modes. \(help_display_list)")
                return
            }

            if let displayIndex = Int(Process.arguments[2]) {
                if displayIndex < displayCount {
                    let _info = listModesByDisplayID(onlineDisplayIDs[displayIndex]) 
                    displayModes(onlineDisplayIDs[displayIndex], index:displayIndex, _modes:_info)
                    
                } else {
                    print("Display index: \(displayIndex) not found. \(help_display_list)")
                }
            } else {
                print("Display index should be a number. \(help_display_list)")
            }
            return
        }

        if Process.arguments[1] == "-s" || Process.arguments[1] == "--set" {
            if argc < 3 {
                print("Specify a display to set its mode. \(help_display_list)")
                return
            }

            if argc < 4 {
                print("Specify display width")
                return
            }


            if let displayIndex = Int(Process.arguments[2]) {
                if displayIndex < displayCount {
                    if let designatedWidth = Process.arguments[3].toUInt() {
                        if let modesArray = listModesByDisplayID(onlineDisplayIDs[displayIndex]) {
                            var designatedWidthIndex:Int?
                            for i in 0..<modesArray.count {
                                let di = displayInfo(onlineDisplayIDs[displayIndex], mode:modesArray[i])
                                if di.width == designatedWidth {
                                    designatedWidthIndex = i
                                    break
                                }
                            }
                            if designatedWidthIndex != nil {
                                print("setting display mode")
                                setDisplayMode(onlineDisplayIDs[displayIndex], mode:modesArray[designatedWidthIndex!], designatedWidth:designatedWidth)
                            }
                            else {
                                print("This mode is unavailable for current desktop GUI")
                            }
                        }
                    }
                } else {
                    print("Display index: \(displayIndex) not found. \(help_display_list)")
                }                
            }
            
            return
        }

        
    }
        
    print(help_msg)
}

func setDisplayMode(display:CGDirectDisplayID, mode:CGDisplayMode, designatedWidth:UInt) -> Void {
    if CGDisplayModeIsUsableForDesktopGUI(mode) {
    
        let config = UnsafeMutablePointer<CGDisplayConfigRef>.alloc(1);
    
        let error = CGBeginDisplayConfiguration(config)
        if error == .Success {
            if nil != config {
                let option:CGConfigureOption = CGConfigureOption(rawValue:2) //XXX: permanently
                CGConfigureDisplayWithDisplayMode(config.memory, display, mode, nil)
                let afterCheck = CGCompleteDisplayConfiguration(config.memory, option)
                if afterCheck != .Success {
                    CGCancelDisplayConfiguration(config.memory)
                }
            } else {
                print("Setting display mode failed")
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
                let mode = unsafeBitCast(modeRaw, CGDisplayMode.self)

                modesArray.append(mode)
            }

            return modesArray
        }
    }
    return nil
}

func displayModes(_display:CGDirectDisplayID?, index:Int, _modes:[CGDisplayMode]?) -> Void {
    if let display = _display {
        if let modes = _modes {
            print("Supported Modes for Display \(index):")
            
            let nf = NSNumberFormatter()
            nf.paddingPosition = NSNumberFormatterPadPosition.BeforePrefix
            nf.paddingCharacter = " " // XXX: Swift does not support padding yet
            nf.minimumIntegerDigits = 3 // XXX

            for i in 0..<modes.count {
                let di = displayInfo(display, mode:modes[i])
                print("       \(nf.stringFromNumber(di.width)!) * \(nf.stringFromNumber(di.height)!) @ \(di.frequency)Hz")
            }
        }
    }
}

// print a list of all displays
// used by -l
func listDisplays(displayIDs:UnsafeMutablePointer<CGDirectDisplayID>, count:Int) -> Void {
    for i in 0..<count {
        let di = displayInfo(displayIDs[i], mode:nil)
        print("Display \(i):  \(di.width) * \(di.height) @ \(di.frequency)Hz")
    }
}


struct DisplayInfo {
    var width:UInt, height:UInt, frequency:UInt
}
// return with, height and frequency info for corresponding displayID
func displayInfo(display:CGDirectDisplayID, mode:CGDisplayMode?) -> DisplayInfo {
    var mode_ = mode
    if mode_ == nil {
        mode_ = CGDisplayCopyDisplayMode(display)!
    }
    
    let width = UInt( CGDisplayModeGetWidth(mode) )
    let height = UInt( CGDisplayModeGetHeight(mode) )
    var frequency = UInt( CGDisplayModeGetRefreshRate(mode) )

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

// run it
main()
