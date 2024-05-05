#!/usr/bin/env bash

LOG_FUNC="https://raw.githubusercontent.com/arghpy/functions/main/log_functions.sh"
SECOND_SCRIPT="https://raw.githubusercontent.com/arghpy/gentoo_install/main/installation_part2.sh"

# Sourcing log functions
wget "${LOG_FUNC}"
# shellcheck disable=SC1091
if source log_functions.sh; then
    log_info "sourced log_functions.sh"
else
    echo "Error! Could not source log_functions.sh"
    exit 1
fi

# Downloading the second part of installation
if wget "${SECOND_SCRIPT}"; then
    log_info "Downloaded the second part of the installation"
else
    log_error "Couldn't download the second part of the installation. Aborting..."
    exit 1
fi

# Check for internet
check_internet() {
    log_info "Check Internet"
	if ! ping -c1 -w1 8.8.8.8 > /dev/null 2>&1; then
        log_error "No Internet Connection"
        log_info "Visit https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Networking"
        log_info "Optionally use 'links https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Networking'"
        exit 1
    else
        log_ok "Connected to internet"
	fi
}

# Selecting the disk to install on
disks() {
    log_info "Select installation disk"
    LIST="$(lsblk -d -n | grep -v "loop" | awk '{print $1, $4}' | nl -s") ")"
    echo "${LIST}"
    OPTION=""

    # shellcheck disable=SC2143
    while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
        printf "Choose a disk (e.g.: 1): "
        read -r OPTION
    done

    DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"

    log_ok "DONE"
}

# Creating partitions
partitioning() {
    log_info "Partitioning disk"
    if [[ -n $(ls /sys/firmware/efi/efivars 2>/dev/null) ]];then

        MODE="UEFI"

        parted --script /dev/"${DISK}" mklabel gpt

        parted --script /dev/"${DISK}" mkpart fat32 2048s 1GiB
        parted --script /dev/"${DISK}" set 1 esp on

        parted --script /dev/"${DISK}" mkpart linux-swap 1GiB 5GiB
        parted --script /dev/"${DISK}" mkpart ext4 5GiB 35GiB
        parted --script /dev/"${DISK}" mkpart ext4 35GiB 100%
        parted --script /dev/"${DISK}" align-check optimal 1 
    else

        MODE="BIOS"

        parted --script /dev/"${DISK}" mklabel msdos
        parted --script /dev/"${DISK}" mkpart primary ext4 2048s 35GiB
        parted --script /dev/"${DISK}" mkpart primary linux-swap 35GiB 39GiB
        parted --script /dev/"${DISK}" mkpart primary ext4 39GiB 100%
        parted --script /dev/"${DISK}" align-check optimal 1 
    fi

    log_ok "DONE"

}


# Formatting partitions
formatting() {

    log_info "Formatting partitions"
    PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

    if [[ "${MODE}" == "UEFI" ]]; then

        BOOT_P=$(echo "$PARTITIONS" | sed -n '1p')
        mkfs.vfat -F32 /dev/"${BOOT_P}"

        SWAP_P=$(echo "$PARTITIONS" | sed -n '2p')
        ROOT_P=$(echo "$PARTITIONS" | sed -n '3p')
        HOME_P=$(echo "$PARTITIONS" | sed -n '4p')
    elif [[ "${MODE}" == "BIOS" ]]; then 
        ROOT_P=$(echo "$PARTITIONS" | sed -n '1p')
        SWAP_P=$(echo "$PARTITIONS" | sed -n '2p')
        HOME_P=$(echo "$PARTITIONS" | sed -n '3p')

    fi

    mkswap /dev/"${SWAP_P}"
    swapon /dev/"${SWAP_P}"
    mkfs.ext4 -F /dev/"${HOME_P}"
    mkfs.ext4 -F /dev/"${ROOT_P}"

    log_ok "DONE"
}


