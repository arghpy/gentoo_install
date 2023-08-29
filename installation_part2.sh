#!/usr/bin/env bash

MODE="${1}"
DISK="${2}"

LOG_FUNC="https://raw.githubusercontent.com/arghpy/functions/main/log_functions.sh"
DEP_FILE="https://raw.githubusercontent.com/arghpy/gentoo_installation/main/dependencies.txt"

# Sourcing log functions
wget "${LOG_FUNC}"
if source log_functions.sh; then
    log_info "sourced log_functions.sh"
else
    echo "Error! Could not source log_functions.sh"
    exit -1
fi

# Preparing environment
prep_env() {
    log_info "Preparing environment"
    source /etc/profile
    export PS1="(chroot) ${PS1}"
    log_ok "DONE"
}

# Mounting boot partition
mount_boot() {
    log_info "Mounting boot partition"

    PARTITIONS=$(lsblk --list --noheadings /dev/"$DISK" | tail -n +2 | awk '{print $1}')
    BOOT_P=$(echo "$PARTITIONS" | sed -n '1p')

    mount "${BOOT_P}" /boot

    log_ok "DONE"
}

# Configure portage
configure_portage() {
    log_info "Configure portage"

    log_info "Installing a Gentoo ebuild repository snapshot from the web"
    emerge-webrsync
    log_ok "DONE"

    log_info "Updating the @world set"
    emerge -q --verbose --update --deep --newuse @world
    log_ok "DONE"

    log_info "Configuring CPU_FLAGS"
    emerge -q app-portage/cpuid2cpuflags
    echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
    log_ok "DONE"

    log_info "Configuring VIDEO_CARDS"

    GPU="$(lspci | grep VGA)"

    if echo "${GPU}" | grep -i intel; then
        VIDEO_CARDS="VIDEO_CARDS=\"intel\""
    elif echo "${GPU}" | grep -i nvidia; then 
        VIDEO_CARDS="VIDEO_CARDS=\"nouveau\""
        emerge x11-drivers/nvidia-drivers
    elif echo "${GPU}" | grep -i amd; then 
        VIDEO_CARDS="VIDEO_CARDS=\"radeon\""
    fi

    echo "${VIDEO_CARDS}" >> /etc/portage/make.conf

    log_ok "DONE"

    log_ok "DONE"
}

# Setting the timezone
setting_timezone() {
    log_info "Setting the timezone"
    
    echo "Europe/Bucharest" > /etc/timezone
    emerge --config sys-libs/timezone-data

    log_ok "DONE"
}

# Configuring locales
configure_locales() {
    log_info "Configuring locales"

    echo "en_US ISO-8859-1" >> /etc/locale.gen
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    
    # create file
    echo "LANG=\"en_US.UTF-8\"" > /etc/env.d/02locale
    
    # append to file
    echo "LC_COLLATE=\"en_US.UTF-8\"" >> /etc/env.d/02locale

    env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

    log_ok "DONE"
}

# Configure and install kernel
configure_and_install_kernel() {
    log_info "Configure and install kernel"

    # create file
    echo "# Accepting the license for linux-firmware" > /etc/portage/package.license

    # append to file
    echo "sys-kernel/linux-firmware linux-fw-redistributable" >> /etc/portage/package.license
    echo "" >> /etc/portage/package.license
    echo "# Accepting any license that permits redistribution" >> /etc/portage/package.license
    echo "sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE" >> /etc/portage/package.license


    log_info "Installing linux-firmware"
    emerge -q sys-kernel/linux-firmware
    if lscpu | grep "^Model name" | grep -i intel; then
        emerge sys-firmware/intel-microcode
        emerge x11-drivers/xf86-video-intel
    fi
    log_ok "DONE"

    log_info "Installing the kernel"
    emerge -q sys-kernel/installkernel-gentoo
    emerge -q sys-kernel/gentoo-kernel
    log_ok "DONE"

    log_info "Cleaning up"
    emerge --depclean
    log_ok "DONE"

    log_ok "DONE"
}

# Generating the fstab
generate_fstab() {
    log_info "Generating the fstab"
    emerge sys-fs/genfstab
    genfstab -U / >> /etc/fstab
    log_ok "DONE"
}

# Generate hostname
generate_hostname() {
    log_info "Generate hostname"
    echo gentoo > /etc/hostname
    log_ok "DONE"
}

# Enable networking
enable_network() {
    log_info "Enable networking"
    emerge -q net-misc/dhcpcd
    rc-update add dhcpcd default
    rc-service dhcpcd start
    log_ok "DONE"
}

# Change root password
change_root_password() {
    log_info "Change root password"
    while ! passwd ; do
        sleep 1
    done
    log_ok "DONE"
}

