**SAM9X60 Curiosity vs Medicam Pinout**


**NOTE: Power and Ground pins excluded**


|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
| - | - | - | - | :-: | - | :-: | - | - | - |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
|  R1 |  L2 |  VDDIOP0 |  GPIO |  PA0 |  I/O |  – |  – | A | FLEXCOM0\_IO0 | I/O |  PIO, I, PU, ST | **EEPROM\_TWD\_PA0, MBUS\_TWD\_PA0, RPI\_TWD\_PA0** | **TWI\_SDA\_PA0** |
|  |  |  |  |  |  |  |  | B | FLEXCOM5\_IO4 | O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM4\_IO4 | O |  |  |  |
|  M2 |  L3 |  VDDIOP0 |  GPIO |  PA1 |  I/O |  – |  – | A | FLEXCOM0\_IO1 | I/O |  PIO, I, PU, ST | **EEPROM\_TWCK\_PA1,** **MBUS\_TWCK\_PA1, RPI\_TWCK\_PA1** | **TWI\_SCL\_PA1** |
|  |  |  |  |  |  |  |  | B | FLEXCOM4\_IO5 | O |  |  |  |
|  N1 |  K2 |  VDDIOP0 |  GPIO |  PA2 |  I/O |  WKUP1 |  – | A | FLEXCOM0\_IO4 | O |  PIO, I, PU, ST | **SDMMC1\_DAT1\_PA2** |  |
|  |  |  |  |  |  |  |  | B | SDMMC1\_DAT1 | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | E0\_TX0 | O |  |  |  |
|  L2 |  K3 |  VDDIOP0 |  GPIO |  PA3 |  I/O |  – |  – | A | FLEXCOM0\_IO3 | I/O |  PIO, I, PU, ST | **SDMMC1\_DAT2\_PA3** |  |
|  |  |  |  |  |  |  |  | B | SDMMC1\_DAT2 | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | E0\_TX1 | O |  |  |  |
|  M1 |  L1 |  VDDIOP0 |  GPIO |  PA4 |  I/O |  – |  – | A | FLEXCOM0\_IO2 | I/O |  PIO, I, PU, ST | **SDMMC1\_DAT3\_PA4** |  |
|  |  |  |  |  |  |  |  | B | SDMMC1\_DAT3 | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | E0\_TXER | O |  |  |  |
|  P2 |  N3 |  VDDIOP0 |  GPIO |  PA5 |  I/O |  – |  – | A | FLEXCOM1\_IO0 | I/O |  PIO, I, PU, ST | **CAN1\_TX\_PA5** | **RGB\_MOSI\_PA5** |
|  |  |  |  |  |  |  |  | B | CANTX1 | O |  |  |  |
|  J2 |  N1 |  VDDIOP0 |  GPIO |  PA6 |  I/O |  – |  – | A | FLEXCOM1\_IO1 | I/O |  PIO, I, PU, ST | **CAN1\_RX\_PA6** |  |
|  |  |  |  |  |  |  |  | B | CANRX1 | I |  |  |  |
|  L3 |  P2 |  VDDIOP0 |  GPIO |  PA7 |  I/O |  – |  – | A | FLEXCOM2\_IO0 | I/O |  PIO, I, PU, ST | **RPI\_NPCS0\_PA7** | **UART\_TX\_PA7** |
|  |  |  |  |  |  |  |  | B | FLEXCOM4\_IO4 | O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM5\_IO4 | O |  |  |  |
|  K1 |  P3 |  VDDIOP0 |  GPIO |  PA8 |  I/O |  – |  – | A | FLEXCOM2\_IO1 | I/O |  PIO, I, PU, ST | **MBUS\_NPCS\_PA8, RPI\_NPCS1\_PA8** | **UART\_RX\_PA8** |
|  |  |  |  |  |  |  |  | B | FLEXCOM5\_IO3 | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM4\_IO5 | O |  |  |  |
|  F5 |  N2 |  VDDIOP0 |  GPIO |  PA9 |  I/O |  WKUP2 |  – | A | DRXD | I |  PIO, I, PU, ST | **DBGU\_RX\_PA9, CAN0\_RX\_PA9** | **DBGU\_RX\_PA9** |
|  |  |  |  |  |  |  |  | B | CANRX0 | I |  |  |  |
|  H2 |  M4 |  VDDIOP0 |  GPIO |  PA10 |  I/O |  WKUP3 |  – | A | DTXD | O |  PIO, I, PU, ST | **DBGU\_TX\_PA10, CAN0\_TX\_PA10** | **DBGU\_TX\_PA10** |
|  |  |  |  |  |  |  |  | B | CANTX0 | O |  |  |  |
|  L1 |  G3 |  VDDIOP0 |  GPIO |  PA11 |  I/O |  – |  – | A | FLEXCOM4\_IO1 | I/O |  PIO, I, PU, ST | **SDMMC1\_DAT0\_PA11** |  |
|  |  |  |  |  |  |  |  | B | SDMMC1\_DAT0 | I/O |  |  |  |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
|  J1 |  G4 |  VDDIOP0 |  GPIO |  PA12 |  I/O |  – |  – | A | FLEXCOM4\_IO0 | I/O |  PIO, I, PU, ST | **SDMMC1\_CMD\_PA12** |  |
|  |  |  |  |  |  |  |  | B | SDMMC1\_CMD | I/O |  |  |  |
|  H4 |  G1 |  VDDIOP0 |  GPIO |  PA13 |  I/O |  – |  – | A | FLEXCOM4\_IO2 | I/O |  PIO, I, PU, ST | **SDMMC1\_CK\_PA13** |  |
|  |  |  |  |  |  |  |  | B | SDMMC1\_CK | I/O |  |  |  |
| H1 | G2 | VDDIOP0 | GPIO | PA14 | I/O | – | – | A | FLEXCOM4\_IO3 | I/O | PIO, I, PU, ST | **SDMMC1\_WP\_PA14** |  |
| K2 | K1 | VDDIOP0 | GPIO | PA15 | I/O | – | – | A | SDMMC0\_DAT0 | I/O | PIO, I, PU, ST | **SDMMC0\_DAT0\_PA15** | **SDMMC0\_DAT0\_PA15** |
| G2 | J2 | VDDIOP0 | GPIO | PA16 | I/O | – | – | A | SDMMC0\_CMD | I/O | PIO, I, PU, ST | **SDMMC0\_CMD\_PA16** | **SDMMC0\_CMD\_PA16** |
| K3 | H4 | VDDIOP0 | GPIO | PA17 | I/O | – | – | A | SDMMC0\_CK | I/O | PIO, I, PU, ST | **SDMMC0\_CK\_PA17** | **SDMMC0\_CK\_PA17** |
| G1 | H3 | VDDIOP0 | GPIO | PA18 | I/O | – | – | A | SDMMC0\_DAT1 | I/O | PIO, I, PU, ST | **SDMMC0\_DAT1\_PA18** | **SDMMC0\_DAT1\_PA18** |
| M3 | J1 | VDDIOP0 | GPIO | PA19 | I/O | – | – | A | SDMMC0\_DAT2 | I/O | PIO, I, PU, ST | **SDMMC0\_DAT2\_PA19** | **SDMMC0\_DAT2\_PA19** |
| F2 | J4 | VDDIOP0 | GPIO | PA20 | I/O | – | – | A | SDMMC0\_DAT3 | I/O | PIO, I, PU, ST | **SDMMC0\_DAT3\_PA20** | **SDMMC0\_DAT3\_PA20** |
|  C1 |  B11 |  VDDIOP0 |  GPIO |  PA21 |  I/O |  – |  – | A | TIOA0 | I/O |  PIO, I, PU, ST | **MBUS\_MISO\_PA21, RPI\_MISO\_PA21** | **RUART\_RX\_PA21** |
|  |  |  |  |  |  |  |  | B | FLEXCOM5\_IO1 | I/O |  |  |  |
|  E1 |  A10 |  VDDIOP0 |  GPIO |  PA22 |  I/O |  – |  – | A | TIOA1 | I/O |  PIO, I, PU, ST | **MBUS\_MOSI\_PA22, RPI\_MOSI\_PA22** | **RUART\_TX\_PA22** |
|  |  |  |  |  |  |  |  | B | FLEXCOM5\_IO0 | I/O |  |  |  |
|  H3 |  C11 |  VDDIOP0 |  GPIO |  PA23 |  I/O |  – |  – | A | TIOA2 | I/O |  PIO, I, PU, ST | **MBUS\_SCLK\_PA23, RPI\_SCLK\_PA23** | **RS485\_NRE\_PA23** |
|  |  |  |  |  |  |  |  | B | FLEXCOM5\_IO2 | I/O |  |  |  |
|  D3 |  B10 |  VDDIOP0 |  GPIO |  PA24 |  I/O |  – |  – | A | TCLK0 | I |  PIO, I, PU, ST | **RPI\_GPIO1\_PA24** |  |
|  |  |  |  |  |  |  |  | B | TK | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | CLASSD\_L0 | O |  |  |  |
|  F1 |  A9 |  VDDIOP0 |  GPIO |  PA25 |  I/O |  – |  – | A | TCLK1 | I |  PIO, I, PU, ST | **SDMMC0\_CD\_PA25** | **SDMMC0\_CD\_PA25** |
|  |  |  |  |  |  |  |  | B | TF | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | CLASSD\_L1 | O |  |  |  |
|  H5 |  D10 |  VDDIOP0 |  GPIO |  PA26 |  I/O |  – |  – | A | TCLK2 | I |  PIO, I, PU, ST | **USBB\_OVCUR\_PA26, RPI\_GPIO17\_PA26** | **USBB\_OVCUR\_PA26** |
|  |  |  |  |  |  |  |  | B | TD | O |  |  |  |
|  |  |  |  |  |  |  |  | C | CLASSD\_L2 | O |  |  |  |
|  E2 |  D12 |  VDDIOP0 |  GPIO |  PA27 |  I/O |  – |  – | A | TIOB0 | I/O |  PIO, I, PU, ST | **USBA\_VBUS\_DETECT\_PA27, RPI\_GPIO27\_PA27** | **USBA\_VBUS\_DETECT\_PA27** |
|  |  |  |  |  |  |  |  | B | RD | I |  |  |  |
|  |  |  |  |  |  |  |  | C | CLASSD\_L3 | O |  |  |  |
|  D1 |  A11 |  VDDIOP0 |  GPIO |  PA28 |  I/O |  WKUP4 |  – | A | TIOB1 | I/O |  PIO, I, PU, ST | **USBC\_OVCUR\_PA28, RPI\_GPIO22\_PA28** | **USBC\_OVCUR\_PA28** |
|  |  |  |  |  |  |  |  | B | RK | I/O |  |  |  |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
|  J3 |  C10 |  VDDIOP0 |  GPIO |  PA29 |  I/O |  – |  – | A | TIOB2 | I/O |  PIO, I, PU, ST | **USER\_BUTTON\_PA29, RPI\_GPIO29\_PA29** | **RS485\_DE\_PA29** |
|  |  |  |  |  |  |  |  | B | RF | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM2\_IO7 | I |  |  |  |
|  D2 |  H1 |  VDDIOP0 |  GPIO |  PA30 |  I/O |  – |  – | A | FLEXCOM6\_IO0 | I/O |  PIO, I, PU, ST |  | **MODE\_BTN\_PA30** |
|  |  |  |  |  |  |  |  | B | FLEXCOM5\_IO6 | O |  |  |  |
|  |  |  |  |  |  |  |  | C | E0\_MDC | O |  |  |  |
|  G3 |  H2 |  VDDIOP0 |  GPIO |  PA31 |  I/O |  – |  – | A | FLEXCOM6\_IO1 | I/O |  PIO, I, PU, ST |  | **INFO\_LED\_PA31** |
|  |  |  |  |  |  |  |  | B | FLEXCOM5\_IO5 | O |  |  |  |
|  |  |  |  |  |  |  |  | C | E0\_TXEN | O |  |  |  |
|  A3 |  B3 |  VDDANA |  GPIO |  PB0 |  I/O |  WKUP5 |  – | A | E0\_RX0 | I |  PIO, I, PU, ST | **ETH0\_RX0\_PB0** | **ETH0\_RX0\_PB0** |
|  |  |  |  |  |  |  |  | B | FLEXCOM2\_IO4 | O |  |  |  |
|  B6 |  D1 |  VDDANA |  GPIO |  PB1 |  I/O |  – |  – | A | E0\_RX1 | I |  PIO, I, PU, ST | **ETH0\_RX1\_PB1** | **ETH0\_RX1\_PB1** |
|  |  |  |  |  |  |  |  | B | FLEXCOM2\_IO3 | I/O |  |  |  |
|  A6 |  A3 |  VDDANA |  GPIO |  PB2 |  I/O |  – |  – | A | E0\_RXER | I |  PIO, I, PU, ST | **ETH0\_RXER\_PB2** | **ETH0\_RXER\_PB2** |
|  |  |  |  |  |  |  |  | B | FLEXCOM2\_IO2 | I/O |  |  |  |
|  A5 |  D2 |  VDDANA |  GPIO |  PB3 |  I/O |  WKUP6 |  – | A | E0\_RXDV | I |  PIO, I, PU, ST | **ETH0\_RXDV\_PB3** | **ETH0\_RXDV\_PB3** |
|  |  |  |  |  |  |  |  | B | FLEXCOM4\_IO6 | O |  |  |  |
|  B3 |  E3 |  VDDANA |  GPIO |  PB4 |  I/O |  – |  – | A | E0\_TXCK | I/O |  PIO, I, PU, ST | **ETH0\_TXCK\_PB4** | **ETH0\_TXCK\_PB4** |
|  |  |  |  |  |  |  |  | B | FLEXCOM8\_IO0 | I/O |  |  |  |
|  B1 |  E1 |  VDDANA |  GPIO |  PB5 |  I/O |  – |  – | A | E0\_MDIO | I/O |  PIO, I, PU, ST | **ETH0\_MDIO\_PB5** | **ETH0\_MDIO\_PB5** |
|  |  |  |  |  |  |  |  | B | FLEXCOM8\_IO1 | I/O |  |  |  |
|  B5 |  D3 |  VDDANA |  GPIO |  PB6 |  I/O |  AD7 |  – | A | E0\_MDC |  O |  PIO, I, PU, ST | **ETH0\_MDC\_PB6** | **ETH0\_MDC\_PB6** |
|  |  |  |  |  |  |  |  | B | FLEXCOM0\_IO7 |  |  |  |  |
| A11 | F4 | VDDANA | GPIO | PB7 | I/O | AD8 | – | A | E0\_TXEN | O | PIO, I, PU, ST | **ETH0\_TXEN\_PB7** | **ETH0\_TXEN\_PB7** |
| E6 | D5 | VDDANA | GPIO | PB8 | I/O | AD9 | – | A | E0\_TXER | O | PIO, I, PU, ST | **ETH0\_IRQ\_PB8** | **ETH0\_IRQ\_PB8** |
|  B9 |  B4 |  VDDANA |  GPIO |  PB9 |  I/O |  AD10 |  – | A | E0\_TX0 | O |  PIO, I, PU, ST | **ETH0\_TX0\_PB9** | **ETH0\_TX0\_PB9** |
|  |  |  |  |  |  |  |  | B | PCK1 | O |  |  |  |
|  C9 |  B5 |  VDDANA |  GPIO |  PB10 |  I/O |  AD11 |  – | A | E0\_TX1 | O |  PIO, I, PU, ST | **ETH0\_TX1\_PB10** | **ETH0\_TX1\_PB10** |
|  |  |  |  |  |  |  |  | B | PCK0 | O |  |  |  |
|  C10 |  C5 |  VDDANA |  GPIO |  PB11 |  I/O |  AD0 |  – | A | E0\_TX2 | O |  PIO, I, PU, ST | **RPI\_GPIO5/CLK1\_PB11** |  |
|  |  |  |  |  |  |  |  | B | PWM0 | O |  |  |  |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
|  C6 |  A2 |  VDDANA |  GPIO |  PB12 |  I/O |  AD1 |  – | A | E0\_TX3 | O |  PIO, I, PU, ST | **RPI\_PWM0\_PB12** |  |
|  |  |  |  |  |  |  |  | B | PWM1 | O |  |  |  |
|  E9 |  A5 |  VDDANA |  GPIO |  PB13 |  I/O |  AD2 |  – | A | E0\_RX2 | I |  PIO, I, PU, ST | **MBUS\_PWM\_PB13** |  |
|  |  |  |  |  |  |  |  | B | PWM2 | O |  |  |  |
|  C2 |  E4 |  VDDANA |  GPIO |  PB14 |  I/O |  AD3 |  – | A | E0\_RX3 | I |  PIO, I, PU, ST | **MBUS\_AN\_PB14, RPI\_GPIO13\_PB14** |  |
|  |  |  |  |  |  |  |  | B | PWM3 | O |  |  |  |
| B11 | C4 | VDDANA | GPIO | PB15 | I/O | AD4 | – | A | E0\_RXCK | I | PIO, I, PU, ST | **MCP16501\_LPM\_PB15 ** | **MCP16501\_LPM\_PB15** |
| D9 | E2 | VDDANA | GPIO | PB16 | I/O | AD5 | – | A | E0\_CRS | I | PIO, I, PU, ST | **ETH0\_NRST\_PB16 (0R DNP)** | **ETH0\_NRST\_PB16** |
| A9 | A4 | VDDANA | GPIO | PB17 | I/O | AD6 | – | A | E0\_COL | I | PIO, I, PU, ST | **CAN1\_STBY\_PB17** |  |
|  A4 |  D7 |  VDDANA |  GPIO |  PB18 |  I/O |  WKUP7 |  – | A | IRQ | I |  PIO, I, PU, ST | **MBUS\_INT\_PB18** |  |
|  |  |  |  |  |  |  |  | B | ADTRG | I |  |  |  |
|  B7 |  A7 |  VDDQSPI |  GPIO |  PB19 |  I/O |  – |  – | A | QSCK | O |  PIO, I, PU, ST | **RPI\_I2SCK\_PB19** |  |
|  |  |  |  |  |  |  |  | B | I2SMCC\_CK | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM11\_IO0 | I/O |  |  |  |
|  A8 |  D9 |  VDDQSPI |  GPIO |  PB20 |  I/O |  – |  – | A | QCS | O |  PIO, I, PU, ST | **RPI\_I2SWS\_PB20** |  |
|  |  |  |  |  |  |  |  | B | I2SMCC\_WS | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM11\_IO1 | I/O |  |  |  |
|  B8 |  A8 |  VDDQSPI |  GPIO |  PB21 |  I/O |  – |  – | A | QIO0 | I/O |  PIO, I, PU, ST | **RPI\_I2SDIN\_PB21** |  |
|  |  |  |  |  |  |  |  | B | I2SMCC\_DIN0 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM12\_IO0 | I/O |  |  |  |
|  C8 |  B8 |  VDDQSPI |  GPIO |  PB22 |  I/O |  – |  – | A | QIO1 | I/O |  PIO, I, PU, ST | **RPI\_I2SDOUT\_PB22** |  |
|  |  |  |  |  |  |  |  | B | I2SMCC\_DOUT0 | O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM12\_IO1 | I/O |  |  |  |
|  A7 |  C7 |  VDDQSPI |  GPIO |  PB23 |  I/O |  – |  – | A | QIO2 | I/O |  PIO, I, PU, ST | **RPI\_I2SMCK\_PB23** |  |
|  |  |  |  |  |  |  |  | B | I2SMCC\_MCK | O |  |  |  |
| D8 | B9 | VDDQSPI | GPIO | PB24 | I/O | – | – | A | QIO3 | I/O | PIO, I, PU, ST | **RPI\_GPIO26\_PB24** |  |
|  A2 |  B7 |  VDDIOP0 |  GPIO |  PB25 |  I/O |  WKUP8 |  – | A | NRST\_OUT | O |  NRST\_OUT, O, PD | **MPU\_NRSTOUT\_PB25** | **MPU\_NRSTOUT\_PB25** |
|  |  |  |  |  |  |  |  | B | NTRST | I |  |  |  |
|  M4 |  U8 |  VDDIOP1 |  GPIO |  PC0 |  I/O |  – |  – | A | LCDDAT0 | O |  PIO, I, PU, ST | **MBUS\_TX\_PC0** | **ISI\_D0\_PC0** |
|  |  |  |  |  |  |  |  | B | ISI\_D0 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM7\_IO0 | I/O |  |  |  |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
|  P4 |  U3 |  VDDIOP1 |  GPIO |  PC1 |  I/O |  – |  – | A | LCDDAT1 | O |  PIO, I, PU, ST | **MBUS\_RX\_PC1** | **ISI\_D1\_PC1** |
|  |  |  |  |  |  |  |  | B | ISI\_D1 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM7\_IO1 | I/O |  |  |  |
|  N3 |  T4 |  VDDIOP1 |  GPIO |  PC2 |  I/O |  – |  – | A | LCDDAT2 | O |  PIO, I, PU, ST |  | **ISI\_D2\_PC2** |
|  |  |  |  |  |  |  |  | B | ISI\_D2 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TIOA3 | I/O |  |  |  |
|  P5 |  T1 |  VDDIOP1 |  GPIO |  PC3 |  I/O |  – |  – | A | LCDDAT3 | O |  PIO, I, PU, ST |  | **ISI\_D3\_PC3** |
|  |  |  |  |  |  |  |  | B | ISI\_D3 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TIOB3 | I/O |  |  |  |
|  L5 |  R5 |  VDDIOP1 |  GPIO |  PC4 |  I/O |  – |  – | A | LCDDAT4 | O |  PIO, I, PU, ST |  | **ISI\_D4\_PC4** |
|  |  |  |  |  |  |  |  | B | ISI\_D4 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TCLK3 | I |  |  |  |
|  R4 |  U4 |  VDDIOP1 |  GPIO |  PC5 |  I/O |  – |  – | A | LCDDAT5 | O |  PIO, I, PU, ST |  | **ISI\_D5\_PC5** |
|  |  |  |  |  |  |  |  | B | ISI\_D5 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TIOA4 | I/O |  |  |  |
|  M6 |  T7 |  VDDIOP1 |  GPIO |  PC6 |  I/O |  – |  – | A | LCDDAT6 | O |  PIO, I, PU, ST |  | **IDI\_D6\_PC6** |
|  |  |  |  |  |  |  |  | B | ISI\_D6 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TIOB4 | I/O |  |  |  |
|  T3 |  R2 |  VDDIOP1 |  GPIO |  PC7 |  I/O |  – |  – | A | LCDDAT7 | O |  PIO, I, PU, ST |  | **ISI\_D7\_PC7** |
|  |  |  |  |  |  |  |  | B | ISI\_D7 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TCLK4 | I |  |  |  |
|  N8 |  U7 |  VDDIOP1 |  GPIO |  PC8 |  I/O |  – |  – | A | LCDDAT8 | O |  PIO, I, PU, ST | **SDMMC1\_CD\_PC8, RPI\_GPIO23\_PC8** |  |
|  |  |  |  |  |  |  |  | B | ISI\_D8 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM9\_IO0 | I/O |  |  |  |
|  T4 |  R1 |  VDDIOP1 |  GPIO |  PC9 |  I/O |  – |  – | A | LCDDAT9 | O |  PIO, I, PU, ST | **CAN0\_STBY\_PC9, RPI\_GPIO6\_PC9** |  |
|  |  |  |  |  |  |  |  | B | ISI\_D9 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM9\_IO1 | I/O |  |  |  |
|  P6 |  T8 |  VDDIOP1 |  GPIO |  PC10 |  I/O |  – |  – | A | LCDDAT10 | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | ISI\_D10 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | PWM0 | O |  |  |  |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
|  M11 |  T3 |  VDDIOP1 |  GPIO |  PC11 |  I/O |  – |  – | A | LCDDAT11 | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | ISI\_D11 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | PWM1 | O |  |  |  |
|  R5 |  T5 |  VDDIOP1 |  GPIO |  PC12 |  I/O |  – |  – | A | LCDDAT12 | O |  PIO, I, PU, ST |  | **ISI\_PCK\_PC12** |
|  |  |  |  |  |  |  |  | B | ISI\_PCK | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TIOA5 | I/O |  |  |  |
|  M13 |  R4 |  VDDIOP1 |  GPIO |  PC13 |  I/O |  – |  – | A | LCDDAT13 | O |  PIO, I, PU, ST |  | **ISI\_VSYNC\_PC13** |
|  |  |  |  |  |  |  |  | B | ISI\_VSYNC | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TIOB5 | I/O |  |  |  |
|  T5 |  U2 |  VDDIOP1 |  GPIO |  PC14 |  I/O |  – |  – | A | LCDDAT14 | O |  PIO, I, PU, ST |  | **ISI\_HSYNC\_PC14** |
|  |  |  |  |  |  |  |  | B | ISI\_HSYNC | I |  |  |  |
|  |  |  |  |  |  |  |  | C | TCLK5 | I |  |  |  |
|  L12 |  U5 |  VDDIOP1 |  GPIO |  PC15 |  I/O |  – |  – | A | LCDDAT15 | O |  PIO, I, PU, ST |  | **ISI\_MCK\_PC15** |
|  |  |  |  |  |  |  |  | B | ISI\_MCK | O |  |  |  |
|  |  |  |  |  |  |  |  | C | PCK0 | O |  |  |  |
|  R6 |  R10 |  VDDIOP1 |  GPIO |  PC16 |  I/O |  – |  – | A | LCDDAT16 | O |  PIO, I, PU, ST | **RPI\_TX\_PC16** | **ISI\_PWDN\_PC16** |
|  |  |  |  |  |  |  |  | B | E1\_RXER | I |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM10\_IO0 | I/O |  |  |  |
|  N14 |  R8 |  VDDIOP1 |  GPIO |  PC17 |  I/O |  – |  – | A | LCDDAT17 | O |  PIO, I, PU, ST | **RPI\_RX\_PC17** | **ISI\_RST\_PC17** |
|  |  |  |  |  |  |  |  | B | FLEXCOM1\_IO7 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM10\_IO1 | I/O |  |  |  |
|  T6 |  R7 |  VDDIOP1 |  GPIO |  PC18 |  I/O |  – |  – | A | LCDDAT18 | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_TX0 | O |  |  |  |
|  |  |  |  |  |  |  |  | C | PWM0 | O |  |  |  |
|  L14 |  P6 |  VDDIOP1 |  GPIO |  PC19 |  I/O |  – |  – | A | LCDDAT19 | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_TX1 | O |  |  |  |
|  |  |  |  |  |  |  |  | C | PWM1 | O |  |  |  |
|  P8 |  T14 |  VDDIOP1 |  GPIO |  PC20 |  I/O |  – |  – | A | LCDDAT20 | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_RX0 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | PWM2 | O |  |  |  |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
|  M8 |  P8 |  VDDIOP1 |  GPIO |  PC21 |  I/O |  – |  – | A | LCDDAT21 | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_RX1 | I |  |  |  |
|  |  |  |  |  |  |  |  | C | PWM3 | O |  |  |  |
|  R7 |  R14 |  VDDIOP1 |  GPIO |  PC22 |  I/O |  – |  – | A | LCDDAT22 | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | FLEXCOM3\_IO0 | I/O |  |  |  |
|  M14 |  T9 |  VDDIOP1 |  GPIO |  PC23 |  I/O |  – |  – | A | LCDDAT23 | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | FLEXCOM3\_IO1 | I/O |  |  |  |
|  R8 |  U14 |  VDDIOP1 |  GPIO |  PC24 |  I/O |  WKUP9 |  – | A | LCDDISP | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | FLEXCOM3\_IO4 | O |  |  |  |
|  M9 |  P5 |  VDDIOP1 |  GPIO |  PC25 |  I/O |  WKUP10 |  – | A | – | – |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | FLEXCOM3\_IO3 | I/O |  |  |  |
|  T8 |  R13 |  VDDIOP1 |  GPIO |  PC26 |  I/O |  – |  – | A | LCDPWM | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | FLEXCOM3\_IO2 | I/O |  |  |  |
|  N9 |  U9 |  VDDIOP1 |  GPIO |  PC27 |  I/O |  – |  – | A | LCDVSYNC | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_TXEN | O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM1\_IO4 | O |  |  |  |
|  P11 |  P13 |  VDDIOP1 |  GPIO |  PC28 |  I/O |  – |  – | A | LCDHSYNC | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_CRSDV | I |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM1\_IO3 | I/O |  |  |  |
|  N12 |  P9 |  VDDIOP1 |  GPIO |  PC29 |  I/O |  – |  – | A | LCDDEN | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_TXCK | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM1\_IO2 | I/O |  |  |  |
|  T7 |  T13 |  VDDIOP1 |  GPIO |  PC30 |  I/O |  – |  – | A | LCDPCK | O |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_MDC | O |  |  |  |
|  |  |  |  |  |  |  |  | C | FLEXCOM3\_IO7 | I |  |  |  |
|  P15 |  U13 |  VDDIOP1 |  GPIO |  PC31 |  I/O |  WKUP11 |  – | A | FIQ | I |  PIO, I, PU, ST |  |  |
|  |  |  |  |  |  |  |  | B | E1\_MDIO | I/O |  |  |  |
|  |  |  |  |  |  |  |  | C | PCK1 | O |  |  |  |
| P16 | L17 | VDDNF | GPIO | PD0 | I/O | – | – | A | NANDOE | O | PIO, I, PU, ST | NAND\_RE\_PD0 | NAND\_RE\_PD0 |
| R16 | H15 | VDDNF | GPIO | PD1 | I/O | – | – | A | NANDWE | O | PIO, I, PU, ST | NAND\_WE\_PD1 | NAND\_WE\_PD1 |
| N16 | K17 | VDDNF | GPIO | PD2 | I/O | – | – | A | A21/NANDALE | O | A21,O, PD, ST | NAND\_ALE\_PD2 | NAND\_ALE\_PD2 |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
| L15 | J16 | VDDNF | GPIO | PD3 | I/O | – | – | A | A22/NANDCLE | O | A22,O, PD | **NAND\_CLE\_PD3** | **NAND\_CLE\_PD3** |
| L16 | J17 | VDDNF | GPIO | PD4 | I/O | – | – | A | NCS3/NANDCS | O | PIO, I, PU, ST | **NAND\_NCS\_PD4 (W/ JUMPER)** | **NAND\_NCS\_PD4 (W/ JUMPER)** |
| M15 | K14 | VDDNF | GPIO | PD5 | I/O | – | – | A | NWAIT | I | PIO, I, PU, ST | **NAND\_RDY\_PD5** | **NAND\_RDY\_PD5** |
| G15 | C17 | VDDNF | GPIO | PD6 | I/O | – | – | A | D16 | I/O | PIO, I, PU, ST | **NAND\_D0\_PD6** | **NAND\_D0\_PD6** |
| H12 | K16 | VDDNF | GPIO | PD7 | I/O | – | – | A | D17 | I/O | PIO, I, PU, ST | **NAND\_D1\_PD7** | **NAND\_D1\_PD7** |
| F16 | D16 | VDDNF | GPIO | PD8 | I/O | – | – | A | D18 | I/O | PIO, I, PU, ST | **NAND\_D2\_PD8** | **NAND\_D2\_PD8** |
| J15 | J14 | VDDNF | GPIO | PD9 | I/O | – | – | A | D19 | I/O | PIO, I, PU, ST | **NAND\_D3\_PD9** | **NAND\_D3\_PD9** |
| F15 | E17 | VDDNF | GPIO | PD10 | I/O | – | – | A | D20 | I/O | PIO, I, PU, ST | **NAND\_D4\_PD10** | **NAND\_D4\_PD10** |
| M16 | E15 | VDDNF | GPIO | PD11 | I/O | – | – | A | D21 | I/O | PIO, I, PU, ST | **NAND\_D5\_PD11** | **NAND\_D5\_PD11** |
| J13 | E16 | VDDNF | GPIO | PD12 | I/O | – | – | A | D22 | I/O | PIO, I, PU, ST | **NAND\_D6\_PD12** | **NAND\_D6\_PD12** |
| H14 | D17 | VDDNF | GPIO | PD13 | I/O | – | – | A | D23 | I/O | PIO, I, PU, ST | **NAND\_D7\_PD13** | **NAND\_D7\_PD13** |
| H15 | F14 | VDDNF | GPIO | PD14 | I/O | – | – | A | D24 | I/O | PIO, I, PU, ST |  |  |
|  H13 |  H14 |  VDDNF |  GPIO |  PD15 |  I/O |  – |  – | A | D25 | I/O |  A20, O, PD | **USBC\_EN\_PD15** | **USBC\_EN\_PD15** |
|  |  |  |  |  |  |  |  | B | A20 | O |  |  |  |
|  J14 |  H16 |  VDDNF |  GPIO |  PD16 |  I/O |  – |  – | A | D26 | I/O |  A23, O, PD | **MBUS\_NRST\_PD16 (INSTEAD OF MPU\_NRSTOUT\_PB25), RPI\_GPIO16\_PD16** |  |
|  |  |  |  |  |  |  |  | B | A23 | O |  |  |  |
|  J16 |  H17 |  VDDNF |  GPIO |  PD17 |  I/O |  WKUP12 |  – | A | D27 | I/O |  A24, O, PD | **RGBLED\_RED\_PD17** |  |
|  |  |  |  |  |  |  |  | B | A24 | O |  |  |  |
|  J12 |  G15 |  VDDNF |  GPIO |  PD18 |  I/O |  WKUP13 |  – | A | D28 | I/O |  A25, O, PD | **USBB\_EN\_PD18, RPI\_GPIO0\_PD17** | **USBB\_EN\_PD18** |
|  |  |  |  |  |  |  |  | B | A25 | O |  |  |  |
|  K16 |  G16 |  VDDNF |  GPIO |  PD19 |  I/O |  – |  – | A | D29 | I/O |  PIO, I, PU, ST | **RGBLED\_GREEN\_PD19** |  |
|  |  |  |  |  |  |  |  | B | NCS2 | O |  |  |  |
|  K15 |  K15 |  VDDNF |  GPIO |  PD20 |  I/O |  – |  – | A | D30 | I/O |  PIO, I, PU, ST | **RPI\_GPIO25\_PD20** |  |
|  |  |  |  |  |  |  |  | B | NCS4 | O |  |  |  |
|  H16 |  G17 |  VDDNF |  GPIO |  PD21 |  I/O |  – |  – | A | D31 | I/O |  PIO, I, PU, ST | **RGBLED\_BLUE\_PD21** |  |
|  |  |  |  |  |  |  |  | B | NCS5 | O |  |  |  |
| A15 | C8 | VDDIOM | – | DDR\_CAL | I/O | – | – | – | – | – | I | **DDR\_CAL** | **DDR\_CAL** |
| D12 | A14 | VDDIOM | – | DDR\_VREF | I/O | – | – | – | – | – | I | **DDR\_VREF** | **DDR\_VREF** |
| D5 | B1 | VDDANA | – | ADVREFP | I | – | – | – | – | – | I | **ADVERFP** | **ADVERFP** |
| C5 | C1 | VDDANA | – | ADVREFN | I | – | – | – | – | – | I | **ADVREFN** | **ADVREFN** |
| P12 | P17 | VDDIN33 | – | RTUNE | I/O | – | – | – | – | – | I | **USB\_RTUNE** | **USB\_RTUNE** |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
| T12 | T15 | VDDIN33 | – | HHSDPA | I/O | DHSDP | – | – | – | – | O, PD | **USBA\_P** | **USBA\_P** |
| R12 | U16 | VDDIN33 | – | HHSDMA | I/O | DHSDM | – | – | – | – | O, PD | **USBA\_N** | **USBA\_N** |
| T13 | T17 | VDDIN33 | – | HHSDPB | I/O | – | – | – | – | – | O, PD | **USBB\_P** | **USBB\_P** |
| T14 | R17 | VDDIN33 | – | HHSDMB | I/O | – | – | – | – | – | O, PD | **USBB\_N** | **USBB\_N** |
| T15 | P16 | VDDIN33 | – | HHSDPC | I/O | – | – | – | – | – | O, PD | **USBC\_P** | **USBC\_P** |
| R14 | P15 | VDDIN33 | – | HHSDMC | I/O | – | – | – | – | – | O, PD | **USBC\_N** | **USBC\_N** |
| T11 | L16 | VDDBU | – | WKUP0 | I | – | – | – | – | – | I, ST | **WAKE\_UP** | **WAKE\_UP** |
| R11 | N17 | VDDBU | – | SHDN | O | – | – | – | – | – | O, PD | **SHDN** | **SHDN** |
| P9 | N14 | VDDBU | – | JTAGSEL | I | – | – | – | – | – | I, PD |  |  |
| R3 | P12 | VDDIOP0 | – | TCK | I | – | – | – | – | – | I, ST | **TCK** | **TCK** |
| F3 | L15 | VDDIOP0 | – | TDI | I | – | – | – | – | – | I, ST | **TDI** | **TDI** |
| B4 | N15 | VDDIOP0 | – | TDO | O | – | – | – | – | – | O | **TDO** | **TDO** |
| E3 | N16 | VDDIOP0 | – | TMS | I | – | – | – | – | – | I, ST | **TMS** | **TMS** |
| T2 | N4 | VDDIOP0 | – | RTCK | O | – | – | – | – | – | O | **RTCK** | **RTCK** |
| P1 | P1 | VDDIOP0 | – | NRST | I | – | – | – | – | – | I, PU, ST | **NRST** | **NRST** |
| T9 | U10 | VDDBU | – | XIN32 | I | – | – | – | – | – | I | **XIN32K** | **XIN32K** |
| R9 | T10 | VDDBU | – | XOUT32 | I/O | – | – | – | – | – | O | **XOUT32K** | **XOUT32K** |
| R10 | T11 | VDDIN33 | – | XIN | I | – | – | – | – | – | I | **XIN32M** | **XIN32M** |
| T10 | U11 | VDDIN33 | – | XOUT | I/O | – | – | – | – | – | O | **XOUT24M** | **XOUT24M** |
| F11, F12, G14 | D11, E14, G14 | VDDIOM | power | – | – | – | – | – | – | – | – |  |  |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
|             A1, T1, N2, G5, K5, E7, M7, H8, J8, H9, J9, E10, G12, K12, B13, N15, A16, T16 | A1, U1, B2, T2, F3, J3, R3, D4, P4, E5, L5, M5, N5, E6, F6, G6, M6, N6, E7, F7, H8, J8, K8, C9, H9, J9, K9, R9, H10, J10, K10, P10, M11, R11, L12, M12, N12, A13, B13, C13, L13, M13, N13, B14, L14, M14, P14, A15, J15, R15, U15, R16, T16, U17 |                 GND |                 ground |                 – |                 – |                 – |                 – |                 – |                 – |                 – |                 – |  |  |
| K14 | M15 | VDDNF | power | – | – | – | – | – | – | – | – |  |  |
| J4, J5 | K4, L4, F5 | VDDIOP0 | power | – | – | – | – | – | – | – | – |  |  |
| N5 | M3 | VDDIOP1 | power | – | – | – | – | – | – | – | – |  |  |
| P7 | R6 | VDDBU | power | – | – | – | – | – | – | – | – |  |  |
| E4 | C2 | VDDANA | power | – | – | – | – | – | – | – | – |  |  |
| C4 | C3 | GNDANA | ground | – | – | – | – | – | – | – | – |  |  |
| P10 | P11 | VDDOUT25 | output | – | – | – | – | – | – | – | – |  |  |
| L11, P13 | R12, N11 | VDDIN33 | power | – | – | – | – | – | – | – | – |  |  |
| M10, R13 | P7, N7 | GNDIN33 | ground | – | – | – | – | – | – | – | – |  |  |


