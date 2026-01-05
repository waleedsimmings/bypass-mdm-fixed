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
    
    echo -e "${GRN}Using system volume: $SYSTEM_VOLUME${NC}"
    echo -e "${GRN}Using data volume: $DATA_VOLUME${NC}"
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
            
            # Create Users directory if it doesn't exist
            mkdir -p "$DATA_VOLUME/Users"
            
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" 2>/dev/null || true
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh" 2>/dev/null || true
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName" 2>/dev/null || true
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501" 2>/dev/null || true
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" 2>/dev/null || true
            mkdir -p "$DATA_VOLUME/Users/$username"
            dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" 2>/dev/null || true
            dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" 2>/dev/null || true
            dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null || true

            # Block MDM domains
            echo "0.0.0.0 deviceenrollment.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 mdmenrollment.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo "0.0.0.0 iprofiles.apple.com" >> "$SYSTEM_VOLUME/etc/hosts"
            echo -e "${GRN}Successfully blocked MDM & Profile Domains${NC}"

            # Remove configuration profiles
            mkdir -p "$DATA_VOLUME/private/var/db"
            touch "$DATA_VOLUME/private/var/db/.AppleSetupDone"
            
            mkdir -p "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings"
            rm -rf "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
            rm -rf "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
            touch "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
            touch "$SYSTEM_VOLUME/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"

            echo -e "${GRN}MDM enrollment has been bypassed!${NC}"
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

