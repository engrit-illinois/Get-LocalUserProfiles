# https://gallery.technet.microsoft.com/scriptcenter/Remove-Old-Local-User-080438f6#content
# https://gallery.technet.microsoft.com/scriptcenter/How-to-delete-user-d86ffd3c/view/Discussions/0

param(
	[Parameter(Mandatory=$true)]
	[int]$DeleteProfilesOlderThan,
	
	# Comma-separated list of NetIDs
	[string]$ExcludedUsers
)

$version = "1.1"

$ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$log = "c:\engrit\logs\Remove-LocalUserProfiles_MECM_$ts.log"
	
function log($msg) {
	$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
	$msg = "[$ts] $msg"
	Write-Host $msg
	if(!(Test-Path -PathType leaf -Path $log)) {
		New-Item -ItemType File -Force -Path $log | Out-Null
	}
	$msg | Out-File $log -Append
}

log "Script version: `"$version`""
log "-DeleteProfilesOlderThan: `"$DeleteProfilesOlderThan`""
log "-ExcludedUsers: `"$ExcludedUsers`""

if($DeleteProfilesOlderThan -lt 1) {
	log "-DeleteProfilesOlderThan value is less than 1!"
}
else {
	$oldestDate = (Get-Date).AddDays(-$DeleteProfilesOlderThan)
	log "oldestDate = $oldestDate"
	
	log "Getting profiles..."
	#$profiles = Get-WMIObject -ClassName "Win32_UserProfile"
	$profiles = Get-CIMInstance -ClassName "Win32_UserProfile" -OperationTimeoutSec 300
	
	if(!$profiles) {
		log "    No profiles returned."
	}
	else {
		$count = @($profiles).count
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
		foreach($profile in $profiles) {
			log "    Deleting profile: `"$($profile.LocalPath)`"..."
			try {
				# Delete() method works with Get-WMIObject, but not with Get-CIMInstance
				# https://www.reddit.com/r/PowerShell/comments/7qu9dg/inconsistent_results_with_calling_win32/
				#$profile.Delete()
				$profile | Remove-CIMInstance
				log "        Profile deleted."
			}
			catch {
				log "        Failed to delete profile."
				log ($_ | ConvertTo-Json | Out-String)
			}
		}
	}
}

log "EOF"