| **.**	**continued** |
| - |
|  **196-ball BGArotatethispage90** |   **233-ball BGA** |   **Power Rail** |   **I/O Type** | **Primary** | **Alternate** | **PIO Peripheral** | **Reset State** | **SAM9X60 Curiosity** | **Medicam** |
|  |  |  |  |  **Signal** |  **Dir** |  **Signal** |  **Dir** |  **Func** |  **Signal** |  **Dir** | **Signal, Dir, PU, PD, HiZ, ST, SEC, FILTER** |  |  |
| E8, F6, L6 | G5, D6, L6, M7, D8 | VDDCORE | power | – | – | – | – | – | – | – | – |  |  |
| C7 | C6 | VDDQSPI | power | – | – | – | – | – | – | – | – |  |  |
|  B10, B12, B14, C12, C15, D14, E14, F14 | D15, C16, B17, E11, E12, D13, F13, G13, C14, B15, A16 |    DDRM\_VDD |    power |    – |    – |    – |    – |    – |    – |    – |    – |  |  |
| A10, A13, A14, C11, C16, D16, E15, G16 | F15, F11, C12, F12, G12, E13, D14, C15, B16, A17 |   DDRM\_VSS |   ground |   – |   – |   – |   – |   – |   – |   – |   – |  |  |
| E11, C13, E13, D15, B16, E16, A12 |   – |   – |   NC |   – |   – |   – |   – |   – |   – |   – |   – |  |  |


