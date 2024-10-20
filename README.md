# Artifical Nose Project

Utilizes an Arduino UNO R4 w/WiFi and several gas and enviromental sensors, which return data over WiFi to the Swift app interface. 

### Sensors Used
- BME680: Used to gather environment data to calibrate the sensors for accurate readings no matter the location
- SGP-30: Gathers TVoC data as well as organic CO2 concentrations
- MQ-3, MQ-4, MQ-7, and MQ-135: General gas readings and concentrations

### Other
We use a micro-sd card module as well to store calibration data and training data. Training data is simply sensor values for 10 seconds with a label of the object which is applied in the app. This data will eventually go on to train a ML model to detect smells.
The caveat is I was having trouble with the data recording, and thus that feature is currently not working.

### Build Your Own

#### BME680 Sensor

VCC to 3.3V
GND to GND
SCL to SCL (A5 on most Arduinos)
SDA to SDA (A4 on most Arduinos)


#### SGP30 Sensor

VCC to 3.3V
GND to GND
SCL to SCL (same as BME680)
SDA to SDA (same as BME680)


#### MQ Sensors

VCC to 5V
GND to GND
Analog output to A0, A1, A2, A3 respectively


#### SD Card Module

CS to Digital Pin 10
MOSI to Digital Pin 11
MISO to Digital Pin 12
SCK to Digital Pin 13
VCC to 5V
GND to GND



#### Setup Instructions

- Upload the provided code to your Arduino board.
- Connect to the Wi-Fi network specified in the code.
- Access the sensor data through the Arduino's IP address.
- Use the /startRecording endpoint to begin data collection.
- Use the /calibrate endpoint to calibrate the sensors.
