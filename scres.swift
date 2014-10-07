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

enum MyCGError:Int32 {
    case kCGErrorSuccess = 0
    case kCGErrorFailure = 1000
}

// Swift String is quite powerless at the moment
// http://stackoverflow.com/questions/24044851
// http://openradar.appspot.com/radar?id=6373877630369792
extension String {
    func substringFromLastOcurrenceOf(var needle:String) -> String {
        var str = self
        while var range = str.rangeOfString(needle) {
            var index2 = advance(range.startIndex, 1)
            var range2 = Range<String.Index>(start: index2, end: str.endIndex)
            str = str.substringWithRange(range2)
        }
        return str
    }

    func toUInt() -> UInt? {
        if let num = self.toInt() {
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
    var error:CGError = CGGetOnlineDisplayList(maxDisplays, onlineDisplayIDs, &displayCount32)
    
    if (error != MyCGError.kCGErrorSuccess.rawValue) {
		println("Error on getting online display List.");
        return
    }

    let displayCount:Int = Int(displayCount32)


    // strip path and leave filename
    var binary_name = Process.arguments[0].substringFromLastOcurrenceOf("/")

    // help message
    var help_msg = "".join([
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
                ])
    var help_display_list = "List all available displays by:\n    \(binary_name) -l"
    

    let argc = Process.arguments.count
    if argc > 1 {
        if Process.arguments[1] == "-l" || Process.arguments[1] == "--list" {
            listDisplays(onlineDisplayIDs, displayCount)
            return
        }

        if Process.arguments[1] == "-m" || Process.arguments[1] == "--mode" {
            if argc < 3 {
                println("Specify a display to see its supported modes. \(help_display_list)")
                return
            }

            if let displayIndex = Process.arguments[2].toInt() {
                if displayIndex < displayCount {
                    let _info = listModesByDisplayID(onlineDisplayIDs[displayIndex]) 
                    displayModes(onlineDisplayIDs[displayIndex], displayIndex, _info)
                    
                } else {
                    println("Display index: \(displayIndex) not found. \(help_display_list)")
                }
            } else {
                println("Display index should be a number. \(help_display_list)")
            }
            return
        }

        if Process.arguments[1] == "-s" || Process.arguments[1] == "--set" {
            if argc < 3 {
                println("Specify a display to set its mode. \(help_display_list)")
                return
            }

            if argc < 4 {
                println("Specify display width")
                return
            }


            if let displayIndex = Process.arguments[2].toInt() {
                if displayIndex < displayCount {
                    if let designatedWidth = Process.arguments[3].toUInt() {
                        if let modesArray = listModesByDisplayID(onlineDisplayIDs[displayIndex]) {
                            var designatedWidthIndex:Int?
                            for i in 0..<modesArray.count {
                                var di = displayInfo(onlineDisplayIDs[displayIndex], modesArray[i])
                                if di.width == designatedWidth {
                                    designatedWidthIndex = i
                                    break
                                }
                            }
                            if designatedWidthIndex != nil {
                                println("setting display mode")
                                setDisplayMode(onlineDisplayIDs[displayIndex], modesArray[designatedWidthIndex!], designatedWidth)
                            }
                            else {
                                println("This mode is unavailable for current desktop GUI")
                            }
                        }
                    }
                } else {
                    println("Display index: \(displayIndex) not found. \(help_display_list)")
                }                
            }
            
            return
        }

        
    }
        
    println(help_msg)
}

func setDisplayMode(var display:CGDirectDisplayID, var mode:CGDisplayMode, var designatedWidth:UInt) -> Void {
    if CGDisplayModeIsUsableForDesktopGUI(mode) {
    
        var config = UnsafeMutablePointer<CGDisplayConfigRef>.alloc(1);
    
        var error = CGBeginDisplayConfiguration(config)
        if error == MyCGError.kCGErrorSuccess.rawValue {
            if nil != config {
                var option:CGConfigureOption = CGConfigureOption(kCGConfigurePermanently)
                CGConfigureDisplayWithDisplayMode(config.memory, display, mode, nil)
                var afterCheck = CGCompleteDisplayConfiguration(config.memory, option)
                if afterCheck != MyCGError.kCGErrorSuccess.rawValue {
                    CGCancelDisplayConfiguration(config.memory)
                }
            } else {
                println("Setting display mode failed")
            }
        }
    } else {
        println("This mode is unavailable for current desktop GUI")
    }
}

// list mode by display id
func listModesByDisplayID(var _displayID:CGDirectDisplayID?) -> [CGDisplayMode]? {
    if let displayID = _displayID {
        if let modeList = CGDisplayCopyAllDisplayModes(displayID, nil) {
            var modes = modeList.takeRetainedValue()

            var modesArray = [CGDisplayMode]()

            var count = CFArrayGetCount(modes)
            for i in 0..<count {
                var modeRaw = CFArrayGetValueAtIndex(modes, i)
                // https://github.com/FUKUZAWA-Tadashi/FHCCommander
                var mode = unsafeBitCast(modeRaw, CGDisplayMode.self)

                var di = displayInfo(displayID, mode)

                modesArray.append(mode)
            }

            return modesArray
        }
    }
    return nil
}

func displayModes(var _display:CGDirectDisplayID?, var index:Int, var _modes:[CGDisplayMode]?) -> Void {
    if let display = _display {
        if let modes = _modes {
            println("Supported Modes for Display \(index):")
            
            let nf = NSNumberFormatter()
            nf.paddingPosition = NSNumberFormatterPadPosition.BeforePrefix
            nf.paddingCharacter = " " // XXX: Swift does not support padding yet
            nf.minimumIntegerDigits = 3 // XXX

            for i in 0..<modes.count {
                var di = displayInfo(display, modes[i])
                println("       \(nf.stringFromNumber(di.width)!) * \(nf.stringFromNumber(di.height)!) @ \(di.frequency)Hz")
            }
        }
    }
}

// print a list of all displays
// used by -l
func listDisplays(var displayIDs:UnsafeMutablePointer<CGDirectDisplayID>, var count:Int) -> Void {
    for i in 0..<count {
        var di = displayInfo(displayIDs[i], nil)
        println("Display \(i):  \(di.width) * \(di.height) @ \(di.frequency)Hz")
    }
}


struct DisplayInfo {
    var width:UInt, height:UInt, frequency:UInt
}
// return with, height and frequency info for corresponding displayID
func displayInfo(var display:CGDirectDisplayID, var mode:CGDisplayMode?) -> DisplayInfo {
    if mode == nil {
        mode = CGDisplayCopyDisplayMode(display).takeRetainedValue() as CGDisplayMode
    }
    
    var width = UInt( CGDisplayModeGetWidth(mode) )
    var height = UInt( CGDisplayModeGetHeight(mode) )
    var frequency = UInt( CGDisplayModeGetRefreshRate(mode) )

    if frequency == 0 {
        var link:Unmanaged<CVDisplayLink>?
        CVDisplayLinkCreateWithCGDisplay(display, &link)
    
        var time:CVTime = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!.takeRetainedValue() as CVDisplayLink)

        // timeValue is in fact already in Int64
        var timeValue = time.timeValue as Int64

        // a hack-y way to do ceil
        var timeScale = Int64(time.timeScale) + timeValue / 2

        frequency = UInt( timeScale / timeValue )
    }

    return DisplayInfo(width:width, height:height, frequency:frequency)
}

// run it
main()
