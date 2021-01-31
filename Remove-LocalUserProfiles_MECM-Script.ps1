# Documentation home: https://github.com/engrit-illinois/Get-LocalUserProfiles
# By mseng3

param(
	# Delete profiles that are older than the given number of days
	[Parameter(Mandatory=$true)]
	[int]$DeleteProfilesOlderThan,
	
	# Comma-separated list of NetIDs
	[string]$ExcludedUsers,
	
	# Timeout gracefully via self-regulation because MECM Run Scripts feature will timeout ungracefully at 60 mins
	# Recommended to make this a few minutes less than the expected ungraceful timeout
	[int]$TimeoutMins = 55,
	
	# A starting lowball (i.e. minimum) estimate for how long it will take to delete a single profile
	# This will become more accurate once we clock the actual deletions
	[int]$DeletionTimeEstimateMins = 1,
	
	[switch]$Loud
)

$VERSION = "1.5"

$ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LOG = "c:\engrit\logs\Remove-LocalUserProfiles_MECM-Script_$ts.log"

function log($msg) {
	$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
	$msg = "[$ts] $msg"
	if($Loud) {
		Write-Host $msg
	}
	if(!(Test-Path -PathType leaf -Path $LOG)) {
		New-Item -ItemType File -Force -Path $LOG | Out-Null
	}
	$msg | Out-File $LOG -Append
}

function Quit($msg) {
	log "Quitting with message: `"$msg`"."
	$quitTime = Get-Date
	$runTime = New-TimeSpan -Start $startTime -End $quitTime
	log "Total runtime: `"$runTime`""
	Write-Output $msg
	exit
}

$startTime = Get-Date
$endTime = $startTime.AddMinutes($TimeoutMins)
$timedOut = $false

$profilesCount = 0
$profilesAttempted = 0
$profilesDeleted = 0
$profilesFailed = 0

