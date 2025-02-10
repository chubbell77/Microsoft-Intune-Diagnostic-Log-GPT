# Microsoft-Intune-Diagnostic-Log-GPT
Converts Microsoft Intune Windows Diagnostic files to .CSV files to allow ChatGPT to read them and use them for troubleshooting 

## Features

- **Pre-run Cleanup:** Removes any leftover temporary folders.
- **Flexible Input:** Accepts a ZIP file path as a parameter or prompts you with a file selector.
- **Extraction & Expansion:** Unzips the archive and expands any CAB files.
- **Conversion:** Processes registry exports (`*.reg`), XML files (`SetupDiagResults.xml`), Windows Event Logs (`*.evtx`), and ETL logs (`*.etl`) to CSV.
- **Merging & Documentation:** Merges all converted files into a final archive folder and creates a comprehensive `README.TXT` with a table of contents, key file descriptions, and a full file index.
- **Packaging:** Compresses the final archive to a ZIP file and performs cleanup with a retry loop to remove temporary files.
- **Optional Sanity Check:** Compares the final archive size to the original.

## Prerequisites

- **Windows PowerShell 5.1 or later**
- Tools such as `expand.exe` and `tracerpt` (typically available on Windows systems)

## Usage

Open PowerShell and run the script like this:

```powershell
# With an archive file provided:
.\IntuneLogProcessor.ps1 -ArchiveFile "C:\Path\To\DiagLogs-PCNAME-TIMESTAMP.zip"

# Or simply run the script and select the file via the file selector:
.\IntuneLogProcessor.ps1
