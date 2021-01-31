# Summary

This Powershell module pulls information about local user profiles from an array of given computers.  

It will dump some of this info about all profiles found on all given computers to the screen. Additionally it will optionally log data to a log file, and/or a CSV file, as well as return an object containing all the data.  

This is sort of a companion module to [Remove-LocalUserProfiles](https://github.com/engrit-illinois/Remove-LocalUserProfiles). Get-LocalUserProfiles is meant for gathering information and informing decisions about how to use Remove-LocalUserProfiles.

See below for more detailed [context](#context) and caveats. 

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

In many circumstances this info would be useful for the purposes of using [Remove-LocalUserProfiles](https://github.com/engrit-illinois/Remove-LocalUserProfiles) to "delete profiles older than X days". However due to either Windows bugs, or incompatibilities with other tools, this LastUseTime property has proven to be completely unreliable as a source for determining when a user last logged in. This is likely due to the property being updated by some unknown mechanism. This is very frustrating for IT pros looking to rely on that information.  

This module was created mostly to scan large swaths of computers to look for patterns in the age of the youngest and oldest profiles. In the author's environment. Using it on any given shared computer, it's not uncommon to find that nearly all profiles have a LastUseTime within a few seconds of each other. This would be impossible if that property accurately described the times when these profiles were last legitimately used by their users. In our environment, this is the case even on computers which have over 500 profiles (from semesters of student logins).  

Sources on the issue:
- https://techcommunity.microsoft.com/t5/windows-10-deployment/issue-with-date-modified-for-ntuser-dat/m-p/102438
- https://community.spiceworks.com/topic/2263965-find-last-user-time
- https://powershell.org/forums/topic/incorrect-information-gets-recorded-in-win32_userprofile-lastusetime-obj/

# Notes
- By mseng3