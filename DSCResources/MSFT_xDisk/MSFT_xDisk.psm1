﻿#region localizeddata
if (Test-Path "${PSScriptRoot}\${PSUICulture}")
{
    Import-LocalizedData `
        -BindingVariable LocalizedData `
        -Filename MSFT_xDisk.strings.psd1 `
        -BaseDirectory "${PSScriptRoot}\${PSUICulture}"
}
else
{
    #fallback to en-US
    Import-LocalizedData `
        -BindingVariable LocalizedData `
        -Filename MSFT_xDisk.strings.psd1 `
        -BaseDirectory "${PSScriptRoot}\en-US"
}
#endregion

# Import the common storage functions
Import-Module -Name ( Join-Path `
    -Path (Split-Path -Path $PSScriptRoot -Parent) `
    -ChildPath '\MSFT_xStorageCommon\MSFT_xStorageCommon.psm1' )

<#
    .SYNOPSIS
    Returns the current state of the Disk and Partition.
    .PARAMETER DiskNumber
    Specifies the identifier for which disk to modify.
    .PARAMETER DriveLetter
    Specifies the preferred letter to assign to the disk volume.
    .PARAMETER Size
    Specifies the size of new volume (use all available space on disk if not provided).
    .PARAMETER FSLabel
    Define volume label if required.
    .PARAMETER AllocationUnitSize
    Specifies the allocation unit size to use when formatting the volume.
#>
function Get-TargetResource
{
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory)]
        [uint32] $DiskNumber,

        [parameter(Mandatory)]
        [string] $DriveLetter,

        [UInt64] $Size,

        [string] $FSLabel,

        [UInt32] $AllocationUnitSize
    )

    Write-Verbose -Message ( @(
            "$($MyInvocation.MyCommand): "
            $($LocalizedData.GettingDiskMessage -f $DiskNumber,$DriveLetter)
        ) -join '' )

    # Validate the DriveLetter parameter
    $DriveLetter = Test-DriveLetter -DriveLetter $DriveLetter

    $disk = Get-Disk `
        -Number $DiskNumber `
        -ErrorAction SilentlyContinue

    $partition = Get-Partition `
        -DriveLetter $DriveLetter `
        -ErrorAction SilentlyContinue

    $FSLabel = (Get-Volume `
        -DriveLetter $DriveLetter `
        -ErrorAction SilentlyContinue).FileSystemLabel

    $blockSize = (Get-CimInstance `
        -Query "SELECT BlockSize from Win32_Volume WHERE DriveLetter = '$($DriveLetter):'" `
        -ErrorAction SilentlyContinue).BlockSize

    if ($blockSize)
    {
        $allocationUnitSize = $blockSize
    }
    else
    {
        # If Get-CimInstance did not return a value, try again with Get-WmiObject
        $blockSize = (Get-WmiObject `
            -Query "SELECT BlockSize from Win32_Volume WHERE DriveLetter = '$($DriveLetter):'" `
            -ErrorAction SilentlyContinue).BlockSize
        $allocationUnitSize = $blockSize
    } # if

    $returnValue = @{
        DiskNumber = $disk.Number
        DriveLetter = $partition.DriveLetter
        Size = $partition.Size
        FSLabel = $FSLabel
        AllocationUnitSize = $allocationUnitSize
    }
    $returnValue
} # Get-TargetResource

<#
    .SYNOPSIS
    Initializes the Disk and Partition and assigns the drive letter.
    .PARAMETER DiskNumber
    Specifies the identifier for which disk to modify.
    .PARAMETER DriveLetter
    Specifies the preferred letter to assign to the disk volume.
    .PARAMETER Size
    Specifies the size of new volume (use all available space on disk if not provided).
    .PARAMETER FSLabel
    Define volume label if required.
    .PARAMETER AllocationUnitSize
    Specifies the allocation unit size to use when formatting the volume.
