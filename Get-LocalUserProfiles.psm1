# Documentation home: https://github.com/engrit-illinois/Get-LocalUserProfiles
# By mseng3

function Get-LocalUserProfiles {
	
	param(
				
		[Parameter(Position=0,Mandatory=$true)]
		[string[]]$Computers,
		
		[string]$OUDN = "OU=Desktops,OU=Engineering,OU=Urbana,DC=ad,DC=uillinois,DC=edu",
		
		[switch]$Log,
		[string]$LogPath = "c:\engrit\logs\Get-LocalUserProfiles_$(Get-Date -Format `"yyyy-MM-dd_HH-mm-ss`").log",
		
		[switch]$Csv,
		[string]$CsvPath = "c:\engrit\logs\Get-LocalUserProfiles_$(Get-Date -Format `"yyyy-MM-dd_HH-mm-ss`").csv",
		
		[int]$Verbosity = 0,
		
		[switch]$NoConsoleOutput,
		
		# Maximum number of asynchronous jobs allowed to run at once
		# This is to limit how many computers are simultaneously being polled for profile data over the network
		# Set to 0 to disable the asynchronous mechanism entirely and just do it sequentially
		[int]$MaxAsyncJobs = 10,
		
		# System root profiles ignored by default because this cmdlet's output will
		# likely be used to delete profiles, and we don't want to accidentally enable that mistake
		[switch]$IncludeSystemProfiles,
		
		[string]$SystemRootProfileQuery = "*$env:SystemRoot*",
		
		# Outputs profiles gathered from each computer as they are gathered
		# Not compatible with -MaxAsyncJobs > 1, will be ignored
		[switch]$PrintProfilesInRealtime,
		
		[string]$Indent = "    ",
		
		[ValidateSet("ComputersSummary","ComputersSummaryExtended","FlatProfiles")]
		[string]$CsvType = "ComputersSummary",
		
		[switch]$ReturnObject,
		
		[ValidateSet("ComputersSummary","ComputersSummaryExtended","FlatProfiles")]
		[string]$ReturnObjectType = "ComputersSummary",
		
		[ValidateSet("Name","_NumberOfProfiles","_YoungestProfilePath","_YoungestProfileDate","_OldestProfileDate","_OldestProfilePath","_LargestProfileTimeSpan")]
		[string]$SortSummaryBy = "_NumberOfProfiles",
		
		[int]$CIMTimeoutSec = 60
	)
	
	$SCRIPT_VERSION = "v1.2"
	$ASYNC_JOBNAME_BASE = "Job_Get-LocalUserProfiles"
	
	function log {
		param (
			[Parameter(Position=0)]
			[string]$Msg = "",
			
			[int]$L = 0, # level of indentation
			[int]$V = 0, # verbosity level
			[switch]$NoTS, # omit timestamp
			[switch]$NoNL, # omit newline after output
			[switch]$NoConsole, # skip outputting to console
			[switch]$NoLog # skip logging to file
		)
		
		# Custom indent per message, good for making output much more readable
		for($i = 0; $i -lt $L; $i += 1) {
			$Msg = "$Indent$Msg"
		}
		
		# Add timestamp to each message
		# $NoTS parameter useful for making things like tables look cleaner
		if(!$NoTS) {
			$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
			$Msg = "[$ts] $Msg"
		}
		
		# Each message can be given a custom verbosity ($V), and so can be displayed or ignored depending on $Verbosity
		# Check if this particular message is too verbose for the given $Verbosity level
		if($V -le $Verbosity) {
			
			# Check if this particular message is supposed to be output to console
			if(!$NoConsole) {
				
				# If we're allowing console output, then Write-Host
				if(!$NoConsoleOutput) {
					
					if($NoNL) {
						Write-Host $Msg -NoNewline
					}
					else {
						Write-Host $Msg
					}
				}
			}
			
			# Check if this particular message is supposed to be logged
			if(!$NoLog) {
				
				# If we're allowing logging, then log
				if($Log) {
					
					# Check that the logfile already exists, and if not, then create it (and the full directory path that should contain it)
					if(!(Test-Path -PathType leaf -Path $LogPath)) {
						New-Item -ItemType File -Force -Path $LogPath | Out-Null
					}
					
					if($NoNL) {
						$Msg | Out-File $LogPath -Append -NoNewline
					}
					else {
						$Msg | Out-File $LogPath -Append
					}
				}
			}
		}
	}
	
	function Log-Error($e, $L) {
		log "$($e.Exception.Message)" -L $l
		log "$($e.InvocationInfo.PositionMessage.Split("`n")[0])" -L ($L + 1)
	}
	
	function Get-CompNameString($comps) {
		$list = ""
		foreach($comp in $comps) {
			$list = "$list, $($comp.Name)"
		}
		$list = $list.Substring(2,$list.length - 2) # Remove leading ", "
		$list
	}

	function Get-Comps($compNames) {
		log "Getting computer names..."
		
		$comps = @()
		foreach($name in @($compNames)) {
			$comp = Get-ADComputer -Filter "name -like '$name'" -SearchBase $OUDN
			$comps += $comp
		}
		$list = Get-CompNameString $comps
		log "Found $($comps.count) computers in given array: $list." -L 1
	
		log "Done getting computer names." -V 2
		$comps
	}

	function Get-ProfilesFrom($comp) {
		$compName = $comp.Name
		log "Getting profiles from `"$compName`"..." -L 1
		
		# TODO: wrap this in try/catch and save any errors to a new custom property
		$profiles = Get-CIMInstance -ComputerName $compName -ClassName "Win32_UserProfile" -OperationTimeoutSec $CIMTimeoutSec
		
		# Ignore system profiles by default
		if(!$IncludeSystemProfiles) {
			$profiles = $profiles | Where { $_.LocalPath -notlike $SystemRootProfileQuery }
		}
		
		log "Found $(@($profiles).count) profiles." -L 2 -V 1
		$comp | Add-Member -NotePropertyName "_Profiles" -NotePropertyValue $profiles -Force
		Print-ProfilesFrom($comp)
		log "Done getting profiles from `"$compname`"." -L 1 -V 2
		$comp
	}
	
	function AsyncGet-ProfilesFrom {
		param(
			$comp,
			$CIMTimeoutSec,
			$IncludeSystemProfiles
		)
		
		# Note: cannot do any logging to the console from jobs (i.e. log() and Print-ProfilesFrom()), because jobs run in another process.
		# Might be able to capture this with a bunch of extra code checking each job while it's still running, but that's totally not worth it for short jobs
		# Jobs might still be able to write to the log file, but it would be out of order and might cause race conditions with different processes accessing the same log file at the same time.
		# Also, any external functions and variable must be passed into the job since it's a separate process. For functions which call other functions and variables, this quickly becomes infeasible.
		# For simple scripts like this, I'll have to accept not getting any real-time feedback from async jobs.
		
		function log($msg) {
			Write-Host $msg
		}
	
		function Log-Error($e) {
			log "$($e.Exception.Message)"
			log "$($e.InvocationInfo.PositionMessage.Split("`n")[0])"
		}
			
		$compName = $comp.Name
		log "Getting profiles from `"$compName`"..."
		
		$error = ""
		try {
			$profiles = Get-CIMInstance -ComputerName $compName -ClassName "Win32_UserProfile" -OperationTimeoutSec $CIMTimeoutSec
		}
		catch {
			Log-Error $_
			$error = $_.Exception.Message
		}
		$comp | Add-Member -NotePropertyName "_Error" -NotePropertyValue $error -Force
		
		# Ignore system profiles by default
		if(!$IncludeSystemProfiles) {
			$profiles = $profiles | Where { $_.LocalPath -notlike $SystemRootProfileQuery }
		}
		
		log "Found $(@($profiles).count) profiles."
		$comp | Add-Member -NotePropertyName "_Profiles" -NotePropertyValue $profiles -Force
		log "Done getting profiles from `"$compname`"."
		$comp
	}
	
	function Print-ProfilesFrom($comp) {
		if($PrintProfilesInRealtime) {
			# Limit output to relevant info
			$profiles = $comp._Profiles | Select LocalPath,LastUseTime | Sort LastUseTime,Name
			
			# Build a string to output all at once, so individual lines don't end up getting mixed up
			# with lines from other asynchronous jobs
			$output = "`n$Indent$Indent-----------------------------`n"
			$output += "$($Indent)$($Indent)Profiles for `"$($comp.Name)`":"
			$profiles | Out-String -Stream | ForEach { $output += "`n$Indent$Indent$Indent$_" }
			$output += "`n$Indent$Indent-----------------------------`n"
			log $output -NoTS
		}
	}
	
	function Start-AsyncGetProfilesFrom($comp) {
		# If there are already the max number of jobs running, then wait
		$running = @(Get-Job | Where { $_.State -eq 'Running' })
		if($running.Count -ge $MaxAsyncJobs) {
			$running | Wait-Job -Any | Out-Null
		}
		
		# After waiting, start the job
		# Each job gets profiles, and returns a modified $comp object with the profiles included
		# We'll collect each new $comp object into the $comps array when we use Recieve-Job
		
		<# Turns out that using script-level functions in Start-Job ScriptBlocks is not that simple:
		
		#$comp = GetProfilesFrom $comp
		#return $comp
		
		# https://stackoverflow.com/questions/7162090/how-do-i-start-a-job-of-a-function-i-just-defined
		# https://social.technet.microsoft.com/Forums/windowsserver/en-US/b68c1c68-e0f0-47b7-ba9f-749d06621a2c/calling-a-function-using-startjob?forum=winserverpowershell
		# https://stuart-moore.com/calling-a-powershell-function-in-a-start-job-script-block-when-its-defined-in-the-same-script/
		# https://stackoverflow.com/questions/15520404/how-to-call-a-powershell-function-within-the-script-from-start-job
		# https://stackoverflow.com/questions/8489060/reference-command-name-with-dashes
		# https://powershell.org/forums/topic/what-is-function-variable/
		# https://stackoverflow.com/questions/8489060/reference-command-name-with-dashes
		# https://stackoverflow.com/a/8491780/994622
		#>
		
		$scriptBlock = Get-Content function:AsyncGet-ProfilesFrom
		
		$ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss-ffff"
		$compName = $comp.name
		$uniqueJobName = "$($ASYNC_JOBNAME_BASE)_$($compName)_$($ts)"
		Start-Job -Name $uniqueJobName -ArgumentList $comp,$CIMTimeoutSec,$IncludeSystemProfiles -ScriptBlock $scriptBlock
	}
	
	function AsyncGet-Profiles($comps) {
		# Async example: https://stackoverflow.com/a/24272099/994622
		
		# For each computer start an asynchronous job
		log "Starting async jobs to get profiles from computers..." -L 1
		log "-MaxAsyncJobs is set to $($MaxAsyncJobs)." -L 2
		$count = 0
		foreach ($comp in $comps) {
			log $comp.Name -L 2
			Start-AsyncGetProfilesFrom $comp
			$count += 1
		}
		log "Started $count jobs." -L 1
		
		# Wait for all the jobs to finish
		log "Waiting for async jobs to finish..." -L 1
		Wait-Job * | Out-Null

		# Once all jobs are done, start processing their output
		# We can't directly write over each $comp in $comps, because we don't know which one is which without doing a bunch of extra logic
		# So just make a new $comps instead
		$newComps = @()
		
		log "Receiving jobs..." -L 1
		$count = 0
		$jobNameQuery = "$($ASYNC_JOBNAME_BASE)_*"
		foreach($job in Get-Job -Name $jobNameQuery) {
			$comp = Receive-Job $job
			log "Received job for computer `"$($comp.Name)`"." -L 2
			$newComps += $comp
			$count += 1
		}
		log "Received $count jobs." -L 1
		
		log "Removing jobs..." -L 1
		Remove-Job -Name $jobNameQuery
		
		$newComps
	}
	
	function Get-Profiles($comps) {
		log "Retrieving profiles..."
		
		if($MaxAsyncJobs -lt 1) {
			foreach($comp in $comps) {
				$comp = Get-ProfilesFrom $comp
			}
		}
		else {
			$comps = AsyncGet-Profiles $comps
		}
		
		log "Done retrieving profiles." -V 2
		$comps
	}
	
	function Munge-Profiles($comps) {
		log "Identifying youngest and oldest profiles..."
		
		foreach($comp in $comps) {
			$compName = $comp.Name
			log "$compName" -L 1 -V 1
			
			# Track youngest and oldest profile
			$oldestProfileDate = Get-Date # default to current date and time
			$oldestProfilePath = "unknown"
			$youngestProfileDate = Get-Date "1900-01-01" # default to an impossibly old date and time
			$youngestProfilePath = "unknown"
			
			foreach($profile in $comp._Profiles) {
				if($profile.LastUseTime -lt $oldestProfileDate) {
					$oldestProfileDate = $profile.LastUseTime
					$oldestProfilePath = $profile.LocalPath
				}
				if($profile.LastUseTime -gt $youngestProfileDate) {
					$youngestProfileDate = $profile.LastUseTime
					$youngestProfilePath = $profile.LocalPath
				}
				if(
					($profile.PSComputerName -eq $null) -or
					($profile.PSComputerName -eq "")
				) {
					if($comp.Name -eq $env:Computername) {
						$profile.PSComputerName = $comp.Name
					}
				}
			}
			
			# This gets me EVERY FLIPPIN TIME:
			# https://stackoverflow.com/questions/32919541/why-does-add-member-think-every-possible-property-already-exists-on-a-microsoft
			
			# Store info about youngest and oldest profiles in the comp object
			$comp | Add-Member -NotePropertyName "_OldestProfileDate" -NotePropertyValue $oldestProfileDate -Force
			$comp | Add-Member -NotePropertyName "_OldestProfilePath" -NotePropertyValue $oldestProfilePath -Force
			$comp | Add-Member -NotePropertyName "_YoungestProfileDate" -NotePropertyValue $youngestProfileDate -Force
			$comp | Add-Member -NotePropertyName "_YoungestProfilePath" -NotePropertyValue $youngestProfilePath -Force
			$comp | Add-Member -NotePropertyName "_NumberOfProfiles" -NotePropertyValue @($comp._Profiles).count -Force
			
			$diff = New-TimeSpan -Start $oldestProfileDate -End $youngestProfileDate
			$diffFormatted = "{0:G}" -f $diff
			$comp | Add-Member -NotePropertyName "_LargestProfileTimeSpan" -NotePropertyValue $diffFormatted -Force
			
			# Print out a preview of the interesting info for this comp
			#log ($comp | Select "_YoungestProfilePath","_YoungestProfileDate","_OldestProfileDate","_OldestProfilePath" | Out-String) -NoTS
			
			log "Done with `"$compName`"." -L 1 -V 2
		}
		
		log "Done identifying youngest and oldest profiles." -V 2
		$comps
	}
	
	function Print-Profiles($comps) {
		log "Summary of profiles from all computers:"
		log ($comps | Format-Table | Out-String) -NoTS
	}
	
	function Export-Profiles($comps, $summaryComps) {
		if($Csv) {
			log "-Csv was specified. Exporting data to `"$CsvPath`"..."
			
			switch($CsvType) {
				"ComputersSummaryExtended" { $csvComps = $comps }
				"FlatProfiles" { $csvComps = $flatProfiles }
				Default { $csvComps = $summaryComps }
			}
			
			$csvComps | Export-Csv -NoTypeInformation -Encoding "Ascii" -Path $CsvPath
		}
	}
	
	function Return-Object($comps, $summaryComps, $flatProfiles) {
		if($ReturnObject) {
			switch($ReturnObjectType) {
				"ComputersSummaryExtended" { $comps }
				"FlatProfiles" { $flatProfiles }
				Default { $summaryComps }
			}
		}
	}
	
	function Get-SummaryComps($comps) {
		$comps | Select Name,"_NumberOfProfiles","_Error","_YoungestProfilePath","_YoungestProfileDate","_OldestProfileDate","_OldestProfilePath","_LargestProfileTimeSpan" | Sort $SortSummaryBy
	}
	
	function Get-FlatProfiles($comps) {
		$flatProfiles = @()
		foreach($comp in $comps) {
			$flatProfiles += @($comp._Profiles)
		}
		$flatProfiles
	}
	
	function Get-RunTime($startTime) {
		$endTime = Get-Date
		$runTime = New-TimeSpan -Start $startTime -End $endTime
		$runTime
	}

	function Do-Stuff {
		$startTime = Get-Date
		
		$comps = Get-Comps $Computers
		$comps = Get-Profiles $comps
		$comps = Munge-Profiles $comps
		
		$summaryComps = Get-SummaryComps $comps
		$flatProfiles = Get-FlatProfiles $comps
		
		Print-Profiles $summaryComps
		Export-Profiles $comps $summaryComps $flatProfiles
		Return-Object $comps $summaryComps $flatProfiles
		
		$runTime = Get-RunTime $startTime
		log "Runtime: $runTime"
	}
	
	Do-Stuff

	log "EOF"

}