# Screen resolution switcher (in Swift)
This is a simple (mac) screen resolution switcher written in Swift.

Tested with Swift 3.0, Xcode 8.0, OS X Sierra 10.12.1 (16B2555), Retina MacBook Pro (Mid 2014).

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

### Set display resolution for a certain display
```bash
# Set resolution of display 0 to 2880 x 1800
./scres.swift -s 0 2880

# if only one display is attached
./scres.swift -s 2880
```

### Set display resolution with a scaling factor
```bash
# Set resolution of display 0 to 2880 x 1800 @ 2x
./scres.swift -s 0 2880 2

# Use -r for the common "Retina" scaling factor of 2.
./scres.swift -r 0 2880

# if only one display is attached
./scres.swift -r 2880
```

### Show quick help
```bash
./scres.swift -h
```

### Compile to binary (which runs faster)
```bash
# compile output write to `retina`
make

# run binary
./retina -h
```

# License
Copyright (c) 2016 Jingwei "John" Liu

Licensed under the MIT license.
