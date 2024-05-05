#!/usr/bin/env bash

MODE="${1}"
DISK="${2}"

LOG_FUNC="https://raw.githubusercontent.com/arghpy/functions/main/log_functions.sh"
DEP_FILE="https://raw.githubusercontent.com/arghpy/gentoo_install/main/dependencies.txt"

# Sourcing log functions
wget "${LOG_FUNC}"
# shellcheck disable=SC1091
if source log_functions.sh; then
    log_info "sourced log_functions.sh"
else
    echo "Error! Could not source log_functions.sh"
    exit 1
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

    PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')
    BOOT_P=$(echo "$PARTITIONS" | sed -n '1p')

    [[ "${MODE}" == "UEFI" ]] && mount /dev/"${BOOT_P}" /boot

    log_ok "DONE"
}

# Configure portage
configure_portage() {
    log_info "Configure portage"

    log_info "Installing a Gentoo ebuild repository snapshot from the web"
    emerge-webrsync
    log_ok "DONE"

    log_info "Updating the @world set"
    emerge --quiet --update --deep --newuse @world
    log_ok "DONE"

    log_info "Configuring CPU_FLAGS"
    emerge --quiet app-portage/cpuid2cpuflags
    echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
    log_ok "DONE"

    log_info "Configuring VIDEO_CARDS"

    GPU="$(lspci | grep VGA)"

    if [[ $(echo "${GPU}" | grep -q -i intel; echo $?) == 0 ]]; then
        echo 'VIDEO_CARDS="intel"' >> /etc/portage/make.conf
    elif [[ "$(echo "${GPU}" | grep -q -i nvidia; echo $?)" == 0 ]]; then 
        echo 'VIDEO_CARDS="nouveau"' >> /etc/portage/make.conf
        emerge --quiet x11-drivers/nvidia-drivers
    elif [[ "$(echo "${GPU}" | grep -q -i amd; echo $?)" == 0 ]]; then 
        echo 'VIDEO_CARDS="radeon"' >> /etc/portage/make.conf
    fi


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
    echo 'LANG="en_US.UTF-8"' > /etc/env.d/02locale
    
    # append to file
    echo 'LC_COLLATE="en_US.UTF-8"' > /etc/env.d/02locale

    env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

    log_ok "DONE"
}

# Configure and install kernel
configure_and_install_kernel() {
    log_info "Configure and install kernel"
    # create file
    echo "# Accepting the license for linux-firmware" > /etc/portage/package.license

    # append to file
    # shellcheck disable=SC2129
    echo "sys-kernel/linux-firmware linux-fw-redistributable" >> /etc/portage/package.license
    echo "" >> /etc/portage/package.license
    echo "# Accepting any license that permits redistribution" >> /etc/portage/package.license
    echo "sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE" >> /etc/portage/package.license


    log_info "Installing linux-firmware"
    emerge --quiet sys-kernel/linux-firmware
    if [[ $(lscpu | grep "^Model name" | grep -q -i intel; echo $?) == 0 ]]; then
        emerge --quiet sys-firmware/intel-microcode
        emerge --quiet x11-drivers/xf86-video-intel
    fi
    log_ok "DONE"

    log_info "Installing the kernel"
    emerge --quiet sys-kernel/installkernel-gentoo
    emerge --quiet sys-kernel/gentoo-kernel
    log_ok "DONE"

    log_info "Cleaning up"
    emerge --depclean
    log_ok "DONE"

    log_ok "DONE"
}

# Generating the fstab
generate_fstab() {
    log_info "Generating the fstab"
    emerge --quiet sys-fs/genfstab
    genfstab -U / >> /etc/fstab
    log_ok "DONE"
}

# Generate hostname
generate_hostname() {
    log_info "Generate hostname"
    echo "gentoo" > /etc/hostname
    log_ok "DONE"
}

# Enable networking
enable_network() {
    log_info "Enable networking"
    emerge --quiet net-misc/networkmanager
    for x in /etc/runlevels/default/net.* ; do
      rc-update del "$(basename "$x")" default
      rc-service --ifstarted "$(basename "$x")" stop
    done
    rc-update del dhcpcd default
    rc-service NetworkManager start
    rc-update add NetworkManager default
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
    emerge --quiet app-admin/sysklogd
    rc-update add sysklogd default
    log_ok "DONE"

    log_info "Cron daemon"
    emerge --quiet sys-process/cronie
    rc-update add cronie default
    log_ok "DONE"

    log_info "File indexing"
    emerge --quiet sys-apps/mlocate
    log_ok "DONE"

    log_info "enabling sshd"
    rc-update add sshd default
    log_ok "DONE"

    log_info "bash completion"
    emerge --quiet app-shells/bash-completion
    log_ok "DONE"

    log_info "Time Synchronization"
    emerge --quiet net-misc/chrony
    rc-update add chronyd default
    log_ok "DONE"

    log_info "udev scheduler"
    emerge --quiet sys-block/io-scheduler-udev-rules
    log_ok "DONE"

    log_info "Wireless tools"
    emerge --quiet net-wireless/iw net-wireless/wpa_supplicant
    log_ok "DONE"
    log_ok "DONE"
}

# Install packages
install_packages() {
    log_info "Install packages"
    log_info "Installing rust-bin"
    emerge --quiet rust-bin
    log_ok "DONE"
    wget "${DEP_FILE}"
    DEPLIST="$(grep -v "#" dependencies.txt | paste -sd" ")"
    # shellcheck disable=SC2086
    emerge --autounmask-continue --quiet ${DEPLIST}
    log_ok "DONE"
}

