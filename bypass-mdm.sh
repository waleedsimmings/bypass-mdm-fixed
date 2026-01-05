#!/bin/bash

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Function to detect volumes
detect_volumes() {
    echo -e "${CYAN}Detecting volumes...${NC}"
    
    # Find system volume (has /etc directory)
    SYSTEM_VOLUME=""
    DATA_VOLUME=""
    
    # Function to check if volume should be skipped
    should_skip_volume() {
        local vol_name="$1"
        # Skip Recovery and other system volumes
        case "$vol_name" in
            *"Recovery"*|*"Preboot"*|*"VM"*|*"macOS Base System"*|*"Update"*|*"com.apple"*)
                return 0  # Should skip
                ;;
            *)
                # Also check if it's a recovery volume by looking for installation files
                if [ -f "/Volumes/$vol_name/System/Installation/Packages/OSInstall.mpkg" ]; then
                    return 0  # Should skip (recovery volume)
                fi
                return 1  # Don't skip
                ;;
        esac
    }
    
    # First pass: Find data volume (prioritize " - Data" volumes)
    for vol in /Volumes/*; do
        if [ -d "$vol" ] && [ "$vol" != "/Volumes" ]; then
            vol_name=$(basename "$vol")
            
            if should_skip_volume "$vol_name"; then
                continue
            fi
            
            # Data volume has /private/var/db/dslocal
            if [ -d "$vol/private/var/db/dslocal" ]; then
                # Prefer volumes with " - Data" suffix for APFS
                if [[ "$vol_name" == *" - Data" ]]; then
                    DATA_VOLUME="$vol"
                    echo -e "${GRN}Found data volume: $vol_name${NC}"
                    break  # Found the best candidate, stop looking
                elif [ -z "$DATA_VOLUME" ]; then
                    # Keep as candidate if no Data volume found yet
                    DATA_VOLUME="$vol"
                    echo -e "${GRN}Found data volume candidate: $vol_name${NC}"
                fi
            fi
        fi
    done
    
    # Second pass: Find system volume
    # If we found a " - Data" volume, try to find its corresponding system volume first
    if [ -n "$DATA_VOLUME" ]; then
        data_name=$(basename "$DATA_VOLUME")
        if [[ "$data_name" == *" - Data" ]]; then
            base_name="${data_name% - Data}"
            if [ -d "/Volumes/$base_name" ] && ! should_skip_volume "$base_name"; then
                SYSTEM_VOLUME="/Volumes/$base_name"
                echo -e "${GRN}Found system volume: $base_name${NC}"
            fi
        fi
    fi
    
    # If we don't have a system volume yet, look for one with /etc/hosts
    if [ -z "$SYSTEM_VOLUME" ]; then
        for vol in /Volumes/*; do
            if [ -d "$vol" ] && [ "$vol" != "/Volumes" ]; then
                vol_name=$(basename "$vol")
                
                if should_skip_volume "$vol_name"; then
                    continue
                fi
                
                # System volume has /etc/hosts
                if [ -f "$vol/etc/hosts" ]; then
                    SYSTEM_VOLUME="$vol"
                    echo -e "${GRN}Found system volume: $vol_name${NC}"
                    break
                fi
            fi
        done
    fi
    
    # For APFS volumes, if we found a " - Data" volume, find its corresponding system volume
    if [ -n "$DATA_VOLUME" ]; then
        data_name=$(basename "$DATA_VOLUME")
        if [[ "$data_name" == *" - Data" ]]; then
            base_name="${data_name% - Data}"
            if [ -d "/Volumes/$base_name" ]; then
                # Verify it's not a recovery volume
                skip=false
                for skip_pattern in "${SKIP_VOLUMES[@]}"; do
                    if [[ "$base_name" == *"$skip_pattern"* ]]; then
                        skip=true
                        break
                    fi
                done
                if [ "$skip" = false ]; then
                    SYSTEM_VOLUME="/Volumes/$base_name"
                    echo -e "${GRN}Found system volume: $base_name${NC}"
                fi
            fi
        fi
    fi
    
    # If we still don't have a system volume, try finding by /var/db/ConfigurationProfiles
    if [ -z "$SYSTEM_VOLUME" ]; then
        for vol in /Volumes/*; do
            if [ -d "$vol" ] && [ "$vol" != "/Volumes" ]; then
                vol_name=$(basename "$vol")
                skip=false
                for skip_pattern in "${SKIP_VOLUMES[@]}"; do
                    if [[ "$vol_name" == *"$skip_pattern"* ]]; then
                        skip=true
                        break
                    fi
                done
                if [ "$skip" = true ]; then
                    continue
                fi
                if [ -d "$vol/var/db/ConfigurationProfiles" ] && [ ! -d "$vol/System/Installation" ]; then
                    SYSTEM_VOLUME="$vol"
                    echo -e "${GRN}Found system volume: $vol_name${NC}"
                    break
                fi
            fi
        done
    fi
    
    if [ -z "$SYSTEM_VOLUME" ] || [ -z "$DATA_VOLUME" ]; then
        echo -e "${RED}Error: Could not detect volumes automatically${NC}"
        echo -e "${YEL}Available volumes:${NC}"
        ls -1 /Volumes/ | grep -v "^$"
        echo ""
        read -p "Enter system volume name (or full path): " system_input
        read -p "Enter data volume name (or full path): " data_input
        
        if [[ "$system_input" == /* ]]; then
            SYSTEM_VOLUME="$system_input"
        else
            SYSTEM_VOLUME="/Volumes/$system_input"
        fi
        
        if [[ "$data_input" == /* ]]; then
            DATA_VOLUME="$data_input"
        else
            DATA_VOLUME="/Volumes/$data_input"
        fi
    fi
    
    # Verify volumes exist
    if [ ! -d "$SYSTEM_VOLUME" ]; then
        echo -e "${RED}Error: System volume not found: $SYSTEM_VOLUME${NC}"
        exit 1
    fi
    
    if [ ! -d "$DATA_VOLUME" ]; then
        echo -e "${RED}Error: Data volume not found: $DATA_VOLUME${NC}"
        exit 1
    fi
    
    # Final verification - make sure we're not using recovery volumes
    system_name=$(basename "$SYSTEM_VOLUME")
    data_name=$(basename "$DATA_VOLUME")
    
    if should_skip_volume "$system_name"; then
        echo -e "${RED}Error: Detected system volume appears to be a recovery volume: $system_name${NC}"
        echo -e "${YEL}Please manually specify the correct volumes${NC}"
        echo -e "${YEL}Available volumes:${NC}"
        ls -1 /Volumes/ | grep -v "^$"
        echo ""
        read -p "Enter system volume name (or full path): " system_input
        read -p "Enter data volume name (or full path): " data_input
        
        if [[ "$system_input" == /* ]]; then
            SYSTEM_VOLUME="$system_input"
        else
            SYSTEM_VOLUME="/Volumes/$system_input"
        fi
        
        if [[ "$data_input" == /* ]]; then
            DATA_VOLUME="$data_input"
        else
            DATA_VOLUME="/Volumes/$data_input"
        fi
    fi
    
    # Verify the data volume has the required directory structure
    if [ ! -d "$DATA_VOLUME/private/var/db/dslocal/nodes/Default" ] && [ ! -d "$DATA_VOLUME/var/db/dslocal/nodes/Default" ]; then
        echo -e "${RED}Error: Data volume does not contain DirectoryService database${NC}"
        echo -e "${YEL}Data volume path: $DATA_VOLUME${NC}"
        echo -e "${YEL}Please verify this is the correct macOS data volume${NC}"
        exit 1
    fi
    
    echo -e "${GRN}Using system volume: $SYSTEM_VOLUME${NC}"
    echo -e "${GRN}Using data volume: $DATA_VOLUME${NC}"
    echo ""
    
    # Ask user to confirm volumes
    echo -e "${YEL}Please verify these are the correct volumes:${NC}"
    echo -e "  System: $(basename "$SYSTEM_VOLUME")"
    echo -e "  Data: $(basename "$DATA_VOLUME")"
    echo ""
    read -p "Are these correct? (y/n, default=y): " confirm_volumes
    confirm_volumes="${confirm_volumes:=y}"
    
    if [[ ! "$confirm_volumes" =~ ^[Yy] ]]; then
        echo -e "${YEL}Available volumes:${NC}"
        ls -1 /Volumes/ | grep -v "^$"
        echo ""
        read -p "Enter system volume name (or full path): " system_input
        read -p "Enter data volume name (or full path): " data_input
        
        if [[ "$system_input" == /* ]]; then
            SYSTEM_VOLUME="$system_input"
        else
            SYSTEM_VOLUME="/Volumes/$system_input"
        fi
        
        if [[ "$data_input" == /* ]]; then
            DATA_VOLUME="$data_input"
        else
            DATA_VOLUME="/Volumes/$data_input"
        fi
        
        echo -e "${GRN}Using system volume: $SYSTEM_VOLUME${NC}"
        echo -e "${GRN}Using data volume: $DATA_VOLUME${NC}"
    fi
    echo ""
}

# Display header
echo -e "${CYAN}Bypass MDM By Assaf Dori (assafdori.com)${NC}"
echo ""

# Prompt user for choice
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot & Exit")
select opt in "${options[@]}"; do
    case $opt in
        "Bypass MDM from Recovery")
            # Detect volumes
            detect_volumes
            
            # Bypass MDM from Recovery
            echo -e "${YEL}Bypass MDM from Recovery${NC}"

            # Create Temporary User
            echo -e "${NC}Create a Temporary User"
            read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
            realName="${realName:=Apple}"
            read -p "Enter Temporary Username (Default is 'Apple'): " username
            username="${username:=Apple}"
            read -p "Enter Temporary Password (Default is '1234'): " passw
            passw="${passw:=1234}"

            # Create User
            dscl_path="$DATA_VOLUME/private/var/db/dslocal/nodes/Default"
            echo -e "${GRN}Creating Temporary User${NC}"
            
            # Verify dscl path exists
            if [ ! -d "$dscl_path" ]; then
                echo -e "${RED}Error: DirectoryService path not found: $dscl_path${NC}"
                echo -e "${YEL}Trying to find correct path...${NC}"
                # Try alternative path
                if [ -d "$DATA_VOLUME/var/db/dslocal/nodes/Default" ]; then
                    dscl_path="$DATA_VOLUME/var/db/dslocal/nodes/Default"
                    echo -e "${GRN}Using alternative path: $dscl_path${NC}"
                else
                    echo -e "${RED}Error: Could not find DirectoryService database${NC}"
                    exit 1
                fi
            fi
            
            # Create Users directory if it doesn't exist
            mkdir -p "$DATA_VOLUME/Users"
            
            # Completely remove user if it already exists (including home directory)
            echo -e "${CYAN}Removing existing user if present...${NC}"
            dscl -f "$dscl_path" localhost -delete "/Local/Default/Users/$username" 2>/dev/null || true
            rm -rf "$DATA_VOLUME/Users/$username" 2>/dev/null || true
            # Remove from admin group
            dscl -f "$dscl_path" localhost -delete "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null || true
            sleep 1
            
            # Create user record step by step with error checking
            echo -e "${CYAN}Creating user record...${NC}"
            if ! dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"; then
                echo -e "${RED}Error: Failed to create user record${NC}"
                exit 1
            fi
            
            # Set basic user properties BEFORE setting password
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
            
            # Create home directory
            mkdir -p "$DATA_VOLUME/Users/$username"
            chmod 755 "$DATA_VOLUME/Users/$username"
            
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
            
            # Set password BEFORE adding to admin group
            echo -e "${CYAN}Setting password...${NC}"
            
            # Set password - for a new user, we can set it directly
            echo -e "${CYAN}Setting password...${NC}"
            
            # Method 1: Try dscl passwd (for new users, this should work without old password)
            # The trick is to pipe the password twice (new password, confirm)
            password_set=false
            
            # Try the standard method first
            if printf "%s\n%s\n" "$passw" "$passw" | dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" 2>&1 | grep -vq "eDSOperationFailed\|Permission denied\|Error"; then
                sleep 1
                # Verify password was set by checking AuthenticationAuthority
                if dscl -f "$dscl_path" localhost -read "/Local/Default/Users/$username" AuthenticationAuthority 2>/dev/null | grep -q "ShadowHash\|Kerberos"; then
                    password_set=true
                    echo -e "${GRN}Password set successfully${NC}"
                fi
            fi
            
            # Method 2: If that failed, set up for password-less login
            if [ "$password_set" = false ]; then
                echo -e "${YEL}Password setting had issues. Setting up account for flexible login...${NC}"
                
                # Remove AuthenticationAuthority to allow multiple login methods
                dscl -f "$dscl_path" localhost -delete "/Local/Default/Users/$username" AuthenticationAuthority 2>/dev/null || true
                
                # Try one more time with a simpler approach
                echo "$passw" | dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" - 2>&1 | grep -v "Permission denied" || true
                
                echo -e "${YEL}Login options to try:${NC}"
                echo -e "  1. Username: $username, Password: $passw"
                echo -e "  2. Username: $username, Password: (leave blank, press Enter)"
                echo -e "  3. Username: $username, Password: Apple (common default)"
            fi
            
            # Ensure user is in admin group
            dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null || \
            dscl -f "$dscl_path" localhost -create "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null || true
            
            # Verify user account exists and is properly configured
            echo -e "${CYAN}Verifying user account...${NC}"
            if dscl -f "$dscl_path" localhost -read "/Local/Default/Users/$username" UniqueID >/dev/null 2>&1; then
                echo -e "${GRN}User account verified${NC}"
                echo -e "${CYAN}Account details:${NC}"
                dscl -f "$dscl_path" localhost -read "/Local/Default/Users/$username" RealName UniqueID NFSHomeDirectory 2>/dev/null | head -5
            else
                echo -e "${RED}Warning: User account verification failed${NC}"
            fi
            
            echo -e "${GRN}User created successfully${NC}"

            # Block MDM domains
            echo "0.0.0.0 deviceenrollment.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 mdmenrollment.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 iprofiles.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo -e "${GRN}Successfully blocked MDM & Profile Domains${NC}"

            # Remove configuration profiles and mark setup as done
            mkdir -p "$DATA_VOLUME/private/var/db"
            touch "$DATA_VOLUME/private/var/db/.AppleSetupDone"
            
            # Also mark setup done in system volume
            mkdir -p "$SYSTEM_VOLUME/var/db"
            touch "$SYSTEM_VOLUME/var/db/.AppleSetupDone" 2>/dev/null || true
            
            # Disable setup assistants
            mkdir -p "$DATA_VOLUME/private/var/db/.AppleSetupDone" 2>/dev/null || true
            defaults write "$DATA_VOLUME/private/var/db/.AppleSetupDone" -bool true 2>/dev/null || true
            
            # Remove MDM configuration profiles
            mkdir -p "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings"
            rm -rf "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
            rm -rf "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
            touch "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
            touch "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"
            
            # Block additional MDM/enterprise enrollment domains (including Microsoft)
            echo "0.0.0.0 enterprise.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 gdmf.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 albert.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 ocsp.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 login.microsoftonline.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 login.microsoft.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 account.microsoft.com" >> "$SYSTEM_VOLUME/etc/hosts"
            
            # Disable Microsoft/Office enrollment
            mkdir -p "$DATA_VOLUME/Library/Preferences"
            defaults write "$DATA_VOLUME/Library/Preferences/com.microsoft.office.plist" OfficeAutoSignIn -bool false 2>/dev/null || true
            
            # Ensure login window shows local users
            mkdir -p "$DATA_VOLUME/Library/Preferences"
            defaults write "$DATA_VOLUME/Library/Preferences/com.apple.loginwindow.plist" SHOWOTHERUSERS_MANAGED -bool false 2>/dev/null || true
            defaults write "$DATA_VOLUME/Library/Preferences/com.apple.loginwindow.plist" SHOWFULLNAME -bool true 2>/dev/null || true
            
            # Create a plist to skip cloud account setup
            mkdir -p "$DATA_VOLUME/private/var/db"
            cat > "$DATA_VOLUME/private/var/db/.CloudSetupDone" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CloudSetupDone</key>
    <true/>
</dict>
</plist>
EOF

            echo -e "${GRN}MDM enrollment has been bypassed!${NC}"
            echo ""
            echo -e "${CYAN}Login Instructions:${NC}"
            echo -e "${YEL}After reboot, try these login methods IN ORDER:${NC}"
            echo ""
            echo -e "${GRN}Method 1 (try first):${NC}"
            echo -e "  Username: ${GRN}$username${NC}"
            echo -e "  Password: ${GRN}$passw${NC}"
            echo ""
            echo -e "${GRN}Method 2 (if Method 1 fails):${NC}"
            echo -e "  Username: ${GRN}$username${NC}"
            echo -e "  Password: ${YEL}(leave blank, just press Enter)${NC}"
            echo ""
            echo -e "${GRN}Method 3 (if still having issues):${NC}"
            echo -e "  Click ${GRN}'Local login'${NC} button if available"
            echo -e "  Or press ${GRN}Escape${NC} or ${GRN}Cmd+Q${NC} to dismiss Microsoft screen"
            echo ""
            echo -e "${YEL}If screen keeps flickering, the account may need password reset after first login${NC}"
            echo ""
            echo -e "${NC}Exit terminal and reboot your Mac.${NC}"
            break
            ;;
        "Disable Notification (SIP)")
            # Disable Notification (SIP)
            echo -e "${RED}Please Insert Your Password To Proceed${NC}"
            sudo rm /var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
            sudo rm /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
            sudo touch /var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
            sudo touch /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
            break
            ;;
        "Disable Notification (Recovery)")
            # Detect volumes
            detect_volumes
            
            # Disable Notification (Recovery)
            mkdir -p "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings"
            rm -rf "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
            rm -rf "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
            touch "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
            touch "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"
            break
            ;;
        "Check MDM Enrollment")
            # Check MDM Enrollment
            echo ""
            echo -e "${GRN}Check MDM Enrollment. Error is success${NC}"
            echo ""
            echo -e "${RED}Please Insert Your Password To Proceed${NC}"
            echo ""
            sudo profiles show -type enrollment
            break
            ;;
        "Reboot & Exit")
            # Reboot & Exit
            echo "Rebooting..."
            reboot
            break
            ;;
        *) echo "Invalid option $REPLY" ;;
    esac
done

