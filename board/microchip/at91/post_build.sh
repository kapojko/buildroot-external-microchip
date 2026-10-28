#!/bin/bash
# SPDX-License-Identifier: GPL-2.0

if grep -Eq "^BR2_PACKAGE_SYSTEMD=y$" ${BR2_CONFIG}; then
       # The board can be configured without the dhcp-server / wpa_supplicant
       # packages (trimmed images); never assume the units exist, an
       # unconditional "mv" used to fail the whole build in that case.
       if [ -f ${TARGET_DIR}/usr/lib/systemd/system/dhcpd.service ]; then
               mv ${TARGET_DIR}/usr/lib/systemd/system/dhcpd.service                        ${TARGET_DIR}/usr/lib/systemd/system/dhcpd.service.example
       fi
       rm -f ${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/dhcpd.service
       rm -f ${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service
       rm -f ${TARGET_DIR}/usr/lib/systemd/system/wpa_supplicant.service

       if grep -Eq "^BR2_TARGET_OPTEE_OS=y$" ${BR2_CONFIG}; then
               cp ${BR2_EXTERNAL}/package/optee-client/tee-supplicant.service \
               ${TARGET_DIR}/usr/lib/systemd/system/tee-supplicant.service
               mkdir -p ${TARGET_DIR}/etc/systemd/system/basic.target.wants
               ln -sf /usr/lib/systemd/system/tee-supplicant.service \
               ${TARGET_DIR}/etc/systemd/system/basic.target.wants/tee-supplicant.service
       fi
fi
