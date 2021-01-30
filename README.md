# Summary

This Powershell module pulls information about local user profiles from an array of given computers.  

It will dump some of this info about all profiles found on all given computers to the screen. Additionally it will optionally log data to a log file, and/or a CSV file, as well as return an object containing all the data.  

See below for more detailed [context](#context) and [credits](#credits).  

# Usage

1. Download `Get-LocalUserProfiles.psm1`
2. Import it as a module: `Import-Module "c:\path\to\Get-LocalUserProfiles.psm1"`
3. Run it using the parameters documented below
- e.g. `Get-LocalUserProfiles -Computers "gelib-4c-*" -Log -Csv -PrintProfilesInRealtime`

# Parameters

### -Computers
WIP

### -OUDN
WIP

### -Log
WIP

### -LogPath
WIP

### -Csv
WIP

### -CsvPath
WIP

### -Verbosity
WIP

### -NoConsoleOutput
WIP

### -MaxAsyncJobs
WIP

### -IncludeRootProfiles
WIP

### -PrintProfilesInRealtime
WIP

### -Indent
WIP

### -ReturnObject
WIP

### -CIMTimeoutSec
WIP

# Context

Specifically this module is mostly interested in the age of the profiles. For each computer, it looks through each profile and determines which profile is the "youngest" (i.e. has the most recent LastUseTime property), and which is the "oldest".  

In many circumstances this info would be useful for the purposes of "deleting profiles older than X days". However due to either Windows bugs, or incompatibilities with other tools, this LastUseTime property has been proven to be completely unreliable as a source to determining when a user last logged in. This is likely due to the property being updated by some unknown mechanism. This is very frustrating for IT pros looking to rely on that information.  

This module was created mostly to scan large swaths of computers to look for patterns in the age of the youngest and oldest profiles. In the author's environment

Sources on the issue:
- https://techcommunity.microsoft.com/t5/windows-10-deployment/issue-with-date-modified-for-ntuser-dat/m-p/102438
- https://community.spiceworks.com/topic/2263965-find-last-user-time
- https://powershell.org/forums/topic/incorrect-information-gets-recorded-in-win32_userprofile-lastusetime-obj/

# Credits

This module was based closely on various scripts written for the purposes of deleting old, stale profiles.
- https://gallery.technet.microsoft.com/scriptcenter/Remove-Old-Local-User-080438f6#content
- https://gallery.technet.microsoft.com/scriptcenter/How-to-delete-user-d86ffd3c/view/Discussions/0

# Notes
- By mseng3