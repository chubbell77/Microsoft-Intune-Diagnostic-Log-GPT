
---

### IntuneLogProcessor.ps1

```powershell
<#
.SYNOPSIS
   Microsoft Intune Diagnostic Log Preprocessing Script - Revision 1.14.2

.DESCRIPTION
   This script processes diagnostic logs from a Windows Intune diagnostic ZIP file.
   It accepts an optional command-line parameter for the archive file path. If not provided
   or invalid, a file selector dialog is used.
   
   Steps performed:
     1. Pre-run Cleanup: Remove any leftover temporary folders ("LogProcessing_*").
     2. File Input: Use the provided archive file path or prompt via a file selector.
     3. Title Output: Immediately print a title with credit to Geeks.Online (displayed in blue).
     4. Extraction: Unzip the archive and expand any CAB files.
     5. Conversion: Convert *.reg, SetupDiagResults.xml, *.evtx, and *.etl files to CSV 
        (renaming them with appended extensions, e.g. filename.reg.csv). Note that event log and ETL conversions
        may take several minutes.
     6. Merging: Copy all converted files into one final archive folder; also copy any raw file
        (if no converted version exists and if not zero-byte or error-marked) preserving folder structure.
     7. Documentation: Generate a combined README.TXT in the final archive’s root that includes:
         - A “READ ME FIRST” overview,
         - A detailed Table of Contents (with summary counts and explanation regarding numeric prefixes),
         - A Key Files and Guidance section,
         - A complete file Index (listing all files with relative paths).
     8. Packaging: If the output archive already exists, prompt for overwrite (in yellow). Then remove zero‑byte files,
        compress the final archive into a ZIP archive, and clean up temporary data.
     9. Final Cleanup: Use a retry loop (with status set to 99%) to remove the temporary folder and release locked files.

.PARAMETER ArchiveFile
   (Optional) Full path to the Windows Intune diagnostic ZIP file.
#>

param(
    [string]$ArchiveFile
)

# --- Pre-run Cleanup: Remove any leftover temporary folders from previous runs ---
$tempRoot = [System.IO.Path]::GetTempPath()
Get-ChildItem -Path $tempRoot -Directory -Filter "LogProcessing_*" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    } catch { }
}

# --- If ArchiveFile parameter is missing or invalid, use a file selector ---
if (-not $ArchiveFile -or -not (Test-Path $ArchiveFile)) {
    Add-Type -AssemblyName System.Windows.Forms
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Filter = "ZIP Files (*.zip)|*.zip"
    $OpenFileDialog.Title = "Select the Microsoft Intune Diagnostic ZIP file to process"
    $DownloadsFolder = [System.IO.Path]::Combine([System.Environment]::GetFolderPath("UserProfile"), "Downloads")
    $OpenFileDialog.InitialDirectory = $DownloadsFolder
    $OpenFileDialog.Multiselect = $false
    if ($OpenFileDialog.ShowDialog() -eq "OK") {
        $ArchiveFile = $OpenFileDialog.FileName
    } else {
        Write-Host "No file selected. Exiting."
        exit
    }
}

# --- Display the archive file being processed ---
Write-Host "Processing archive file: $ArchiveFile"

# --- Immediately display title and credit ---
Write-Host "========================================="
Write-Host "Microsoft Intune Diagnostic Log Processor - Revision 1.14.2"
Write-Host "Created by " -NoNewline; Write-Host "Geeks.Online" -ForegroundColor Blue -NoNewline; Write-Host " in collaboration with ChatGPT"
Write-Host "========================================="

# --- Extract computer name from the archive file name (assumes format: DiagLogs-PCNAME-TIMESTAMP.zip) ---
$BaseFileName = [System.IO.Path]::GetFileNameWithoutExtension($ArchiveFile)
$ComputerName = ($BaseFileName -split "-")[1]

# --- Define temporary folder structure ---
$TempFolder         = Join-Path $tempRoot "LogProcessing_$ComputerName"
$ExtractFolder      = Join-Path $TempFolder "ExtractedLogs"
$OutputFolder       = Join-Path $TempFolder "ConvertedLogs"
$FinalArchiveFolder = Join-Path $TempFolder "FinalArchive"

# Create fresh temporary directories
New-Item -ItemType Directory -Path $ExtractFolder -Force | Out-Null
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
New-Item -ItemType Directory -Path $FinalArchiveFolder -Force | Out-Null

# --- Start Transcript Logging ---
$LogFile = Join-Path $OutputFolder "ScriptLog.txt"
Start-Transcript -Path $LogFile -Append

# --- Helper function: Update progress bar ---
function Update-ProgressBar {
    param(
        [string]$Status,
        [int]$PercentComplete
    )
    Write-Progress -Activity "Processing Diagnostic Logs (Revision 1.14.2)" -Status $Status -PercentComplete $PercentComplete
}

# --- Stage 1: Extract ZIP file ---
Update-ProgressBar -Status "Extracting ZIP file..." -PercentComplete 10
Expand-Archive -Path $ArchiveFile -DestinationPath $ExtractFolder -Force

# --- Stage 2: Expand CAB files ---
Update-ProgressBar -Status "Extracting CAB files..." -PercentComplete 20
$CabFiles = Get-ChildItem -Path $ExtractFolder -Filter "*.cab" -Recurse
foreach ($CabFile in $CabFiles) {
    $CabExtractFolder = Join-Path $ExtractFolder ("{0}_Extracted" -f $CabFile.BaseName)
    New-Item -ItemType Directory -Path $CabExtractFolder -Force | Out-Null
    Write-Verbose "Extracting CAB file: $($CabFile.Name)"
    expand.exe -F:* $CabFile.FullName $CabExtractFolder *> $null
}

# --- Stage 3: Convert Registry Exports (*.reg) to CSV ---
Update-ProgressBar -Status "Converting Registry exports to CSV..." -PercentComplete 30
$RegFiles = Get-ChildItem -Path $ExtractFolder -Filter "*.reg" -Recurse
foreach ($File in $RegFiles) {
    $CsvFile = Join-Path $OutputFolder ("{0}.reg.csv" -f $File.BaseName)
    Write-Verbose "Converting Registry export: $($File.Name)"
    Get-Content $File.FullName | Out-File -Encoding utf8 $CsvFile
}

# --- Stage 4: Convert SetupDiagResults.xml to CSV ---
Update-ProgressBar -Status "Converting SetupDiagResults.xml to CSV..." -PercentComplete 40
$SetupDiagFile = Get-ChildItem -Path $ExtractFolder -Filter "SetupDiagResults.xml" -Recurse | Select-Object -First 1
if ($SetupDiagFile) {
    $CsvFile = Join-Path $OutputFolder "SetupDiagResults.csv"
    Write-Verbose "Converting SetupDiagResults.xml"
    [xml]$xmlData = Get-Content $SetupDiagFile.FullName
    $xmlData.SelectNodes("//Error") | ForEach-Object {
        [PSCustomObject]@{
            Timestamp  = $_.Timestamp
            ErrorCode  = $_.ErrorCode
            Phase      = $_.Phase
            Operation  = $_.Operation
            Message    = $_.Message
        }
    } | Export-Csv -NoTypeInformation -Path $CsvFile
}

# --- Stage 5: Convert Windows Event Logs (*.evtx) to CSV ---
Update-ProgressBar -Status "Converting Windows Event Logs to CSV (this may take several minutes)..." -PercentComplete 50
$EventLogFiles = Get-ChildItem -Path $ExtractFolder -Filter "*.evtx" -Recurse
foreach ($File in $EventLogFiles) {
    $CsvFile = Join-Path $OutputFolder ("{0}.evtx.csv" -f $File.BaseName)
    Write-Verbose "Converting Event Log: $($File.Name)"
    Get-WinEvent -Path $File.FullName -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
        Export-Csv -NoTypeInformation -Path $CsvFile
}

# --- Stage 6: Convert ETL logs (*.etl) to CSV ---
Update-ProgressBar -Status "Converting ETL logs to CSV (this may take several minutes)..." -PercentComplete 60
$ETLFiles = Get-ChildItem -Path $ExtractFolder -Filter "*.etl" -Recurse
foreach ($Log in $ETLFiles) {
    $CsvFile = Join-Path $OutputFolder ("{0}.etl.csv" -f $Log.BaseName)
    if (Test-Path $CsvFile) { Remove-Item $CsvFile -Force }
    Write-Verbose "Converting ETL log: $($Log.Name)"
    tracerpt $Log.FullName -o $CsvFile -of CSV *> $null
}

# --- Stage 7: Merge Converted and Raw Files into Final Archive ---
Update-ProgressBar -Status "Merging files into final archive..." -PercentComplete 70
# Copy all converted files (from OutputFolder) into FinalArchive.
Copy-Item -Path (Join-Path $OutputFolder "*") -Destination $FinalArchiveFolder -Recurse -Force
# Then, iterate over all raw files in ExtractFolder. For processed types,
# if a converted version exists, skip copying the raw file; otherwise, copy it.
$processedExtensions = @(".reg", ".evtx", ".etl")
$specialFiles = @("SetupDiagResults.xml")
$allRawFiles = Get-ChildItem -Path $ExtractFolder -Recurse -File
foreach ($raw in $allRawFiles) {
    if ($raw.Length -eq 0) { continue }
    $shouldCopy = $true
    $ext = $raw.Extension.ToLower()
    $rawName = $raw.Name
    if ($processedExtensions -contains $ext -or $specialFiles -contains $rawName) {
        switch ($ext) {
            ".reg" { $expected = "$($raw.BaseName).reg.csv" }
            ".evtx" { $expected = "$($raw.BaseName).evtx.csv" }
            ".etl" { $expected = "$($raw.BaseName).etl.csv" }
            default { if ($rawName -ieq "SetupDiagResults.xml") { $expected = "SetupDiagResults.csv" } }
        }
        if ($expected) {
            $exists = Get-ChildItem -Path $OutputFolder -Recurse -File -Filter $expected | Select-Object -First 1
            if ($exists) { $shouldCopy = $false }
        }
    }
    if ($shouldCopy -and ($ext -eq ".reg" -or $ext -eq ".xml" -or $ext -eq ".txt")) {
        try {
            $content = Get-Content $raw.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match "No Results\s*-\s*Error") { $shouldCopy = $false }
        } catch { }
    }
    if ($shouldCopy) {
        $relativePath = $raw.FullName.Substring($ExtractFolder.Length + 1)
        $destPath = Join-Path $FinalArchiveFolder $relativePath
        $destDir = Split-Path $destPath -Parent
        if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -Path $raw.FullName -Destination $destPath -Force
    }
}

# --- Stage 8: Generate combined README.TXT with Table of Contents, Key Files, and File Index ---
Update-ProgressBar -Status "Generating combined README.TXT..." -PercentComplete 80
$CombinedReadmePath = Join-Path $FinalArchiveFolder "README.TXT"
$InitialContent = @"
READ ME FIRST – Windows Intune Diagnostic Archive for General Troubleshooting
--------------------------------------------------------------------
Overview:
This archive was generated from a Windows Intune diagnostic file and preprocessed for general troubleshooting.
It contains a merged file structure with two primary categories:
  • Converted Files: These have been processed for easier analysis and are renamed to reflect their original type:
         - *.reg.csv : Converted registry exports.
         - *.evtx.csv : Converted Windows Event Logs.
         - *.etl.csv : Converted ETL logs.
         - SetupDiagResults.csv : Converted from SetupDiagResults.xml.
     Note: Some files may have a numeric prefix (e.g., "(65) Events System Events.evtx.csv"). These numbers may vary by system.
  • Raw Files: Files that were not successfully converted (and are not zero-byte or error-marked) are retained in their original form.
  • ScriptLog.txt: Contains the transcript log of the preprocessing run (for debugging and auditing).
--------------------------------------------------------------------
"@
$InitialContent | Out-File -FilePath $CombinedReadmePath -Encoding UTF8

# Append a Table of Contents (with summary counts).
$AllFiles = Get-ChildItem -Path $FinalArchiveFolder -Recurse -File
$ConvertedFiles = $AllFiles | Where-Object { $_.Name -match "\.(reg\.csv|evtx\.csv|etl\.csv)$" -or $_.Name -eq "SetupDiagResults.csv" }
$RawFiles = $AllFiles | Where-Object { $_.Name -notmatch "\.(reg\.csv|evtx\.csv|etl\.csv)$" -and $_.Name -ne "README.TXT" }
$TOCContent = @"
Table of Contents:
------------------
Converted Files (processed):
    Registry Exports (*.reg.csv): $(( $ConvertedFiles | Where-Object { $_.Name -match "\.reg\.csv" } | Measure-Object).Count) file(s)
    Windows Event Logs (*.evtx.csv): $(( $ConvertedFiles | Where-Object { $_.Name -match "\.evtx\.csv" } | Measure-Object).Count) file(s)
    ETL Logs (*.etl.csv): $(( $ConvertedFiles | Where-Object { $_.Name -match "\.etl\.csv" } | Measure-Object).Count) file(s)
    SetupDiagResults: $(( $ConvertedFiles | Where-Object { $_.Name -eq "SetupDiagResults.csv" } | Measure-Object).Count) file(s)
Raw Files (unconverted):
    Total Raw Files: $(( $RawFiles | Measure-Object).Count) file(s)
------------------
Note: ScriptLog.txt contains the transcript log of the preprocessing run.
"@
$TOCContent | Out-File -FilePath $CombinedReadmePath -Append -Encoding UTF8

# Append Key Files and Guidance.
$KeyFilesContent = @"
Key Files and Guidance:
-------------------------
- (e.g., "(65) Events System Events.evtx.csv"): Contains Windows system event logs for system-level troubleshooting.
- (e.g., "(48) Events Application Events.evtx.csv"): Contains Windows application event logs.
- Registry export files (*.reg.csv): Provide configuration and policy data from the registry.
- ETL log files (*.etl.csv): Offer detailed trace information.
- SetupDiagResults.csv: Contains diagnostic errors from the setup process.
- Command output logs (files ending in output.log): Capture outputs from command-line tools.
-------------------------
"@
$KeyFilesContent | Out-File -FilePath $CombinedReadmePath -Append -Encoding UTF8

# Append complete file Index (relative paths).
$IndexHeader = "Complete File Index (relative paths):" + "`r`n"
$IndexHeader | Out-File -FilePath $CombinedReadmePath -Append -Encoding UTF8
$IndexLines = Get-ChildItem -Path $FinalArchiveFolder -Recurse -File | ForEach-Object {
    $_.FullName.Substring($FinalArchiveFolder.Length + 1)
}
$IndexLines | Out-File -FilePath $CombinedReadmePath -Append -Encoding UTF8

Update-ProgressBar -Status "Removing zero-byte files from final archive..." -PercentComplete 90
Get-ChildItem -Path $FinalArchiveFolder -Recurse -File | Where-Object { $_.Length -eq 0 } | Remove-Item -Force

Update-ProgressBar -Status "Creating final archive ZIP..." -PercentComplete 95
$NewZipFilePath = Join-Path ([System.IO.Path]::GetDirectoryName($ArchiveFile)) ("{0}-GPT.zip" -f ([System.IO.Path]::GetFileNameWithoutExtension($ArchiveFile)))
if (Test-Path $NewZipFilePath) {
    Write-Host "Output archive '$NewZipFilePath' already exists. Overwrite? (Y/N)" -ForegroundColor Yellow
    $overwrite = Read-Host
    if ($overwrite -match "^(y|Y)") {
         Remove-Item -Path $NewZipFilePath -Force
    } else {
         Write-Host "Exiting without overwriting existing archive."
         exit
    }
}
Compress-Archive -Path (Join-Path $FinalArchiveFolder "*") -DestinationPath $NewZipFilePath -Force

Update-ProgressBar -Status "Cleaning up temporary files..." -PercentComplete 99
Stop-Transcript
# Attempt to explicitly remove the ScriptLog.txt file to release handles.
try {
    Remove-Item -Path $LogFile -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Warning: Unable to remove ScriptLog.txt" -ForegroundColor Yellow
}
Start-Sleep -Seconds 10
$maxRetries = 5
$retryCount = 0
$removed = $false
while (-not $removed -and $retryCount -lt $maxRetries) {
    try {
        Remove-Item -Path $TempFolder -Recurse -Force -ErrorAction Stop
        $removed = $true
    } catch {
        Write-Host "Warning: Unable to remove temporary folder. Retrying in 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        $retryCount++
    }
}

# --- Optional Sanity Check ---
$OriginalSize = (Get-Item $ArchiveFile).Length
$NewSize = (Get-Item $NewZipFilePath).Length
if ($NewSize -lt $OriginalSize) {
    Write-Host "Warning: Final archive ($NewSize bytes) is smaller than the original archive ($OriginalSize bytes)." -ForegroundColor Yellow
}

Write-Host "Processed logs have been saved to: $NewZipFilePath"
