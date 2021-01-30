# https://gallery.technet.microsoft.com/scriptcenter/Remove-Old-Local-User-080438f6#content
# https://gallery.technet.microsoft.com/scriptcenter/How-to-delete-user-d86ffd3c/view/Discussions/0

param(
	[string]$Computername = $env:COMPUTERNAME,
	
	[Parameter(Mandatory=$true)]
	[Int32]$DeleteProfilesOlderThan,
	
	[Parameter(Mandatory=$false)]
	[String[]]$ExcludedUsers
	
)

Try
{
	$UserProfileLists = Get-WmiObject -ComputerName $Computername -Class Win32_UserProfile | Select-Object @{Expression={$_.__SERVER};Label="ComputerName"},`
	LocalPath,@{Expression={$_.ConvertToDateTime($_.LastUseTime)};Label="LastUseTime"} `
	| Where{$_.LocalPath -notlike "*$env:SystemRoot*"}
}
Catch
{
	Throw "Gathering profile WMI information from $Computername failed. Be sure that WMI is functioning on this system."
}

If($DeleteProfilesOlderThan -gt 0)
{
	$ProfileInfo = Get-WmiObject -ComputerName $Computername -Class Win32_UserProfile | `
	Where{$_.ConvertToDateTime($_.LastUseTime) -le (Get-Date).AddDays(-$DeleteProfilesOlderThan) -and $_.LocalPath -notlike "*$env:SystemRoot*" }
	
	If($ExcludedUsers)
	{
		Foreach($ExcludedUser in $ExcludedUsers)
		{
			#Perform the recursion by calling itself.
			$ProfileInfo = $ProfileInfo | Where{$_.LocalPath -notlike "*$ExcludedUser*"}
		}
	}

	If($ProfileInfo -eq $null)
	{
		Write-Warning -Message "The item not found."
	}
	Else
	{
		Foreach($RemoveProfile in $ProfileInfo)
		{
			Try{$RemoveProfile.Delete();Write-Host "Delete profile '$($RemoveProfile.LocalPath)' successfully."}
			Catch{Write-Host "Delete profile failed." -ForegroundColor Red}
		}

	}
	$ProfileInfo | Select-Object `
	@{Expression={$_.__SERVER};Label="ComputerName"},LocalPath, `
	@{Expression={$_.ConvertToDateTime($_.LastUseTime)};Label="LastUseTime"},`
	@{Name="Action";Expression={If(Test-Path -Path $_.LocalPath){"Not Deleted"}Else{"Deleted"}}}
}