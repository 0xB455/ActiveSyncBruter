# ActiveSyncBruter

ActiveSyncBruter is a penetration testing tool designed to enumerate and brute-force credentials against Microsoft Exchange ActiveSync endpoints. It supports both single-credential checks and bulk testing from a file. The tool employs a two-phase approach to quickly filter out invalid credentials and then re‑verify potential valid candidates.

## Features

- **Dual Modes:**  
  - **File Mode:** Test multiple credentials from a file.  
  - **Single Mode:** Test a single username (with an optional password) with secure prompt support.
- **Two-Phase Verification (File Mode):**  
  - **Phase 1:** A quick check using a baseline-derived timeout threshold to mark potential valid credentials.  
  - **Phase 2:** A final, longer verification for credentials flagged as potentially valid.
- **Customizable Timeouts:**  
  - Supports configurable timeout thresholds for both quick (Phase 1) and final (Phase 2) checks.
  - If no quick timeout is provided in File Mode, the tool computes a baseline by sending test requests with random usernames and sets the threshold to twice the average response time (with a minimum threshold of 1 second).
- **Domain Handling:**  
  - Automatically appends a specified domain to usernames that do not already include an "@".
- **Optional Phase 2 Skipping:**  
  - Use the `-SkipFinal` switch in File Mode to run only Phase 1 checks, saving time when testing large lists.

## Command Types (CmdType)

Each command type is implemented as a minimal WBXML payload. The choice of which command to use depends on the environment and what behavior you wish to observe. ActiveSyncBruter was initially built with the Ping command in mind because its inherent delay can serve as an indicator of valid credentials, but the tool is flexible enough to support other commands as needed.

ActiveSyncBruter currently supports three ActiveSync command types:

- **Ping:**
The default command, Ping, is implemented as a minimal WBXML request. Its design in the ActiveSync protocol is to keep a connection open for a specified heartbeat interval (the payload’s 7th byte is set to 0x0A, representing 10 seconds).
A valid credential on a Ping command causes the server to wait for the heartbeat, leading to a delayed (or even timeout) response. This behavior is used in the quick-check phase: if a credential causes a long response time or timeout, it is flagged as potentially valid.

- **Options:**
The Options command returns server capabilities and configuration.
Although the minimal Options payload is implemented here, some environments might require a more fully formed payload. Options can be used when you need to quickly verify that the endpoint is responsive and to potentially gather configuration details.

- **FolderSync:**
The FolderSync command is implemented as a minimal request, typically with a sync key of "0" (used for new devices).
FolderSync returns a list of folders (such as Inbox, Calendar, etc.) and normally responds quickly. It can be used as an alternative method for checking credential validity when a Ping response might be affected by long heartbeat intervals.


## Requirements

- PowerShell 5.0 or later (Windows PowerShell or PowerShell Core)
- Network access to the target Exchange ActiveSync endpoint (e.g., `https://mail.example.com/Microsoft-Server-ActiveSync`)

## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/0xB455/ActiveSyncBruter.git
   ```

2. Navigate to the project directory:

   ```bash
   cd ActiveSyncBruter
   ```

## Usage

The tool is run from the command line. It supports two modes:

### File Mode (Multiple Credentials)

In File Mode, supply a credentials file where each line contains a username and password separated by whitespace. Use the `-CredFile` switch and optionally specify the target domain using `-Domain`. For example:

```powershell
.\ActiveSyncBruter.ps1 -Hostname "mail.example.com" -CredFile "C:\path\to\credentials.txt" -CmdType Ping -OutputFile "C:\path\to\output.txt" -Domain "example.com"
```

- **Parameters:**
  - `-Hostname`: The target ActiveSync server (e.g., `mail.example.com`).
  - `-CredFile`: Path to the file containing credentials (each line in the format `username password`).
  - `-CmdType`: The ActiveSync command to use. Valid options: `Ping`, `Options`, or `FolderSync` (default is `Ping`).
  - `-OutputFile`: Path to the file where output and results will be saved.
  - `-Domain`: Optional domain to append to usernames that do not include an "@".
  - `-QuickTimeoutSec`: (Optional) Quick check timeout threshold in seconds. If not provided, a baseline is computed.
  - `-FinalTimeoutSec`: Final check timeout in seconds. Defaults to 20 seconds.
  - `-SkipFinal`: (Optional) If specified, the tool will perform only Phase 1 checks (quick check) and skip the final verification phase.

### Single Mode (One Credential Check)

In Single Mode, supply a username using the `-Username` switch. You can also optionally provide a password via `-Password`. If the password is omitted, you will be securely prompted to enter it. For example:

**With both username and password:**

```powershell
.\ActiveSyncBruter.ps1 -Hostname "mail.example.com" -Username "user1" -Password "SuperSecret123" -CmdType Ping -OutputFile "C:\path\to\output.txt" -Domain "example.com"
```

**With username only (password will be prompted):**

```powershell
.\ActiveSyncBruter.ps1 -Hostname "mail.example.com" -Username "user1" -CmdType Ping -OutputFile "C:\path\to\output.txt" -Domain "example.com"
```

### How It Works

#### File Mode Workflow

1. **Baseline Measurement (if `-QuickTimeoutSec` is not provided):**  
   The tool sends 5 test requests with randomly generated usernames to calculate an average response time. It then sets the quick-check threshold to twice the average response time, with a minimum of 1 second.

2. **Phase 1: Quick Check:**  
   Each credential in the file is tested against the ActiveSync endpoint using the quick timeout threshold. Credentials with responses that take longer than the threshold (or that time out) are flagged as potentially valid.

3. **Phase 2: Final Check:**  
   Unless the `-SkipFinal` switch is used, the flagged credentials are re‑tested using a longer timeout (`-FinalTimeoutSec`, default 20 seconds). In this phase, timeouts are treated as valid responses.

4. **Output:**  
   The tool writes detailed results (including response codes and runtimes in milliseconds) to the console and saves them to the specified output file. The final summary lists all credentials that passed final verification (or potential valid ones if Phase 2 is skipped).

#### Single Mode Workflow

For a single credential, the tool performs one check (using the final timeout) and reports the result.

## Disclaimer

**ActiveSyncBruter** is intended for authorized penetration testing and security assessment only. Use this tool only on systems for which you have explicit permission to test. The author assumes no liability for misuse or damage resulting from the use of this tool.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
