ConvertFrom-StringData @'
    CheckingVirtualDiskExistsMessage = Checking virtual disk at location '{0}' exists and is attached.
    VirtualDiskDoesNotExistMessage = The virtual disk at location '{0}' does not exist or is not attached.
    VirtualDiskDoesNotExistCreatingNowMessage = The virtual disk at location '{0}' does not exist. Creating virtual disk now.
    VirtualDiskCurrentlyAttachedMessage = The virtual disk at location '{0}' was found and is attached to the system.
    VirtualDiskCurrentlyAttachedButShouldNotBeMessage = The virtual disk at location '{0}' was found and is attached to the system but it should not be.
    VhdFormatDiskSizeInvalidMessage = The virtual disk size '{0}' was invalid for the 'vhd' format. Min supported value is 10 Mb and max supported value 2040 Gb.
    VhdxFormatDiskSizeInvalidMessage = The virtual disk size '{0}' was invalid for the 'vhdx' format. Min supported value is 10 Mb and max supported value 64 Tb.
    VirtualDiskNotAttachedMessage = The virtual disk at location '{0}' is not attached. Attaching virtual disk now.
    VirtualDiskDismountingImageMessage = The virtual disk located at '{0}' is dismounting.
    VirtualHardDiskUnsupportedFileType = The file type .{0} is not supported. Only .vhd and .vhdx file types are supported.
    VirtualHardDiskPathError = The path '{0}' must be a fully qualified path that starts with a Drive Letter.
'@
