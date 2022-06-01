/*
 * A simplified library for ADS1120 16-bit ADC.
 *
 * Copyright (c) 2021 Kentaro Tao
 * This software is released under the MIT License.
 * http://opensource.org/licenses/MIT
 *
 * For further information, see https://github.com/taoizm/Sniffometer_ADS1120
 */

#include <Arduino.h>
#include <SPI.h>
#include "ADS1120.h"

SPISettings mySPISettings(4096000,MSBFIRST,SPI_MODE1);

ADS1120::ADS1120() {

}

void ADS1120::begin(uint8_t cs_pin, uint8_t drdy_pin) {
  cs_pin_ = cs_pin;
  drdy_pin_ = drdy_pin;

  // Set pin mode
  pinMode(cs_pin_,OUTPUT);
  pinMode(drdy_pin_,INPUT);

  digitalWrite(cs_pin_,HIGH);

  SPI.begin();

  sendCommand(RESET);

  delay(100);

  // Write the respective register configuration
  writeRegister(CONFIG_REG0_ADDR, config_reg0_);
  writeRegister(CONFIG_REG1_ADDR, config_reg1_);
  writeRegister(CONFIG_REG2_ADDR, config_reg2_);
  writeRegister(CONFIG_REG3_ADDR, config_reg3_);

  // Read back all config regs for sanity check
  config_reg0_ = readRegister(CONFIG_REG0_ADDR);
  config_reg1_ = readRegister(CONFIG_REG1_ADDR);
  config_reg2_ = readRegister(CONFIG_REG2_ADDR);
  config_reg3_ = readRegister(CONFIG_REG3_ADDR);

  char message[24];
  sprintf(message,
    "Config reg : %02X %02X %02X %02X",
    config_reg0_, config_reg1_, config_reg2_, config_reg3_);
  Serial.println(message);

  delay(100);
}

void ADS1120::beginTransaction() {
  SPI.beginTransaction(mySPISettings);
  digitalWrite(cs_pin_,LOW);  // Set CS to the device low
  delayMicroseconds(1);       // Delay for a minimum of td(CSSC)
}

void ADS1120::endTransaction() {
  delayMicroseconds(1);       // Delay for a minimum of td(SCCS)
  digitalWrite(cs_pin_,HIGH); // Clear CS to high
  SPI.endTransaction();
}

void ADS1120::sendCommand(uint8_t cmd) {
  beginTransaction();  
  SPI.transfer(cmd);
  endTransaction();
}

void ADS1120::writeRegister(uint8_t addr, const uint8_t &val) {
  beginTransaction();
  SPI.transfer(WREG|(addr<<2));
  SPI.transfer(val);
  endTransaction();
}

uint8_t ADS1120::readRegister(uint8_t addr) {
  uint8_t val;

  beginTransaction();
  SPI.transfer(RREG|(addr<<2));
  val = SPI.transfer(DUMMY);
  endTransaction();

  return val;
}

void ADS1120::readADC() {
  beginTransaction();
  analogData.uint8.MSB = SPI.transfer(DUMMY);
  analogData.uint8.LSB = SPI.transfer(DUMMY);
  endTransaction();
}