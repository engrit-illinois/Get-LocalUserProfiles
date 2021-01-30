# https://gallery.technet.microsoft.com/scriptcenter/Remove-Old-Local-User-080438f6#content
# https://gallery.technet.microsoft.com/scriptcenter/How-to-delete-user-d86ffd3c/view/Discussions/0

param(
	[Parameter(Mandatory=$true)]
	[Int32]$DeleteProfilesOlderThan,
	
	# Comma-separated list of NetIDs
	[String]$ExcludedUsers
)

If($DeleteProfilesOlderThan -gt 0) {
	$oldestDate = (Get-Date).AddDays(-$DeleteProfilesOlderThan)
	$Profiles = Get-CIMInstance -ClassName "Win32_UserProfile"
	$Profiles = $Profiles | Where { $_.LastUseTime -le $oldestDate }
	$Profiles = $Profiles | Where { $_.LocalPath -notlike "*$env:SystemRoot*" }
	
	If($ExcludedUsers) {
		$users = $ExcludedUsers.Split(",")
		Foreach($user in $users) {
			$Profiles = $Profiles | Where { $_.LocalPath -notlike "*$user*" }
		}
	}

	If($Profiles -eq $null) {
		Write-Warning -Message "No profiles returned."
	}
	Else {
		Foreach($RemoveProfile in $Profiles) {
			Try{
				$RemoveProfile.Delete()
			}
			Catch{
				#Write-Host "Delete profile failed."
			}
		}
	}
}