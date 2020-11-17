# Screen resolution switcher (in Swift)
This is a simple (mac) screen resolution & dark-mode switcher written in Swift.

Tested with Swift 5.1.3, Xcode 11.3.1 (11C504), OS X Catalina 10.15.2 (19C57), Retina MacBook Pro (Mid 2015).

# Usage
### List attached displays
```bash
# List attached displays with its display index
./scres.swift -l
```

### List all supported mode for a certain display
```bash
# List all mode for Display 0
./scres.swift -m 0

# if only one display is attached
./scres.swift -m
```

### Set display resolution
```bash
# Supported command calls
#   -s [width]
#   -s [displayID], [width]
#   -s [width], [scale]
#   -s [width], [height]
#   -s [displayID], [width], [height]
#   -s [displayID], [width], [scale]
#   -s [displayID], [width], [height], [scale]
```

#### Shortcut for a certain display
```bash
# Set resolution of display 0 to 2880 x 1800
./scres.swift -s 0 2880

# if only one display is attached
# (by default it will try to use retina mode if possible)
./scres.swift -s 2880
```

#### Set a scaling factor
```bash
# Set resolution of display 0 to 2880 x 1800 @ 2x
./scres.swift -s 0 2880 2

# -r behave the same as -s
./scres.swift -r 0 2880

# if only one display is attached, will try higher retina (2x) first
./scres.swift -s 2880
```

### Toggle Dark Mode (with JXA)
```bash
./scres.swift -d
```

### Sleep display
```bash
./scres.swift -sl
```

### Show quick help
```bash
./scres.swift -h
```

### Compile to binary (which runs faster)
```bash
# compile output write to `scres`
make

# run binary
./scres -h
```

# License
Copyright (c) 2020 Jingwei "John" Liu

Licensed under the MIT license.
