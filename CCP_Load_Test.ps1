################################### GET-HELP #############################################
<#
.SYNOPSIS
 	Runs a simple load test for CyberArk Central Credential Provider. Please make sure you
	disable/turn off caching for the provider to see the most accurate results.

	Find the Change Me tags below and update the values as needed.
 
.EXAMPLES
 	./CCP_Load_Test.ps1
	./CCP_Load_Test.ps1 -Tests 50 -Threads 5
 
.INPUTS  
	Tests: How many times do you want to retrieve a credential
	Threads: How many parallel threads should the script create
	
.OUTPUTS
	Log file with the results
	
.NOTES
	AUTHOR:  
	Randy Brown

	VERSION HISTORY:
	1.0 07/28/2022 - Initial release

.LICENSE
    Permission is hereby granted, free of charge, to any person obtaining a copy of this
    software and associated documentation files (the "Software"), to deal in the Software
    without restriction, including without limitation the rights to use, copy, modify, merge,
    publish, distribute, sublicense, and/or sell copies of the Software, and to permit
    persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or
    substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
    PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
    LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT
    OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.

#>
##########################################################################################
######################## IMPORT MODULES/ASSEMBLY LOADING #################################


##########################################################################################
######################### GLOBAL VARIABLE DECLARATIONS ###################################

param (
    [string]$Tests = 10,
	[string]$Threads = 5
)

$baseURL = "https://pvwa.cybr.com"      # Change Me
$appID = ""								# Change Me
$safe = ""								# Change Me
$object = ""							# Change Me

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

########################## START FUNCTIONS ###############################################

function Test-CCP {
	try {
		$RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $Threads)
		$RunspacePool.Open()
		$Jobs = @()
		
		1..$Tests | ForEach-Object {
			$Job = [powershell]::Create().AddScript($ScriptBlock).AddArgument($_).AddArgument($baseURL).AddArgument($appID).AddArgument($safe).AddArgument($object)
			$Job.RunspacePool = $RunspacePool
			$Jobs += New-Object PSObject -Property @{
				RunNum = $_
				Pipe = $Job
				Result = $Job.BeginInvoke()
			}
		}
		
		Write-Host "Running.." -NoNewline

		do {
			Write-Host "." -NoNewline
			Start-Sleep -Seconds .1
		} while ( $Jobs.Result.IsCompleted -contains $false)
			Write-Host "Done!"
		
		$Results = @()

		foreach ($Job in $Jobs)
		{   
			$Results += $Job.Pipe.EndInvoke($Job.Result)
		}

		return $Results
		
	} catch {
		Write-Log $MyInvocation.MyCommand $_.Exception.Message "error"
	}
}

function Write-Log {
    param (
        [string]$message,
		[string]$errorMessage,
		[string]$type,
        [string]$logFolderPath = "$PSScriptRoot\Logs",
        [string]$logFilePrefix = 'AAM_Load_Test'
    )
 
    $date = Get-Date -Format "MM-dd-yyyy"
    $time = Get-Date -Format "HH:mm:ss.f"
    $logFile = "$LogFolderPath\$LogFilePrefix`_$date.log"
 
    if (!(Test-Path -Path $logFolderPath)) {
        New-Item -ItemType Directory -Path $logFolderPath -Force | Out-Null
    }
 
    if (!(Test-Path -Path $logFile)) {
        New-Item -ItemType File -Path $logFile -Force | Out-Null
    }
 
	if ($type -eq "error") {
		$logMessage = "[$time] "
		$logMessage += "error | $message"
    	Write-Host $logMessage -ForegroundColor Red
	}
    $logMessage = "[$time] "
 	$logMessage += "Info | $message"
    Write-Host $logMessage
 
    Add-Content -Path $logFile -Value "$logMessage"
}

########################## END FUNCTIONS #################################################

########################## MAIN SCRIPT BLOCK #############################################
$ScriptBlock = {
    param (
        [int]$RunNumber,
        [string]$baseURL,
        [string]$appID,
        [string]$safe,
        [string]$object
    )
    $timeTaken = Measure-Command { Invoke-RestMethod -Uri "$baseURL/AIMWebService/api/Accounts?AppID=$appID&Safe=$safe&Folder=root&Object=$object" -Method GET -ContentType "application/json" }
    $RunResult = New-Object PSObject -Property @{
        RunNumber = $RunNumber
        Time_Taken = $timeTaken
   }
   return $RunResult
}

Write-Log "Starting Script"
Write-Log "Making $Tests calls to the CCP"
Write-Log "Using $Threads parallel threads"

$results = Test-CCP

foreach ($entry in $results) {
	$logEntry = "ID: " + $entry.RunNumber + " Run Time: " + $entry.Time_Taken
	Write-Log $logEntry
	$total += $entry.Time_Taken
}

Write-Log "Total Run time: $total"
Write-Log "Script Complete!"

########################### END SCRIPT ###################################################