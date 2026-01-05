# Bypass MDM - Fixed Version

This is a fixed version of the [bypass-mdm](https://github.com/assafdori/bypass-mdm) script that automatically detects volume names instead of requiring hardcoded "Macintosh HD" and "Data" volume names.

## What's Fixed

- **Auto-detection of volumes**: Automatically detects your system and data volumes regardless of their names
- **Works with custom volume names**: No longer fails if your drive is named something other than "Macintosh HD"
- **Better error handling**: Creates necessary directories and handles edge cases
- **Fallback option**: If auto-detection fails, prompts for manual volume input

## Usage

In Recovery Mode Terminal, run:

```bash
curl https://raw.githubusercontent.com/YOUR_USERNAME/bypass-mdm-fixed/main/bypass-mdm.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

Replace `YOUR_USERNAME` with your GitHub username.

## Original Script

Based on the original script by [Assaf Dori](https://github.com/assafdori/bypass-mdm).

## Prerequisites

- **It is advised to erase the hard-drive prior to starting.**
- **It is advised to re-install MacOS using an external flash drive.**
- **Device language needs to be set to English, it can be changed afterwards.**

## Instructions

1. Long press Power button to forcefully shut down your Mac.
2. Hold the power button to start your Mac & boot into recovery mode.
3. Connect to WiFi to activate your Mac.
4. Enter Recovery Mode & Open Safari.
5. Navigate to this repository and copy the curl command above.
6. Launch Terminal (Utilities > Terminal).
7. Paste (CMD + V) and Run the script (ENTER).
8. Input 1 for Autobypass.
9. Press Enter to leave the default username 'Apple'.
10. Press Enter to leave the default password '1234'.
11. Wait for the script to finish & Reboot your Mac.
12. Sign in with user (Apple) & password (1234)
13. Skip all setup (Apple ID, Siri, Touch ID, Location Services)
14. Once on the desktop navigate to System Settings > Users and Groups, and create your real Admin account.
15. Log out of the Apple profile, and sign in into your real profile.
16. Feel free set up properly now (Apple ID, Siri, Touch ID, Location Services).
17. Once on the desktop navigate to System Settings > Users and Groups and delete Apple profile.

## Disclaimer

Use at your own risk. This script modifies system files and bypasses MDM enrollment.

