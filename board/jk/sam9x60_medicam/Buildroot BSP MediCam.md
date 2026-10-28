Install *debian-12.11.0-amd64-DVD-1.iso* to VirtualBox (automatic install, user *yury*, password *1*).

*Configure sudo: *su (password: 1) ; /sbin/usermod -aG sudo yury *; relogin (reboot)

*Configure apt: comment out cdrom and add to *source.list*:


*deb https://deb.debian.org/debian bookworm main non-free-firmware*

*deb-src https://deb.debian.org/debian bookworm main non-free-firmware*


*deb https://security.debian.org/debian-security bookworm-security main non-free-firmware*

*deb-src https://security.debian.org/debian-security bookworm-security main non-free-firmware*


*deb https://deb.debian.org/debian bookworm-updates main non-free-firmware*

*deb-src https://deb.debian.org/debian bookworm-updates main non-free-firmware*


*Install pre packages: *sudo apt install geany git gitk meld*

*Install gh: [https://github.com/cli/cli/blob/trunk/docs/install\_linux.md](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) 

Auth: ***gh auth login** (using Web Browser)

Config username and email

git config --global user.name "Yuriy Kapoyko"

git config --global user.email "yury.kapoyko@gmail.com"


Install buildroot prerequisites software

*sudo apt install which sed make binutils build-essential diffutils gcc g++ bash patch gzip bzip2 perl tar cpio unzip rsync file bc findutils*


*Install microchip buildroot prerequisites *software

***sudo apt-get install libssl-dev**


***Install packages for menuconfig: **libncurses-dev 


*Fork **[linux4microchip/buildroot-external-microchip](https://github.com/linux4microchip/buildroot-external-microchip) **repository (*master* branch only)


***CLone *buildroot-mchp* repo**

***git clone [https://github.com/linux4microchip/buildroot-mchp.git***](https://github.com/linux4microchip/buildroot-mchp.git)

***cd  **buildroot-mchp*

***git checkout linux4microchip-2025.04***


***Fork **buildroot-external-microchip repo and make branch

*gh repo clone buildroot-external-microchip*

***cd ***buildroot-external-microchip*

***git checkout linux4microchip-2025.04 -b medicam**


# **Custom config**


***Board directory: *** board/jk/sam9x60\_medicam*

Defconfig* configs/sam9x60\_medicam\_defconfig – based from configs/sam9x60\_curiosity\_headless\_defconfig*

*Patch *patches/linux/0001-add-at91-sam9x60-medicam-dtb.patch – adds *../at91-sam9x60\_medicam.dtb to microchip dts Makefile


# **Custom DTS approach**

***DTS is given in config**

BR2\_LINUX\_KERNEL\_CUSTOM\_DTS\_PATH="$(BR2\_EXTERNAL\_MCHP\_PATH)/board/jk/sam9x60\_medicam/at91-sam9x60\_medicam.dts"


***NOTE: the DTS is being copied by buildroot to *arch/arm/boot/dts *directory (not *...dts/microchip*), that's why "../" and "microchip/" are added to the Makefile and .dts**


*Linux patch is applied to add dts to build rules.


# Kernel approach – don't use


Fork git repo [https://github.com/linux4microchip/linux](https://github.com/linux4microchip/linux) as ***[linux-microchip**](https://github.com/kapojko/linux-microchip)

 (all branches)


***Replace tarball with git repo, changed strings:**

BR2\_LINUX\_KERNEL\_CUSTOM\_TARBALL=y

BR2\_LINUX\_KERNEL\_CUSTOM\_TARBALL\_LOCATION="$(call github,linux4microchip,linux,linux4microchip-2025.04)/linux,linux4microchip-2025.04.tar.gz"


Clone git repo

gh repo clone kapojko/linux-mchp


Create branch for tag 

git checkout linux4microchip-2025.04 -b medicam


Copy dts (and modify)

cp arch/arm/boot/dts/microchip/at91-sam9x60\_curiosity.dts arch/arm/boot/dts/microchip/at91-sam9x60\_medicam.dts


Modify Makefile in *arch/arm/boot/dts/microchip* dir:

dtb-$(CONFIG\_SOC\_SAM9X60) += \\

	at91-sam9x60\_curiosity.dtb \\

	at91-sam9x60\_medicam.dtb \\

	at91-sam9x60ek.dtb


# Patch approach – don't use


Download kernel archive

wget [https://github.com/linux4microchip/linux/archive/refs/tags/linux4microchip-2025.04.tar.gz](https://github.com/linux4microchip/linux/archive/refs/tags/linux4microchip-2025.04.tar.gz)

tar -zxf linux4microchip-2025.04.tar.gz


Make clean copy for patch generation

cp -r linux-linux4microchip-2025.04/ linux-linux4microchip-2025.04.orig


Copy dts (and modify)

cp arch/arm/boot/dts/microchip/at91-sam9x60\_curiosity.dts arch/arm/boot/dts/microchip/at91-sam9x60\_medicam.dts


Modify Makefile in *arch/arm/boot/dts/microchip* dir:

dtb-$(CONFIG\_SOC\_SAM9X60) += \\

	at91-sam9x60\_curiosity.dtb \\

	at91-sam9x60\_medicam.dtb \\

	at91-sam9x60ek.dtb


Generate a patch:

diff -Naur linux-linux4microchip-2025.04.orig linux-linux4microchip-2025.04 \> 0001-add-at91-sam9x60-medicam.dts.patch


Copy the patch to patches:

mkdir -p patches/linux

cp ~/tmp/0001-add-at91-sam9x60-medicam.dts.patch patches/linux/



**Linux config**





**Custom drivers**


**Check I2C:**


**make linux-menuconfig**


**device drivers -\> I2C Support -\> I2C Hardware Bus Support -\> *Microchip's Flexcom TWI (I2C)**

***\<\*\> Misc devices  ---\>**  
***        \<\*\> EEPROM support  ---\>**  
***            \<\*\> I2C EEPROMs from most vendors (AT24, ...)**

**Check SPI:**

***Device Drivers  ---\>**  
***    \[\*\] SPI support  ---\>**  
***        \<\*\>   Microchip Flexcom SPI controller  \# Hardware driver for SAM9X60**  
***        \[\*\]   Userspace SPI device driver support  \# Required for spidev**


**Check ISI:**

Device Drivers  ---\>

  \[\*\] Multimedia support  ---\>

    \[\*\] Media platform devices  ---\>

        \[\*\] Atmel Image Sensor Interface (ISI) support


Check OV2640

Device Drivers  ---\>

Multimedia support \> Media ancillary drivers \> Camera sensor devices OmniVision OV2640 sensor support


**Loader**


**Curiosity template was configured with *bootm* and *itb* image (uboot + dev tree). But uboot deftree include (dtsi) was not full.**


***That's why build configuration is tuned *genimage.cfg* and *uboot-env.txt* to boot with kernel *dtb* and *zImage* with *bootz***


*image boot.vfat \{*

*	vfat \{*

*		files = \{*

*			"zImage",*

*			"at91-sam9x60\_medicam.dtb",*

*			"boot.bin",*

*			"u-boot.bin"*

*		\}*


*		file uboot.env \{*

*			image = "uboot-env.bin"*

*		\}*

*	\}*

*	size = 16M*

*\}*


*bootcmd\_boot=fatload mmc 0:1 $\{kernel\_addr\_r\} zImage; fatload mmc 0:1 $\{fdt\_addr\_r\} at91-sam9x60\_medicam.dtb; bootz $\{kernel\_addr\_r\} - $\{fdt\_addr\_r\};*

*kernel\_addr\_r=0x22000000*

*fdt\_addr\_r=0x21000000*


# Build


In buildroot-mchp directory:

BR2\_EXTERNAL=../buildroot-external-microchip/ make sam9x60\_medicam\_defconfig


***BR2\_EXTERNAL=../buildroot-external-microchip/ make -j 2**


***Clean**


***Full clean**

***BR2\_EXTERNAL=../buildroot-external-microchip/ make clean**


Super full clean

***BR2\_EXTERNAL=../buildroot-external-microchip/ make defclean**


***Clean linux (or other components)**

***BR2\_EXTERNAL=../buildroot-external-microchip/ make linux-dirclean**


***Rebuild linux (or other components)**

***BR2\_EXTERNAL=../buildroot-external-microchip/ make linux-rebuild**


**Output**


***Output is given in *output* directory:**

build – build files

host – cross-compiler

images – sdcard image

staging

target


***Flash**


***Windows – *balenaEtcher***

***Linux – *dd***


***SSH access**


***Linux solution***


***set passwd**

***Enable root ssh:**


***nano /etc/ssh/sshd\_config**


***- \#PermitRootLogin prohibit-password**  
***+ PermitRootLogin yes**  
  
***- \#PasswordAuthentication yes**  
***+ PasswordAuthentication yes**


***2. Restart SSH Service**

killall -HUP sshd



***Check**


***Test led:**


*cd /sys/class/leds/INFO*

*\# Turn it on*

*echo none \> trigger*

*echo 1 \> brightness*

*\# Turn it off*

*echo 0 \> brightness*

*\# Blink (software)*

*echo timer \> trigger*

*echo 500 \> delay\_on*

*echo 500 \> delay\_off*


Test button:


*evtest *(select group and press button)


***I2C test:**


*i2cdetect -l* (list buses)

*i2cdetect -y 0 *(scan devices)

*i2cdump -y 0 0x50* (read EEPROM first 16 bytes)


SPI test (with *spidev* enabled):


*echo -n -e '\\x9F' | spidev\_test -D /dev/spidev1.0 -v*


*USART test:


*dmesg | grep tty *(/dev/ttyS2 and /dev/ttyS5)

*stty -F /dev/ttyS2 115200*

*echo "Hello" \> /dev/ttyS2*

*cat /dev/ttyS2*


Or use minicom or screen.

screen /dev/ttyS2 115200


RS485 test

*stty -F /dev/ttyS5 115200*

gpioset gpiochip0 29=1 23=0    \# Enable transmit

echo "Hello RS485" \> /dev/ttyS5

sleep 0.1                      \# Wait for data to flush

gpioset gpiochip0 29=0 23=1    \# Enable receive


GPIO testing (raw gpiod):


List available GPIO lines:

gpiodetect gpioinfo

Test toggle GPIO:

\# Export PA30 (button) and PA31 (LED) for manual control

gpioset gpiochip0 31=1 \# turn LED on

gpioget gpiochip0 30 \# read button


I2C EEPROM:

***dmesg | grep at24**

***ls /sys/bus/i2c/devices/0-0050/eeprom**

***dd if=/sys/bus/i2c/devices/0-0050/eeprom bs=1 count=32768 | hexdump -C**

***echo -n -e '\\xAA' | dd of=/sys/bus/i2c/devices/0-0050/eeprom bs=1 count=1 seek=0**


SPI WS2812

***\# Send 24 bits (1 LED, GRB format):***  
***spi\_xfer -v -s 3200000 -d "\\xFF\\x00\\x00" /dev/spidev1.0  *\# Green***  
***spi\_xfer -v -s 3200000 -d "\\x00\\xFF\\x00" /dev/spidev1.0  *\# Red***

OV2640

***\# Check if sensor is detected***  
***i2cdetect -y 0  *\# Should show 0x30***  
***\# Verify V4L2 device***  
***v4l2-ctl --list-devices  *\# Should show /dev/video0***  
***\# Capture test image (install fswebcam)***  
***fswebcam -d /dev/video0 test.jpg**


media-ctl -p          \# List media pipeline

v4l2-ctl --all        \# List device details

v4l2-ctl --list-devices

v4l2-ctl --list-formats

v4l2-ctl --stream-mmap --stream-count=10 --stream-to=frame.raw


***\# Basic capture (320x240, JPEG)***  
***v4l2grab -d /dev/video0 -o test.jpg -W 320 -H 240 -q 85**  
  
***\# Full resolution (1600x1200)***  
***v4l2grab -d /dev/video0 -o fullres.jpg -W 1600 -H 1200**