# Installing tools
install_tools() {
    log_info "Installing tools"
    log_info "system logger"
    emerge -q app-admin/sysklogd
    rc-update add sysklogd default
    log_ok "DONE"

    log_info "Cron daemon"
    emerge -q sys-process/cronie
    rc-update add cronie default
    log_ok "DONE"

    log_info "File indexing"
    emerge -q sys-apps/mlocate
    log_ok "DONE"

    log_info "enabling sshd"
    rc-update add sshd default
    log_ok "DONE"

    log_info "bash completion"
    emerge -q app-shells/bash-completion
    log_ok "DONE"

    log_info "Time Synchronization"
    emerge -q net-misc/chrony
    rc-update add chronyd default
    log_ok "DONE"

    log_info "udev scheduler"
    emerge -q sys-block/io-scheduler-udev-rules
    log_ok "DONE"

    log_info "Wireless tools"
    emerge -q net-wireless/iw net-wireless/wpa_supplicant
    log_ok "DONE"
    log_ok "DONE"
}

# Install packages
install_packages() {
    log_info "Install packages"
    wget "${DEP_FILE}"
    DEPLIST="$(sed -e 's/#.*$//' -e '/^$/d' dependencies.txt | tr '\n' ' ')"
    emerge -q "${DEPLIST}"
    log_ok "DONE"
}

# Installing grub and creating configuration
grub() {
    log_info "Installing and configuring grub"
	if [[ "${MODE}" == "UEFI" ]]; then
        echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
        emerge -q sys-boot/grub
        grub-install --target=x86_64-efi --efi-directory=/boot
		grub-mkconfig -o /boot/grub/grub.cfg
	elif [[ "${MODE}" == "BIOS" ]]; then
        emerge -q --verbose sys-boot/grub
		grub-install /dev/"${DISK}"
		grub-mkconfig -o /boot/grub/grub.cfg
	else
		log_error "An error occured at grub step. Exiting..."
		exit -1
	fi
    log_ok "DONE"
}

# Set user and password
set_user() {
    log_info "Setting user account"

	NAME=$(whiptail --inputbox "Please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit -1

    log_info "Adding user to users, audio, video and wheel group"
	useradd -m -g wheel,users,audio,video -s /bin/zsh "${NAME}"

	export REPODIR="/home/${NAME}/.local/src"
	mkdir --parents "${REPODIR}"
	chown -R "${NAME}":wheel "$(dirname "${REPODIR}")"

    log_info "Setting up user password"
	printf "\n\nEnter password for %s\n\n" "$NAME"

    while ! passwd "${NAME}"; do
        sleep 1
    done

    log_ok "DONE"
}


prep_env
mount_boot
configure_portage
setting_timezone
configure_locales
configure_and_install_kernel
generate_fstab
generate_hostname
enable_network
change_root_password
install_tools
install_packages
grub
set_user

log_info "Adding wheel to sudoers"
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

log_info "Configuring the user's home directory"
rm -rf /home/"${NAME}"/* 
rm -rf /home/"${NAME}"/.* 
sudo -u "${NAME}" git -C /home/"${NAME}"/ clone "${CONFIG_GIT}"
mv /home/"${NAME}"/dotfiles/* /home/"${NAME}"/.
mv /home/"${NAME}"/dotfiles/.* /home/"${NAME}"/.
rm -rf /home/"${NAME}"/dotfiles
rm -rf /home/"${NAME}"/.git
log_ok "DONE"

log_info "Cloning dwm in .local/src"
sudo -u "${NAME}" git -C /home/"${NAME}"/.local/src/ clone "https://github.com/arghpy/dwm"
log_ok "DONE"

log_info "Cloning dwmblocks in .local/src"
sudo -u "${NAME}" git -C /home/"${NAME}"/.local/src/ clone "https://github.com/arghpy/dwmblocks"
log_ok "DONE"

log_info "Cloning nvim in .config"
sudo -u "${NAME}" git -C /home/"${NAME}"/.config/ clone "https://github.com/arghpy/nvim_config"
sudo -u "${NAME}" mv /home/"${NAME}"/.config/nvim_config/* /home/"${NAME}"/.config/
sudo -u "${NAME}" rm -rf /home/"${NAME}"/.config/nvim_config
log_ok "DONE"

log_info "Modifying config settings for the local user"
for i in $(grep -r "arghpy" /home/"${NAME}"/* 2>/dev/null | awk -F ':' '{print $1}'); do  sed -i "s|arghpy|${NAME}|g" $i; done
log_ok "DONE"

log_info "Compiling sources in .local/src/"
for i in $(ls -ld /home/"${NAME}"/.local/src/* | awk '{print $NF}' | grep -v "yay\|lf\|icons");do
    cd "${i}"
    make clean install
done
log_ok "DONE"

log_ok "DONE"
log_info "Exit the chroot now 'exit' and reboot"
log_warning "Don't forget to take out the installation media"

