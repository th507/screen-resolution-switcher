# Screen resolution switcher (in Swift)
This is a simple (mac) screen resolution switcher written in Swift.

Tested with Xcode 7.0 beta 5, OS X El Capitan (15A244d), Retina MacBook Pro (Mid 2014).

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