log "Script version: `"$VERSION`""
log "-DeleteProfilesOlderThan: `"$DeleteProfilesOlderThan`""
log "-ExcludedUsers: `"$ExcludedUsers`""

if($DeleteProfilesOlderThan -lt 1) {
	Quit "-DeleteProfilesOlderThan value is less than 1!"
}
else {
	$oldestDate = (Get-Date).AddDays(-$DeleteProfilesOlderThan)
	log "oldestDate = $oldestDate"
	
	log "Getting profiles..."
	try {
		#$profiles = Get-WMIObject -ClassName "Win32_UserProfile"
		$profiles = Get-CIMInstance -ClassName "Win32_UserProfile" -OperationTimeoutSec 300
	}
	catch {
		log ($_ | ConvertTo-Json | Out-String)
		Quit "Failed to retrieve profiles with Get-CIMInstance!"
	}
	
	if(!$profiles) {
		Quit "Profiles found is null!"
	}
	else {
		$count = @($profiles).count
		$profilesCount = $count
		
		if($count -lt 1) {
			Quit "Zero profiles found!"
		}
		else {
			log "    Found $count profiles."
		
			log "Filtering profiles to those older than $DeleteProfilesOlderThan days..."
			$profiles = $profiles | Where { $_.LastUseTime -le $oldestDate }
			$count = @($profiles).count
			
			if($count -lt 1) {
				Quit "Zero profiles older than $DeleteProfilesOlderThan found."
			}
			else {
				log "    $count profiles remain."
				
				log "Filtering out system profiles..."
				$profiles = $profiles | Where { $_.LocalPath -notlike "*$env:SystemRoot*" }
				$count = @($profiles).count
				
				if($count -lt 1) {
					Quit "Zero non-system profiles older than $DeleteProfilesOlderThan found."
				}
				else {
					log "    $count profiles remain."
					
					if($ExcludedUsers) {
						log "-ExcludedUsers was specified: `"$ExcludedUsers`""
						
						$users = $ExcludedUsers.Split(",")
						$users = $users.Replace("`"","")
						log "    users: $users"
						
						log "    Filtering out excluded users..."
						foreach($user in $users) {
							log "        Filtering out user: `"$user`"..."
							$profiles = $profiles | Where { $_.LocalPath -notlike "*$user*" }
						}
						$count = @($profiles).count
						
						if($count -lt 1) {
							Quit "Zero non-system, non-excluded profiles older than $DeleteProfilesOlderThan found."
						}
						else {
							log "        $count profiles remain."
						}
					}
					else {
						log "No -ExcludedUsers were specified."
					}
		
					log "Deleting remaining profiles..."
					$profiles = $profiles | Sort LocalPath
					$profilesAttempted = @($profiles).count
					
					# Keep track of how much time it takes roughly to delete a profile
					# Start out with a lowball value (since we have plenty of time), and
					# update the estimate every time a profile takes longer to delete.
					$estDeleteTime = New-TimeSpan -Minutes $DeletionTimeEstimateMins
					log "    Starting estimated deletion time: `"$estDeleteTime`""
					
					foreach($profile in $profiles) {
						log "    Processing profile: `"$($profile.LocalPath)`"..."
						
						# Check that there's at least enough time to delete one more profile
						# before the configured timeout occurs
						log "        Current estimated deletion time: `"$estDeleteTime`""
						$currentTime = Get-Date
						$timeLeft = New-TimeSpan -Start $currentTime -End $endTime
						log "        Time left before timeout: `"$timeLeft`""
						if($timeLeft -lt $estDeleteTime) {
							log "        Looks like there's probably not enough time for any more deletions."
							$timedOut = $true
							break
						}
						else {
							log "        Looks like there's probably enough time for at least one more deletion."
							
							log "        Deleting profile..."
							$startDeleteTime = Get-Date
							$startDeleteDeletions = $profilesDeleted
							try {
								# Delete() method works with Get-WMIObject, but not with Get-CIMInstance
								# https://www.reddit.com/r/PowerShell/comments/7qu9dg/inconsistent_results_with_calling_win32/
								#$profile.Delete()
								$profile | Remove-CIMInstance
								log "            Profile deleted."
								$profilesDeleted += 1
							}
							catch {
								log "            Failed to delete profile."
								log ($_ | ConvertTo-Json | Out-String)
								$profilesFailed += 1
							}
							$endDeleteTime = Get-Date
							$deleteTime = New-TimeSpan -Start $startDeleteTime -End $endDeleteTime
							if($profilesDeleted -gt $startDeleteDeletions) {
								log "        Time taken to delete: `"$deleteTime`""
								if($deleteTime -gt $estDeleteTime) {
									log "        Deletion took longer than current estimate. Updating to `"$estDeleteTime`"."
									$estDeleteTime = $deleteTime
								}
							}
						}
					}
					log "Done deleting profiles."
				}
			}
		}
	}
}

log "Profiles total: $profilesCount"
log "Filtered profiles targeted for deletion: $profilesAttempted"
log "Targeted profiles successfully deleted: $profilesDeleted"
log "Targeted profiles failed to delete: $profilesFailed"

if($profilesFailed -lt 1) {
	if($timedOut) {
		Quit "Timeout reached. Before that, all targeted profiles were deleted successfully."
	}
	else {
		Quit "All targeted profiles were deleted successfully."
	}
}
else {
	if($profilesFailed -eq $profilesAttempted) {
		if($timedOut) {
			Quit "Timeout reached. Before that, all targeted profiles failed to delete!"
		}
		else {
			Quit "All targeted profiles failed to delete!"
		}
	}
	else {
		if($timedOut) {
			Quit "Timeout reached. Before that, some, but not all targeted profiles failed to delete."
		}
		else {
			Quit "Some, but not all targeted profiles failed to delete."
		}
	}
}

Quit "Unknown result."

log "EOF"