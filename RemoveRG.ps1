
<#PSScriptInfo

.VERSION 1.0

.GUID

.AUTHOR AzureAutomationTeam & Mads AW

.COMPANYNAME Microsoft

.COPYRIGHT

.TAGS AzureAutomation Utility

.LICENSEURI

.PROJECTURI https://github.com/T-Mads/Budget-Control-Sample/blob/master/RemoveRG.ps1

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES

#>

#Requires -Module Azure
#Requires -Module AzureRM.Profile
#Requires -Module AzureRM.Resources

<#
.SYNOPSIS
  Connects to Azure and removes the resource group that is an exact match for the name filter.

.DESCRIPTION
  This runbook connects to Azure and removes the resource group that matches the name.
  The script will run in the same subscription as the AutomationAccount.
  The workflow can be ran in preview mode where the resources that would be deleted are found but not deleted.
  Warning: This will delete all resources, including child resources in a group when preview mode is set to $false.

  REQUIRED AUTOMATION ASSETS
    An Automation connection asset that contains the Azure AD service principal.

.PARAMETER Name
  Optional
  Allows you to specify a name of the resource group you want to remove. It must be an exact match.
  You can test the script in preview mode to verify that the group is found.

.PARAMETER PreviewMode
  Optional with default of $true.
  Execute the runbook to see which resource group would be deleted but take no action.

.EXAMPLE
    Remove-ResourceGroups `
        -Name removeme

.NOTES
    AUTHOR: System Center Automation Team & Mads AW
    LASTEDIT: August 20, 2020
#>

workflow RemoveRG
{
	param(
		[parameter(Mandatory = $false)]
		[string]$Name,

		[parameter(Mandatory = $false)]
		[bool]$PreviewMode = $true
	)


	# Returns strings with status messages
	[OutputType([String])]

	$VerbosePreference = 'Continue'

  # Connect to ServicePrincipal
  $ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"

  Add-AzureRmAccount -ServicePrincipal `
       -TenantId $servicePrincipalConnection.TenantId `
       -ApplicationId $servicePrincipalConnection.ApplicationId `
       -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

  # Use same subscription as ServicePrincipal
  $subscriptionId = $ServicePrincipalConnection.SubscriptionID

	try {
		# Select the subscription, if not found, skip resource group removal
		Write-Verbose "Attempting connection to subscription: $subscriptionId"
		Set-AzureRMContext -SubscriptionId $subscriptionId -ErrorAction Stop -ErrorVariable err
		if($err) {
			Write-Error "Subscription not found: $subscriptionId."
			throw $err
		}
		else {
			Write-Verbose "Successful connection to subscription: $subscriptionId"
			# Find resource group to remove
			$groupsToRemove = Get-AzureRmResourceGroup -Name $Name

			# No matching groups were found to remove
			if ($groupsToRemove.Count -eq 0) {
				Write-Output "No matching resource groups found for subscription: $($subscriptionId)"
			}
			# Matching groups were found to remove
			else
			{
				# In preview mode, output what would take place but take no action
				if ($PreviewMode -eq $true) {
					Write-Output "Preview Mode: The following resource groups would be removed for subscription: $($subscriptionId)"
					foreach ($group in $groupsToRemove){
					Write-Output $($group.ResourceGroupName)
					}
					Write-Output "Preview Mode: The following resources would be removed:"
					$resources = (Get-AzureRmResource | foreach {$_} | Where-Object {$groupsToRemove.ResourceGroupName.Contains($_.ResourceGroupName)})
					foreach ($resource in $resources) {
						Write-Output $resource
					}
				}
				# Remove the resource groups in parallel
				else {
					Write-Output "Preparing to remove resource groups in parallel for subscription: $($subscriptionId)"
					Write-Output "The following resources will be removed:"
					$resources = (Get-AzureRmResource | foreach {$_} | Where-Object {$groupsToRemove.ResourceGroupName.Contains($_.ResourceGroupName)})
					foreach ($resource in $resources) {
						Write-Output $resource
					}
					foreach -parallel ($resourceGroup in $groupsToRemove) {
						Write-Output "Starting to remove resource group: $($resourceGroup.ResourceGroupName)"
						Remove-AzureRmResourceGroup -Name $($resourceGroup.ResourceGroupName) -Force
						if ((Get-AzureRmResourceGroup -Name $($resourceGroup.ResourceGroupName) -ErrorAction SilentlyContinue) -eq $null) {
							Write-Output "...successfully removed resource group: $($resourceGroup.ResourceGroupName)"
						}
					}
				}
				Write-Output "Completed."
			}
		}
    }
		catch {
			$errorMessage = $_
		}
		if ($errorMessage) {
			Write-Error $errorMessage
		}
}
