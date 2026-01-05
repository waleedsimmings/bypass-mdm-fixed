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
    
    # Check all mounted volumes
    for vol in /Volumes/*; do
        if [ -d "$vol" ] && [ "$vol" != "/Volumes" ]; then
            vol_name=$(basename "$vol")
            # Skip Recovery and other system volumes
            if [[ "$vol_name" == *"Recovery"* ]] || [[ "$vol_name" == *"Preboot"* ]] || [[ "$vol_name" == *"VM"* ]]; then
                continue
            fi
            
            # System volume has /etc/hosts
            if [ -f "$vol/etc/hosts" ]; then
                SYSTEM_VOLUME="$vol"
                echo -e "${GRN}Found system volume: $vol_name${NC}"
            fi
            
            # Data volume has /private/var/db/dslocal
            if [ -d "$vol/private/var/db/dslocal" ]; then
                DATA_VOLUME="$vol"
                echo -e "${GRN}Found data volume: $vol_name${NC}"
            fi
        fi
    done
    
    # If we found a data volume but no system volume, try to find system volume by checking for /var/db/ConfigurationProfiles
    if [ -z "$SYSTEM_VOLUME" ]; then
        for vol in /Volumes/*; do
            if [ -d "$vol" ] && [ "$vol" != "/Volumes" ]; then
                vol_name=$(basename "$vol")
                if [[ "$vol_name" == *"Recovery"* ]] || [[ "$vol_name" == *"Preboot"* ]] || [[ "$vol_name" == *"VM"* ]]; then
                    continue
                fi
                if [ -d "$vol/var/db/ConfigurationProfiles" ]; then
                    SYSTEM_VOLUME="$vol"
                    echo -e "${GRN}Found system volume: $vol_name${NC}"
                    break
                fi
            fi
        done
    fi
    
    # If still no system volume, try the data volume's parent (for APFS volumes)
    if [ -z "$SYSTEM_VOLUME" ] && [ -n "$DATA_VOLUME" ]; then
        # For APFS, the data volume might be named "VolumeName - Data"
        data_name=$(basename "$DATA_VOLUME")
        if [[ "$data_name" == *" - Data" ]]; then
            base_name="${data_name% - Data}"
            if [ -d "/Volumes/$base_name" ]; then
                SYSTEM_VOLUME="/Volumes/$base_name"
                echo -e "${GRN}Found system volume: $base_name${NC}"
            fi
        fi
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

