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
		
		# Not implemented yet
		[int]$MaxAsyncJobs = 1,
		
		# System root profiles ignored by default because this cmdlet's output will
		# likely be used to delete profiles, and we don't want to accidentally enable that mistake
		[switch]$IncludeSystemProfiles,
		
		# Outputs profiles gathered from each computer as they are gathered
		# Might be all kinds of weird with asynchronous jobs
		[switch]$PrintProfilesInRealtime,
		
		[string]$Indent = "    ",
		
		[switch]$ReturnObject,
		
		[ValidateSet("Summary","AllProfiles")]
		[string]$ReturnObjectType = "Summary",
		
		[int]$CIMTimeoutSec = 60
	)
	
	function log {
		param (
			[Parameter(Position=0)]
			[string]$Msg = "",
			
			[int]$L = 0, # level of indentation
			[int]$V = 0, # verbosity level
			[switch]$NoTS, # omit timestamp
			[switch]$NoNL, # omit newline after output
			[switch]$NoLog # skip logging to file
		)
		
		for($i = 0; $i -lt $L; $i += 1) {
			$Msg = "$Indent$Msg"
		}
		
		if(!$NoTS) {
			$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
			$Msg = "[$ts] $Msg"
		}
		
		# Check if this particular message is too verbose for the given $Verbosity level
		if($V -le $Verbosity) {
			
			# If we're allowing console output, then Write-Host
			if(!$NoConsoleOutput) {
				if($NoNL) {
					Write-Host $Msg -NoNewline
				}
				else {
					Write-Host $Msg
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

	function Get-ProfilesFrom {
		# Needed so this can be used in Start-Job and
		# passed parameters
		# https://stackoverflow.com/questions/7162090/how-do-i-start-a-job-of-a-function-i-just-defined
		param($comp)
		
		$compName = $comp.Name
		log "Getting profiles from `"$compName`"..." -L 1
		$profiles = Get-CIMInstance -ComputerName $compName -ClassName "Win32_UserProfile" -OperationTimeoutSec $CIMTimeoutSec
		
		# Ignore system profiles by default
		if(!$IncludeSystemProfiles) {
			$profiles = $profiles | Where { $_.LocalPath -notlike "*$env:SystemRoot*" }
		}
		
		log "Found $(@($profiles).count) profiles." -L 2 -V 1
		$comp | Add-Member -NotePropertyName "_Profiles" -NotePropertyValue $profiles -Force
		Print-ProfilesFrom($comp)
		log "Done getting profiles from `"$compname`"." -L 1 -V 2
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
	
	function Start-AsyncJobGetProfilesFrom($comp) {
		# If there are already the max number of jobs running, then wait
		$running = @(Get-Job | Where { $_.State -eq 'Running' })
		if($running.Count -ge $MaxAsyncJobs) {
			$running | Wait-Job -Any | Out-Null
		}
		
		# After waiting, start the job
		# Each job gets profiles, and returns a modified $comp object with the profiles included
		# We'll collect each new $comp object into the $comps array when we use Recieve-Job
		
		Start-Job -ScriptBlock ${function:Get-ProfilesFrom} -ArgumentList $comp | Out-Null
	}
	
	function Get-ProfilesAsync($comps) {
		# Async example: https://stackoverflow.com/a/24272099/994622
		
		# For each computer start an asynchronous job
		foreach ($comp in $comps) {
			Start-AsyncJobGetProfilesFrom $comp
		}
		
		# Wait for all the jobs to finish
		Wait-Job * | Out-Null

		# Once all jobs are done, start processing their output
		# We can't directly write over each $comp in $comps, because we don't know which one is which without doing a bunch of extra logic
		# So just make a new $comps instead
		$newComps = @()
		foreach($job in Get-Job) {
			$comp = Receive-Job $job
			$comps += $comp
		}
		
		# Remove all the jobs
		Remove-Job -State Completed
		
		$newComps
	}
	
	function Get-Profiles($comps) {
		log "Retrieving profiles..."
		
		if($MaxAsyncJobs -lt 2) {
			foreach($comp in $comps) {
				$comp = Get-ProfilesFrom $comp
			}
		}
		else {
			$comps = Get-ProfilesAsync $comps
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
			$youngestProfileDate = Get-Date 0 # default to an impossibly old date and time
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
	
	function Export-Profiles($comps) {
		if($Csv) {
			log "-Csv was specified. Exporting data to `"$CsvPath`"..."
			$comps | Export-Csv -NoTypeInformation -Encoding "Ascii" -Path $CsvPath
		}
	}
	
	function Get-OutputComps($comps) {
		$comps | Select Name,"_NumberOfProfiles","_YoungestProfilePath","_YoungestProfileDate","_OldestProfileDate","_OldestProfilePath","_LargestProfileTimeSpan" | Sort "_OldestProfileDate",Name
	}
	
	function Get-AllProfiles($comps) {
		$allProfiles = @()
		foreach($comp in $comps) {
			$allProfiles += @($comp._Profiles)
		}
		$allProfiles
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
		
		$outputComps = Get-OutputComps $comps
		
		Print-Profiles $outputComps
		Export-Profiles $outputComps
		
		if($ReturnObject) {
			if($ReturnObjectType -eq "Summary") {
				$outputComps
			}
			elseif($ReturnObjectType -eq "AllProfiles") {
				$allProfiles = Get-AllProfiles $comps
				$allProfiles
			}
		}
		
		$runTime = Get-RunTime $startTime
		log "Runtime: $runTime"
	}
	
	Do-Stuff

	log "EOF"

}