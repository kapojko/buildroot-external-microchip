# buildroot-external-microchip MediCam branch

This repository is forked official Microchip repository with Linux buildroot configuration for MediCam 1.0 board (SAM9X60D1G SIP), based on EV40E67A SAM9X60 Curiosity board.

## Key paths

- current repository is forked from https://github.com/linux4microchip/buildroot-external-microchip , master branch on fork date
- board\jk\sam9x60_medicam  Board directory
- board\jk\sam9x60_medicam\README.md  Board Readme
- configs\sam9x60_medicam_defconfig, configs\sam9x60_medicam_nand_defconfig  Board defconfigs (each is built in own build directory, `make` and `make O=output-nand`, respectively)
- ..\buildroot-mchp  Main buildroot (https://github.com/linux4microchip/buildroot-mchp, on frozen tag linux4microchip-2025.04) 

## Main workflow

Main workflow depends on current machine:

- Windows host: build in WSL, move changes to WSL through commit-push-pull
- WSL or Linux: direct operation

## Agent rules

- Full rebuilds are run by the user, not by the agent. Agent is allowed to do only short rebuilds (less than 5 minutes).
- DON'T make changes unapproved by user. Examples:
    - If user asked for analysys of the defect, give analysys and possible solutions, don't implement it without confirmation from user.
    - If user asked for defect fix, don't implement workaround fix (like, separate watchdog) if direct fix is unclear, without confirmation from user.
- DON'T commit without explicit request from user.
