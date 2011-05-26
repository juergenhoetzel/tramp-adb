# Installation

Your ```.emacs``` file now needs something like this:

     (add-to-list 'load-path "/path/to/tramp-adb")
     (require 'tramp-adb)

Ensure the path to the SDK directory is configured:

    (customize-variable 'tramp-adb-sdk-dir)  

# Usage 

    (find-file "/adb::/")

# Screenshot
 
Access Files on Android device using Emacs Dired mode:

![Emacs Dired accessing Files via TRAMP](tramp-adb/raw/master/res/emacs-dired.png) 

# TODOs and Limitations #

## General 

* non-root-access: Due to security it is not possible to access non-root devices

## Tramp Handlers

* ```tramp-adb-handle-make-directory```: Handle parents
* ```tramp-adb-maybe-open-connection ```: use (tramp-file-name-host vec) to select device