#>
function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [uint32] $DiskNumber,

        [parameter(Mandatory)]
        [string] $DriveLetter,

        [UInt64] $Size,

        [string] $FSLabel,

        [UInt32] $AllocationUnitSize
    )

    Write-Verbose -Message ( @(
            "$($MyInvocation.MyCommand): "
            $($LocalizedData.SettingDiskMessage -f $DiskNumber,$DriveLetter)
        ) -join '' )

    # Validate the DriveLetter parameter
    $DriveLetter = Test-DriveLetter -DriveLetter $DriveLetter

    $disk = Get-Disk `
        -Number $DiskNumber `
        -ErrorAction Stop

    if ($disk.IsOffline)
    {
        # Disk is offline, so bring it online
        Write-Verbose -Message ( @(
                "$($MyInvocation.MyCommand): "
                $($LocalizedData.SetDiskOnlineMessage -f $DiskNumber)
            ) -join '' )

        Set-Disk `
            -InputObject $disk `
            -IsOffline $false
    } # if

    if ($disk.IsReadOnly)
    {
        # Disk is read-only, so make it read/write
        Write-Verbose -Message ( @(
                "$($MyInvocation.MyCommand): "
                $($LocalizedData.SetDiskReadwriteMessage -f $DiskNumber)
            ) -join '' )

        Set-Disk `
            -InputObject $disk `
            -IsReadOnly $false
    } # if

    Write-Verbose -Message ( @(
            "$($MyInvocation.MyCommand): "
            $($LocalizedData.CheckingDiskPartitionStyleMessage -f $DiskNumber)
        ) -join '' )

    switch ($disk.PartitionStyle)
    {
        "RAW"
        {
            # The disk partition table is not yet initialized, so initialize it with GPT
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.InitializingDiskMessage -f $DiskNumber)
                ) -join '' )

            Initialize-Disk `
                -InputObject $disk `
                -PartitionStyle "GPT" `
                -PassThru
        }
        "GPT"
        {
            # The disk partition is already initialized with GPT.
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.DiskAlreadyInitializedMessage -f $DiskNumber)
                ) -join '' )
        }
        default
        {
            # This disk is initialized but not as GPT - so raise an exception.
            New-InvalidOperationError `
                -ErrorId 'DiskAlreadyInitializedError' `
                -ErrorMessage ($LocalizedData.DiskAlreadyInitializedError -f `
                    $DiskNumber,$Disk.PartitionStyle)
        }
    } # switch

    # Check if existing partition already has file system on it
    if ($null -eq ($disk | Get-Partition | Get-Volume ))
    {
        # There is no partiton on the disk, so create one
        $partParams = @{
            DriveLetter = $DriveLetter;
            DiskNumber = $DiskNumber
        }

        if ($Size)
        {
            # Use only a specific size
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.CreatingPartitionMessage -f $DiskNumber,$DriveLetter,"$($Size/1kb) kb")
                ) -join '' )
            $partParams["Size"] = $Size
        }
        else
        {
            # Use the entire disk
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.CreatingPartitionMessage -f $DiskNumber,$DriveLetter,'all free space')
                ) -join '' )
            $partParams["UseMaximumSize"] = $true
        } # if

        # Create the partition.
        $partition = New-Partition @PartParams

        # Sometimes the disk will still be read-only after the call to New-Partition returns.
        Start-Sleep -Seconds 5

        $volParams = @{
            FileSystem = "NTFS";
            Confirm = $false
        }

        if ($FSLabel)
        {
            # Set the File System label on the new volume
            $volParams["NewFileSystemLabel"] = $FSLabel
        } # if
        if($AllocationUnitSize)
        {
            # Set the Allocation Unit Size on the new volume
            $volParams["AllocationUnitSize"] = $AllocationUnitSize
        } # if

        Write-Verbose -Message ( @(
                "$($MyInvocation.MyCommand): "
                $($LocalizedData.FormattingVolumeMessage -f $volParams.FileSystem)
            ) -join '' )

        # Format the volume
        $volume = Format-Volume `
            -InputObject $partition `
            @VolParams

        if ($volume)
        {
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.SuccessfullyInitializedMessage -f $DriveLetter)
                ) -join '' )
        } # if
    }
    else
    {
        # The disk already has a partition on it
        $volume = ($Disk | Get-Partition | Get-Volume)

        if ($volume.DriveLetter)
        {
            # A volume also exists in the partition
            if($volume.DriveLetter -ne $DriveLetter)
            {
                # The drive letter assigned to the volume is different, so change it.
                Write-Verbose -Message ( @(
                        "$($MyInvocation.MyCommand): "
                        $($LocalizedData.ChangingDriveLetterMessage -f $volume.DriveLetter,$DriveLetter)
                    ) -join '' )

                Set-Partition `
                    -DriveLetter $Volume.DriveLetter `
                    -NewDriveLetter $DriveLetter
            } # if
        }
        else
        {
            # Volume doesn't have an assigned letter, so set one.
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.AssigningDriveLetterMessage -f $DriveLetter)
                ) -join '' )

            Set-Partition `
                -DiskNumber $DiskNumber `
                -PartitionNumber 2 `
                -NewDriveLetter $DriveLetter
        }

        if ($PSBoundParameters.ContainsKey('FSLabel'))
        {
            # The volume should have a label assigned
            if($volume.FileSystemLabel -ne $FSLabel)
            {
                # The volume lable needs to be changed because it is different.
                Write-Verbose -Message ( @(
                        "$($MyInvocation.MyCommand): "
                        $($LocalizedData.ChangingVolumeLabelMessage -f $Volume.DriveLetter,$FSLabel)
                    ) -join '' )

                Set-Volume `
                    -InputObject $Volume `
                    -NewFileSystemLabel $FSLabel
            } # if
        } # if
    } # if
} # Set-TargetResource

<#
    .SYNOPSIS
    Tests if the disk is initialized, the partion exists and the drive letter is assigned.
    .PARAMETER DiskNumber
    Specifies the identifier for which disk to modify.
    .PARAMETER DriveLetter
    Specifies the preferred letter to assign to the disk volume.
    .PARAMETER Size
    Specifies the size of new volume (use all available space on disk if not provided).
    .PARAMETER FSLabel
    Define volume label if required.
    .PARAMETER AllocationUnitSize
    Specifies the allocation unit size to use when formatting the volume.
#>
function Test-TargetResource
{
    [OutputType([System.Boolean])]
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory)]
        [uint32] $DiskNumber,

        [parameter(Mandatory)]
        [string] $DriveLetter,

        [UInt64] $Size,

        [string] $FSLabel,

        [UInt32] $AllocationUnitSize
    )

    Write-Verbose -Message ( @(
            "$($MyInvocation.MyCommand): "
            $($LocalizedData.TestingDiskMessage -f $DiskNumber,$DriveLetter)
        ) -join '' )

    # Validate the DriveLetter parameter
    $DriveLetter = Test-DriveLetter -DriveLetter $DriveLetter

    Write-Verbose -Message ( @(
            "$($MyInvocation.MyCommand): "
            $($LocalizedData.CheckDiskInitializedMessage -f $DiskNumber)
        ) -join '' )

    $disk = Get-Disk `
        -Number $DiskNumber `
        -ErrorAction SilentlyContinue

    if (-not $disk)
    {
        Write-Verbose -Message ( @(
                "$($MyInvocation.MyCommand): "
                $($LocalizedData.DiskNotFoundMessage -f $DiskNumber)
            ) -join '' )
        return $false
    } # if

    if ($disk.IsOffline)
    {
        Write-Verbose -Message ( @(
                "$($MyInvocation.MyCommand): "
                $($LocalizedData.DiskNotOnlineMessage -f $DiskNumber)
            ) -join '' )
        return $false
    } # if

    if ($disk.IsReadOnly)
    {
        Write-Verbose -Message ( @(
                "$($MyInvocation.MyCommand): "
                $($LocalizedData.DiskReadOnlyMessage -f $DiskNumber)
            ) -join '' )
        return $false
    } # if

    if ($disk.PartitionStyle -ne "GPT")
    {
        Write-Verbose -Message ( @(
                "$($MyInvocation.MyCommand): "
                $($LocalizedData.DiskNotGPTMessage -f $DiskNumber,$Disk.PartitionStyle)
            ) -join '' )
        return $false
    } # if

    $partition = Get-Partition `
        -DriveLetter $DriveLetter `
        -ErrorAction SilentlyContinue
    if ($partition.DriveLetter -ne $DriveLetter)
    {
        Write-Verbose -Message ( @(
                "$($MyInvocation.MyCommand): "
                $($LocalizedData.DriveLetterNotFoundMessage -f $DriveLetter)
            ) -join '' )
        return $false
    } # if

    # Drive size
    if ($Size)
    {
        if ($partition.Size -ne $Size)
        {
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.DriveSizeMismatchMessage -f `
                        $DriveLetter,$Partition.Size,$Size)
                ) -join '' )
            return $false
        } # if
    } # if

    $blockSize = (Get-CimInstance `
        -Query "SELECT BlockSize from Win32_Volume WHERE DriveLetter = '$($DriveLetter):'" `
        -ErrorAction SilentlyContinue).BlockSize
    if (-not ($blockSize))
    {
        # If Get-CimInstance did not return a value, try again with Get-WmiObject
        $blockSize = (Get-WmiObject `
            -Query "SELECT BlockSize from Win32_Volume WHERE DriveLetter = '$($DriveLetter):'" `
            -ErrorAction SilentlyContinue).BlockSize
    } # if

    if($blockSize -gt 0 -and $AllocationUnitSize -ne 0)
    {
        if($AllocationUnitSize -ne $blockSize)
        {
            # Just write a warning, we will not try to reformat a drive due to invalid allocation
            # unit sizes
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.DriveAllocationUnitSizeMismatchMessage -f `
                        $DriveLetter,$($blockSize.BlockSize/1kb),$($AllocationUnitSize/1kb))
                ) -join '' )
        } # if
    } # if

    if ($PSBoundParameters.ContainsKey('FSLabel'))
    {
        # Check the volume label
        $label = (Get-Volume `
            -DriveLetter $DriveLetter `
            -ErrorAction SilentlyContinue).FileSystemLabel
        if ($label -ne $FSLabel)
        {
            # The assigned volume label is different and needs updating
            Write-Verbose -Message ( @(
                    "$($MyInvocation.MyCommand): "
                    $($LocalizedData.DriveLabelMismatch -f `
                        $DriveLetter,$Label,$FSLabel)
                ) -join '' )
            return $false
        } # if
    } # if

    return $true
} # Test-TargetResource

Export-ModuleMember -Function *-TargetResource