# Mounting partitons
mounting() {
    log_info "Mounting partitions"

    mkdir --parents /mnt/gentoo
    mount /dev/"${ROOT_P}" /mnt/gentoo

    mkdir --parents /mnt/gentoo/home
    mount /dev/"${HOME_P}" /mnt/gentoo/home

    log_ok "DONE"
}

# Configuring date
date_config() {
    log_info "Configuring time with chrony"
    chronyd -q
    log_ok "DONE"
}

# Downloading and unarchiving stage3 tarball
download_and_configure_stage3() {
    log_info "Downloading and setting stage3 tarball"
    STAGE="https://distfiles.gentoo.org/releases/amd64/autobuilds/20230827T170145Z/stage3-amd64-openrc-20230827T170145Z.tar.xz"

    pushd /mnt/gentoo || exit 1

    wget "${STAGE}"
    tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
    rm stage3-*.tar.xz

    popd || exit 1

    log_ok "DONE"
}

# Configuring /etc/portage/make.conf
make_conf_portage() {
    log_info "Configuring /etc/portage/make.conf"

    MAKE_CONF="/mnt/gentoo/etc/portage/make.conf"

    COMMON_FLAGS_OLD="$(grep "^COMMON_FLAGS=" "${MAKE_CONF}")"
    COMMON_FLAGS_NEW='COMMON_FLAGS="-march=native -O2 -pipe"'
    CORES="$(nproc)"
    MAKEOPTS="MAKEOPTS=\"-j${CORES}\""
    USE='USE="X matroska blueray archive fontconfig truetype xml x264 x265 minimal postproc dbus acl alsa grub pulseaudio networkmanager -gnome -kde"'

    # Changing COMMON_FLAGS
    sed -i "s|${COMMON_FLAGS_OLD}|${COMMON_FLAGS_NEW}|g" "${MAKE_CONF}"

    # Appending MAKEOPTS
    echo "${MAKEOPTS}" >> "${MAKE_CONF}"
    echo "${USE}" >> "${MAKE_CONF}"

    log_ok "DONE"
}

# Selecting mirrors
select_mirrors() {
    log_info "Selecting mirrors"

    mirrorselect -i -o >> /mnt/gentoo/etc/portage/make.conf

    log_ok "DONE"
}

# Configure Gentoo ebuild repository
config_ebuild_repo() {
    log_info "Configure Gentoo ebuild repository"

    mkdir --parents /mnt/gentoo/etc/portage/repos.conf
    cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

    log_ok "DONE"
}

# Copying DNS info
dns_copy() {
    log_info "Copying DNS info"

    cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

    log_ok "DONE"
}

# Mounting the necessary filesystems
mounting_filesystems() {
    log_info "Mounting the necessary filesystems"

    mount --types proc /proc /mnt/gentoo/proc
    mount --rbind /sys /mnt/gentoo/sys
    mount --make-rslave /mnt/gentoo/sys
    mount --rbind /dev /mnt/gentoo/dev
    mount --make-rslave /mnt/gentoo/dev
    mount --bind /run /mnt/gentoo/run
    mount --make-slave /mnt/gentoo/run

    log_ok "DONE"
}

# Enter the new environment
enter_environment() {
    log_info "Copying the second installation part to the new environment"
    chmod +x installation_part2.sh
    cp installation_part2.sh /mnt/gentoo/
    log_ok "DONE"

    log_info "Removing installation_part1.sh and log_functions.sh"
    log_info "Entering the new environment"
    log_info "Run the second part of the script: './installation_part2.sh ${MODE} ${DISK}'"
    rm -f installation_part1.sh log_functions.sh
    chroot /mnt/gentoo /bin/bash
}


# Main function to run all program
main() {
    check_internet
    disks
    partitioning
    formatting
    mounting
    date_config
    download_and_configure_stage3
    make_conf_portage
    select_mirrors
    config_ebuild_repo
    dns_copy
    mounting_filesystems
    enter_environment
}

main