# Install pamixer
install_pamixer() {
    log_info "Installing pamixer"
    git clone https://github.com/cdemoulins/pamixer
    pushd pamixer || exit 1
    meson setup build
    meson compile -C build
    meson install -C build
    log_ok "DONE"
}

# Installing grub and creating configuration
grub_configuration() {
    log_info "Installing and configuring grub"
	if [[ "${MODE}" == "UEFI" ]]; then
        echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
        emerge --quiet sys-boot/grub
        grub-install --target=x86_64-efi --efi-directory=/boot
		grub-mkconfig -o /boot/grub/grub.cfg
	elif [[ "${MODE}" == "BIOS" ]]; then
        emerge --quiet sys-boot/grub
		grub-install /dev/"${DISK}"
		grub-mkconfig -o /boot/grub/grub.cfg
	else
		log_error "An error occured at grub step. Exiting..."
		exit 1
	fi
    log_ok "DONE"
}

# Set user and password
set_user() {

    log_info "Setting user account"

    NAME=""

    while [ -z "${NAME}" ]; do
        printf "Enter name for the local user: "
        read -r NAME
    done

    log_info "Adding user to users, audio, video and wheel group"
	useradd -m -G wheel,users,audio,video -s /bin/bash "${NAME}"

    log_info "Adding wheel to sudoers"
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

    log_info "Setting up user password"
    while ! passwd "${NAME}"; do
        sleep 1
    done

    log_ok "DONE"
}

# Move configuration files in user home
my_configuration() {
    log_info "Configuring the user's home directory"
    CONFIG_GIT="https://github.com/arghpy/dotfiles"
    # shellcheck disable=SC2115
    rm -rf /home/"${NAME}"/* 
    rm -rf /home/"${NAME}"/.* 
    git -C /home/"${NAME}"/ clone "${CONFIG_GIT}"
    mv /home/"${NAME}"/dotfiles/* /home/"${NAME}"/.
    mv /home/"${NAME}"/dotfiles/.* /home/"${NAME}"/.
    rm -rf /home/"${NAME}"/dotfiles
    rm -rf /home/"${NAME}"/.git
    log_ok "DONE"
}

# Copy custom dwm suite and neovim config
my_custom_progs() {
    mkdir --parents /home/"${NAME}"/.local/src/
    mkdir --parents /home/"${NAME}"/.config
    log_info "Cloning dwm in .local/src"
    git -C /home/"${NAME}"/.local/src/ clone "https://github.com/arghpy/dwm"
    rm -rf /home/"${NAME}"/.local/src/dwm/.git
    log_ok "DONE"

    log_info "Cloning dwmblocks in .local/src"
    git -C /home/"${NAME}"/.local/src/ clone "https://github.com/arghpy/dwmblocks"
    rm -rf /home/"${NAME}"/.local/src/dwmblocks/.git
    log_ok "DONE"

    log_info "Cloning st in .local/src"
    git -C /home/"${NAME}"/.local/src/ clone "https://github.com/arghpy/st"
    rm -rf /home/"${NAME}"/.local/src/st/.git
    log_ok "DONE"

    log_info "Cloning nvim in .config"
    git -C /home/"${NAME}"/.config/ clone "https://github.com/arghpy/nvim_config"
    mv /home/"${NAME}"/.config/nvim_config/* /home/"${NAME}"/.config/
    rm -rf /home/"${NAME}"/.config/nvim_config
    rm -rf /home/"${NAME}"/.config/.git
    log_ok "DONE"

    log_info "Modifying config settings for the local user"
    # shellcheck disbale=SC2013
    for i in $(grep -rl "arghpy" /home/"${NAME}"/.* /home/"${NAME}"/* 2>/dev/null); do
        sed -i "s|arghpy|${NAME}|g" "${i}"
    done
    log_ok "DONE"

    log_info "Compiling sources in .local/src/"
    # shellcheck disbale=SC2045
    for i in $(ls -d /home/"${NAME}"/.local/src/*);do
        pushd "${i}" || exit 1
        make clean install
        popd || exit 1
    done

    chown -R  "${NAME}":wheel /home/"${NAME}"/* /home/"${NAME}"/.*

    rc-update add elogind boot
    usermod -s /bin/zsh -aG plugdev "${NAME}"
    CORES="$(nproc)"
    NEW_CORES="$((CORES / 2))"
    sed -E -i "s|MAKEOPTS=.*|MAKEOPTS=\"-j${NEW_CORES}\"|g" /etc/portage/make.conf
    log_ok "DONE"
}

set_fonts() {
    log_info "Setting JetBrains Mono Nerd Font"
    pushd /usr/share/fonts || exit 1
    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip
    unzip JetBrainsMono.zip
    rm JetBrainsMono.zip
    popd || exit 1
    log_ok "DONE"
}

# Clean up
clean_up() {
    log_info "Clean up"
    rm -rf /dependencies.txt /log_functions.sh /pamixer
    log_ok "DONE"
}

# Main function to run all program
main() {
    prep_env
    mount_boot
    change_root_password
    set_user
    configure_portage
    setting_timezone
    configure_locales
    configure_and_install_kernel
    generate_fstab
    generate_hostname
    enable_network
    install_tools
    install_packages
    install_pamixer
    grub_configuration
    my_configuration
    my_custom_progs
    set_fonts
    clean_up

    log_ok "DONE"
    log_info "Exit the chroot now 'exit' and reboot"
    log_warning "Don't forget to take out the installation media"
}

main
