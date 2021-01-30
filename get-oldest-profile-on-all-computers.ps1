$comps = Get-ADComputer -Filter "name -like 'gelib-4e-*'"
$comps += Get-ADComputer -Filter "name -like 'gelib-4c-*'"

# Handy log function
$Log = "c:\engrit\logs\oldest-profile.log"
function log {
	param(
		[string]$msg = "",
		[switch]$NoTS,
		[switch]$NoLog
	)
	
	# Create log file (and "c:\engrit\logs" path) if they don't exist
	if(!(Test-Path -PathType leaf -Path $Log)) {
		New-Item -ItemType File -Force -Path $Log | Out-Null
	}
	
	# Add timestamp, unless requested otherwise
	if(!$NoTS) {
		$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
		$msg = "[$ts] $msg"
	}
	
	# Output message to console and log file
	Write-Host $msg
	if(!$NoLog) { $msg | Out-File $Log -Append }
}

foreach($comp in $comps) {
	log $comp.Name
	$profiles = Remove-LocalUserProfiles -ListAll -Computername $comp.Name
	log ($profiles | Sort LastUseTime | Out-String)
	$oldestProfileDate = Get-Date
	$oldestProfilePath = "none"
	$youngestProfileDate = Get-Date -Year 1900
	$youngestProfilePath = "none"
	foreach($profile in $profiles) {
		if($profile.LastUseTime -lt $oldestProfileDate) {
			$oldestProfileDate = $profile.LastUseTime
			$oldestProfilePath = $profile.LocalPath
		}
		if($profile.LastUseTime -gt $youngestProfileDate) {
			$youngestProfileDate = $profile.LastUseTime
			$youngestProfilePath = $profile.LocalPath
		}
	}
	# This gets me EVERY FLIPPIN TIME:
	# https://stackoverflow.com/questions/32919541/why-does-add-member-think-every-possible-property-already-exists-on-a-microsoft
	$comp | Add-Member -NotePropertyName "_OldestProfileDate" -NotePropertyValue $oldestProfileDate -Force
	$comp | Add-Member -NotePropertyName "_OldestProfilePath" -NotePropertyValue $oldestProfilePath -Force
	log "    Oldest:"
	log ($comp | Select "_OldestProfilePath","_OldestProfileDate" | Out-String)
	
	$comp | Add-Member -NotePropertyName "_YoungestProfileDate" -NotePropertyValue $youngestProfileDate -Force
	$comp | Add-Member -NotePropertyName "_YoungestProfilePath" -NotePropertyValue $youngestProfilePath -Force
	log "    Youngest:"
	log ($comp | Select "_YoungestProfilePath","_YoungestProfileDate" | Out-String)
}
$comps | Select Name,"_OldestProfilePath","_OldestProfileDate","_YoungestProfilePath","_YoungestProfileDate" | Sort "_OldestProfileDate",Name


