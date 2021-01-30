# Documentation home: https://github.com/engrit-illinois/Get-LocalUserProfiles
# By mseng3

param(
	[Parameter(Mandatory=$true)]
	[int]$DeleteProfilesOlderThan,
	
	# Comma-separated list of NetIDs
	[string]$ExcludedUsers
)

$version = "1.2"

$ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$log = "c:\engrit\logs\Remove-LocalUserProfiles_MECM_$ts.log"

function log($msg) {
	$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
	$msg = "[$ts] $msg"
	#Write-Host $msg
	if(!(Test-Path -PathType leaf -Path $log)) {
		New-Item -ItemType File -Force -Path $log | Out-Null
	}
	$msg | Out-File $log -Append
}

function Quit($msg) {
	log "Quitting with message: `"$msg`"."
	Write-Output $msg
	exit
}

$profilesCount = 0
$profilesAttempted = 0
$profilesDeleted = 0
$profilesFailed = 0

log "Script version: `"$version`""
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
	elseif(@($profiles).count -lt 1) {
		Quit "Zero profiles found!"
	}
	else {
		$count = @($profiles).count
		$profilesCount = $count
		log "    Found $count profiles."
		
		log "Filtering profiles to those older than $DeleteProfilesOlderThan days..."
		$profiles = $profiles | Where { $_.LastUseTime -le $oldestDate }
		$count = @($profiles).count
		log "    $count profiles remain."
		
		log "Filtering out system profiles..."
		$profiles = $profiles | Where { $_.LocalPath -notlike "*$env:SystemRoot*" }
		$count = @($profiles).count
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
			log "        $count profiles remain."
		}
		else {
			log "No -ExcludedUsers were specified."
		}
		
		log "Deleting remaining profiles..."
		$profiles = $profiles | Sort LocalPath
		$profilesAttempted = @($profiles).count
		foreach($profile in $profiles) {
			log "    Deleting profile: `"$($profile.LocalPath)`"..."
			try {
				# Delete() method works with Get-WMIObject, but not with Get-CIMInstance
				# https://www.reddit.com/r/PowerShell/comments/7qu9dg/inconsistent_results_with_calling_win32/
				#$profile.Delete()
				$profile | Remove-CIMInstance
				log "        Profile deleted."
				$profilesDeleted += 1
			}
			catch {
				log "        Failed to delete profile."
				log ($_ | ConvertTo-Json | Out-String)
				$profilesFailed += 1
			}
		}
		log "Done deleting profiles."
	}
}

log "Profiles total: $profilesCount"
log "Filtered profiles targeted for deletion: $profilesAttempted"
log "Targeted profiles successfully deleted: $profilesDeleted"
log "Targeted profiles failed to delete: $profilesFailed"

if($profilesFailed -lt 1) {
	Quit "All targeted profiles deleted successfully."
}
else {
	if($profilesFailed -eq $profilesAttempted) {
		Quit "All targeted profiles failed to delete!"
	}
	else {
		Quit "Some, but not all targeted profiles failed to delete."
	}
}

log "EOF"