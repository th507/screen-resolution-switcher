# Screen resolution switcher (in Swift)
This is a simple (mac) screen resolution switcher written in Swift.

Tested with Xcode 6.3 beta 2, OS X Yosemite 10.10.2, Retina MacBook Pro (Early 2013).

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
```

### Set display resolution for a certain display
```bash
# Set resolution of display 0 to 2880*1800
./scres.swift -s 0 2880    
```

### Show quick help
```bash
./scres.swift -h
```

# License
Copyright (c) 2015 Jingwei "John" Liu

Licensed under the MIT license.
