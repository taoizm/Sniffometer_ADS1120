/*
 * Code for a sniffing measurement system using an NTC thermistor
 * built on Teensy 4.0 and ADS1120 16-bit ADC.
 *
 * Copyright (c) 2021 Kentaro Tao
 * This software is released under the MIT License.
 * http://opensource.org/licenses/MIT
 *
 * For further information, see https://github.com/taoizm/Sniffometer_ADS1120
 */

#include <Arduino.h>
#include <IntervalTimer.h>
#include <SPI.h>
#include "ADS1120.h"

#define CS   10
#define DRDY 14
#define TRIG 17
#define RED  18
#define BLUE 19

#define BUFFER_SIZE 20

ADS1120 ads1120;

IntervalTimer Timer;

uint32_t samplingRate = 1000; // Hz
unsigned long timerPeriod = (1/(double)samplingRate)*1000000; // microseconds

char opcode;
boolean isStreaming = false;

byte bufferPos = 0;
volatile union {
  int16_t int16Array[BUFFER_SIZE];
  uint8_t uint8Array[BUFFER_SIZE*2];
} buffer;

void setup() {
  // Set pin mode 
  pinMode(TRIG,INPUT);
  pinMode(RED,OUTPUT);
  pinMode(BLUE,OUTPUT);

  analogWriteResolution(8); // 0-255

  Serial.begin(115200);
  delay(1000);

  // Indicate booting
  analogWrite(RED,177); // 3.3V, 47Ohm, 5mA, Vf=2.1V

  ads1120.begin(CS,DRDY);

  // Configure DRDY pin as a falling edge triggered interrupt input
  attachInterrupt(digitalPinToInterrupt(DRDY), drdyInterruptHandler, FALLING);

  // Configure TRIG pin as a rising edge triggered interrupt input
  attachInterrupt(digitalPinToInterrupt(TRIG), trigInterruptHandler, RISING);

  // Indicate running
  analogWrite(RED,0);
  analogWrite(BLUE,254); // 3.3V, 47Ohm, 5mA, Vf=3.1V
}

void loop() {
  if (Serial.available()) {
    opcode = Serial.read();
    switch (opcode) {
      case 'S': // Start or stop data stream
        if (isStreaming) {
          Timer.end();
          if (bufferPos>0) {
            sendBuffer(); // Send reminder data
          }
        } else {
          Timer.begin(timerCallback,timerPeriod);
        }
        isStreaming = !isStreaming;
    }
  }
}

void drdyInterruptHandler() {
    ads1120.readADC();    
    buffer.int16Array[bufferPos++] = ads1120.analogData.int16;
    if (bufferPos == BUFFER_SIZE) {
      sendBuffer();
    }
}

void trigInterruptHandler() {
  if (bufferPos>0) {
    sendBuffer();
  }
  Serial.write('T'); // Trigger opcode
}

void timerCallback() {
  ads1120.sendCommand(START);
}

void sendBuffer() {
  Serial.write('D'); // Data stream opcode
  Serial.write(bufferPos); // Number of values
  Serial.write((uint8_t *)buffer.uint8Array,bufferPos*2); // Send binary data
  bufferPos = 0; // Reset buffer position
}