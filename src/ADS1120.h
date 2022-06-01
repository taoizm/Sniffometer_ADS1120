/*
 * A simplified library for ADS1120 16-bit ADC.
 *
 * Copyright (c) 2021 Kentaro Tao
 * This software is released under the MIT License.
 * http://opensource.org/licenses/MIT
 *
 * For further information, see https://github.com/taoizm/Sniffometer_ADS1120
 */

#ifndef ADS1120_h
#define ADS1120_h
#include <Arduino.h>
#include <SPI.h>

#define RESET 0x06
#define START 0x08
#define PDOWN 0x02
#define RREG  0x20
#define WREG  0x40
#define DUMMY 0xFF

#define CONFIG_REG0_ADDR 0x00
#define CONFIG_REG1_ADDR 0x01
#define CONFIG_REG2_ADDR 0x02
#define CONFIG_REG3_ADDR 0x03

class ADS1120
{
private:
  uint8_t cs_pin_ = 10;
  uint8_t drdy_pin_ = 14;
  uint8_t config_reg0_ = 0x04; // AINP=AIN0, AINN=AIN1, GAIN=4, PGA enabled
  uint8_t config_reg1_ = 0xD0; // DR=2000 SPS, MODE=Turbo, CM=Single-Shot, TS disabled, BCS off
  uint8_t config_reg2_ = 0x40; // VREF REFP0, No 50/60-Hz rejection, PSW open, IDAC off
  uint8_t config_reg3_ = 0x00; // IDAC1 disabled, IDAC2 disabled, DRDY pin only
 public:
  ADS1120();
  void begin(uint8_t cs_pin, uint8_t drdy_pin);
  void beginTransaction();
  void endTransaction();
  void sendCommand(uint8_t cmd);
  void writeRegister(uint8_t addr, const uint8_t &val);
  uint8_t readRegister(uint8_t addr);
  void readADC();
  union {
    int16_t int16;
    struct {
        uint8_t LSB;
        uint8_t MSB;
    } uint8;
  } analogData;
};
#endif