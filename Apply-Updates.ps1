## Taken from https://github.com/aaronparker/MDT/blob/master/Updates/Get-LatestUpdate.ps1 and modified to output to Windows Temp.

function Get-LatestUpdate {
    # Requires -Version 3
    [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Base')]
    Param(
        [Parameter(ParameterSetName = 'Base', Mandatory = $False, HelpMessage = "JSON source for the update KB articles.")]
        [Parameter(ParameterSetName = 'Download', Mandatory = $False)]
        [string]$StartKB = 'https://support.microsoft.com/app/content/api/content/asset/en-us/4000816',

        [Parameter(ParameterSetName = 'Base', Mandatory = $False, HelpMessage = "Windows build number.")]
        [Parameter(ParameterSetName = 'Download', Mandatory = $False)]
        [ValidateSet('16299', '15063', '14393', '10586', '10240')]
        [string]$Build = '16299',

        [Parameter(ParameterSetName = 'Base', Mandatory = $False, HelpMessage = "Search query string.")]
        [Parameter(ParameterSetName = 'Download', Mandatory = $False)]
        [string]$SearchString = 'Cumulative.*x64',

        [Parameter(ParameterSetName = 'Download', Mandatory = $False, HelpMessage = "Download the discovered updates.")]
        [switch]$Download,

        [Parameter(ParameterSetName = 'Download', Mandatory = $False, HelpMessage = "Specify a target path to download the update(s) to.")]
        [ValidateScript( { If (Test-Path $_ -PathType 'Container') { $True } Else { Throw "Cannot find path $_" } })]
        [string]$Path = ".\"
    )

    if ((Get-Host).Version -ge [version]::Parse('6.0.0')) {
        # Set PSCore to apply workarounds where cmdlet function hasn't been introduced
        $PSCore = $True
    }

    #region Support Routine
    Function Select-LatestUpdate {
        [CmdletBinding(SupportsShouldProcess = $True)]
        Param(
            [parameter(Mandatory = $True, ValueFromPipeline = $True)]
            $Updates
        )
        Begin { 
            $maxObject = $Null
            # $maxValue = [version]::new("0.0")
            # Changed to support PowerShell < 5.0
            $maxValue = New-Object System.Version("0.0")
        }
        Process {
            ForEach ( $Update in $Updates ) {
                Select-String -InputObject $Update -AllMatches -Pattern "(\d+\.)?(\d+\.)?(\d+\.)?(\*|\d+)" |
                    ForEach-Object { $_.matches.value } |
                    ForEach-Object { $_ -as [version] } |
                    ForEach-Object { 
                    If ( $_ -gt $MaxValue ) { $MaxObject = $Update; $MaxValue = $_ }
                }
            }
        }
        End { 
            $MaxObject | Write-Output 
        }
    }
    #endregion

    #region Find the KB Article Number
    Write-Verbose "Downloading $StartKB to retrieve the list of updates."
    $kbID = (Invoke-WebRequest -Uri $StartKB).Content |
        ConvertFrom-Json |
        Select-Object -ExpandProperty Links |
        Where-Object level -eq 2 |
        Where-Object text -match $Build |
        Select-LatestUpdate |
        Select-Object -First 1
    #endregion

    #region get the download link from Windows Update
    $Kb = $kbID.articleID
    Write-Verbose "Found ID: KB$($kbID.articleID)"
    $kbObj = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=KB$($kbID.articleID)"

    $Available_kbIDs = $kbObj.InputFields | 
        Where-Object { $_.Type -eq 'Button' -and $_.Value -eq 'Download' } | 
        Select-Object -ExpandProperty ID

    $Available_kbIDs | Out-String | Write-Verbose


    # If innerText is missing or empty, use outerHtml instead. Might be PSCore related
    if ($kbObj.Links.innerText -eq $Null) {
        $kbIDs = $kbObj.Links | 
            Where-Object ID -match '_link' |
            Where-Object outerHTML -match $SearchString |
            ForEach-Object { $_.Id.Replace('_link', '') } |
            Where-Object { $_ -in $Available_kbIDs }
    }
    else {
        $kbIDs = $kbObj.Links | 
            Where-Object ID -match '_link' |
            Where-Object innerText -match $SearchString |
            ForEach-Object { $_.Id.Replace('_link', '') } |
            Where-Object { $_ -in $Available_kbIDs }
    }

    # If innerHTML is empty or does not exist, use outerHTML instead
    If ( $kbIDs -eq $Null ) {
        $kbIDs = $kbObj.Links | 
            Where-Object ID -match '_link' |
            Where-Object outerHTML -match $SearchString |
            ForEach-Object { $_.Id.Replace('_link', '') } |
            Where-Object { $_ -in $Available_kbIDs }
    }

    $Urls = @()
    ForEach ( $kbID in $kbIDs ) {
        Write-Verbose "`t`tDownload $kbID"
        $Post = @{ size = 0; updateID = $kbID; uidInfo = $kbID } | ConvertTo-Json -Compress
        $PostBody = @{ updateIDs = "[$Post]" } 
        $Urls += Invoke-WebRequest -Uri 'http://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $postBody |
            Select-Object -ExpandProperty Content |
            Select-String -AllMatches -Pattern "(http[s]?\://download\.windowsupdate\.com\/[^\'\""]*)" | 
            ForEach-Object { $_.matches.value }
    }
    #endregion

    # Download the updates if -Download is specified, skip if the file exists
    If ( $Download ) {
        ForEach ( $Url in $Urls ) {
            $filename = $Url.Substring($Url.LastIndexOf("/") + 1)
            $target = Join-Path -Path (Get-Item $Path).FullName -ChildPath $filename
            Write-Verbose "`t`tDownload target will be $target"

            If (!(Test-Path -Path $target)) {
                If ($pscmdlet.ShouldProcess($Url, "Download")) {
                    # Invoke-WebRequest -Uri $Url -OutFile $target
                    if ($PSCore) {
                        Invoke-WebRequest -Uri $Url -OutFile $filename
                    }
                    else {
                        Start-BitsTransfer -Source $Url -Destination $target
                    }
                }
            }
            Else {
                Write-Verbose "File exists: $target. Skipping download."
            }
        }
    }

    # Build the output object
    # Select the Update names
    if ($PSCore) {
        $Notes = ([regex]'(?<note>\d{4}-\d{2}.*\(KB\d{7}\))').match($kbObj.RawContent).Value
    }
    else {
        $Notes = $kbObj.ParsedHtml.body.getElementsByTagName('a') | ForEach-Object InnerText | Where-Object { $_ -match $SearchString }
    }

    [int]$i = 0
    $Output = @()
    ForEach ( $Url in $Urls ) {
        $item = New-Object PSObject
        $item | Add-Member -type NoteProperty -Name 'KB' -Value "KB$Kb"
        If ( $Notes.Count -eq 1 ) {
            $item | Add-Member -type NoteProperty -Name 'Note' -Value $Notes
        }
        Else {
            $item | Add-Member -type NoteProperty -Name 'Note' -Value $Notes[$i]
        }
        $item | Add-Member -type NoteProperty -Name 'URL' -Value $Url
        If ($PSBoundParameters.ContainsKey('Download')) {
            $item | Add-Member -type NoteProperty -Name 'File' -Value $Url.Substring($Url.LastIndexOf("/") + 1)
        }
        If ($PSBoundParameters.ContainsKey('Path')) {
            $item | Add-Member -type NoteProperty -Name 'UpdatePath' -Value "$((Get-Item $Path).FullName)"
        }

        $Output += $item
        $i = $i + 1
    }

    # Write the URLs list to the pipeline
    Write-Output $Output 
}

Write-Host "Downloading the latest CU update..."

Get-LatestUpdate -SearchString 'Cumulative.*Server.*x64' -Build 14393 -Download -Path "C:\Windows\Temp"

$LatestCU = Get-ChildItem "C:\Windows\Temp" -Recurse | Where-Object {$_.Name -like "*.msu"}| Select-Object -ExpandProperty FullName

if (!(Test-Path $env:systemroot\SysWOW64\wusa.exe)) {
    $Wus = "$env:systemroot\System32\wusa.exe"
}
else {
    $Wus = "$env:systemroot\SysWOW64\wusa.exe"
}

Start-Process -FilePath $Wus -ArgumentList ($LatestCU, '/quiet', '/norestart') -Wait