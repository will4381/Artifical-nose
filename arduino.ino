#include <WiFiS3.h>
#include <Wire.h>
#include <Adafruit_BME680.h>
#include <Adafruit_SGP30.h>
#include <EEPROM.h>
#include <SD.h>
#include <SPI.h>

// Wi-Fi network credentials
const char* ssid = "";
const char* password = "";

// Create sensor objects
Adafruit_BME680 bme;
Adafruit_SGP30 sgp;

// Flags to check if sensors are detected
bool bme680Found = false;
bool sgp30Found = false;

// Wi-Fi server
WiFiServer server(80);

// SD card CS pin
#define SD_CS_PIN 10  // Digital pin 10 for CS

// Define Calibration Data Structure
struct CalibrationData {
  uint32_t magicNumber;
  int mqCalibration[4];
  uint16_t sgpBaseline[2];
};

#define CALIBRATION_MAGIC_NUMBER 0x12345678

// EEPROM size
#define EEPROM_SIZE sizeof(CalibrationData)

// Recording variables
bool isRecording = false;
unsigned long recordingStartTime = 0;
const unsigned long recordingDuration = 10000; // 10 seconds
String currentLabel = "";
File dataFile;

void setup() {
  // Initialize Serial communication
  Serial.begin(115200);
  while (!Serial) {
    ; // Wait for serial port to connect
  }
  Serial.println("Serial communication started");

  // Initialize I2C communication
  Wire.begin();
  Wire.setClock(100000);

  // Scan I2C devices
  scanI2C();

  // Initialize BME680 sensor
  Serial.println("Initializing BME680 sensor...");
  if (bme.begin(0x76)) {
    Serial.println("BME680 sensor found and initialized!");
    bme680Found = true;
    bme.setTemperatureOversampling(BME680_OS_8X);
    bme.setHumidityOversampling(BME680_OS_2X);
    bme.setPressureOversampling(BME680_OS_4X);
    bme.setIIRFilterSize(BME680_FILTER_SIZE_3);
    bme.setGasHeater(320, 150);
  } else {
    Serial.println("Error: BME680 sensor not found or failed to initialize.");
  }

  // Initialize SGP30 sensor
  Serial.println("Initializing SGP30 sensor...");
  if (sgp.begin()) {
    Serial.println("SGP30 sensor found and initialized!");
    sgp30Found = true;
  } else {
    Serial.println("Error: SGP30 sensor not found or failed to initialize.");
  }

  // Initialize SD card
  Serial.print("Initializing SD card...");
  if (!SD.begin(SD_CS_PIN)) {
    Serial.println("Initialization failed!");
  } else {
    Serial.println("Initialization done.");
  }

  // Initialize EEPROM
  EEPROM.begin();

  // Connect to Wi-Fi network
  Serial.println("Connecting to Wi-Fi...");
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nConnected to Wi-Fi!");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  // Start the server
  server.begin();
  Serial.println("Server started");
}

void loop() {
  // Check if we're currently recording
  if (isRecording) {
    if (millis() - recordingStartTime < recordingDuration) {
      recordSensorData();
    } else {
      stopRecording();
    }
  }

  // Listen for incoming clients
  WiFiClient client = server.available();

  if (client) {
    String currentLine = "";
    
    while (client.connected()) {
      if (client.available()) {
        char c = client.read();
        
        if (c == '\n') {
          if (currentLine.length() == 0) {
            client.println("HTTP/1.1 200 OK");
            client.println("Content-type:application/json");
            client.println("Connection: close");
            client.println();
            
            if (currentLine.startsWith("POST /startRecording")) {
              // Extract label from the request body
              while (client.available()) {
                String body = client.readStringUntil('\r');
                int labelStart = body.indexOf("label=");
                if (labelStart != -1) {
                  currentLabel = body.substring(labelStart + 6);
                  currentLabel.trim();
                  startRecording();
                  client.println("{\"status\":\"Recording started\"}");
                  Serial.println("Received recording command. Label: " + currentLabel);
                  break;
                }
              }
            } else if (currentLine.startsWith("POST /calibrate")) {
              calibrateSensors();
              client.println("{\"status\":\"Calibration completed\"}");
            } else {
              // Send sensor data
              client.println(getSensorDataJson());
            }
            break;
          } else {
            currentLine = "";
          }
        } else if (c != '\r') {
          currentLine += c;
        }
      }
    }
    client.stop();
  }
}

void startRecording() {
  if (!isRecording) {
    dataFile = SD.open("training_data.csv", FILE_WRITE);
    if (dataFile) {
      if (dataFile.size() == 0) {
        dataFile.println("label,timestamp,mq0,mq1,mq2,mq3,temperature,humidity,pressure,gas_resistance,eCO2,TVOC");
      }
      isRecording = true;
      recordingStartTime = millis();
      Serial.println("Started recording to training_data.csv");
    } else {
      Serial.println("Error opening training_data.csv");
    }
  }
}

void stopRecording() {
  if (isRecording) {
    dataFile.close();
    isRecording = false;
    Serial.println("Stopped recording");
  }
}

void recordSensorData() {
  CalibrationData calibData;
  readCalibrationData(calibData);

  String dataString = currentLabel + "," + String(millis() - recordingStartTime);

  // Read and calibrate MQ sensors
  for (int i = 0; i < 4; i++) {
    int rawValue = analogRead(i);
    float calibratedValue = calibData.mqCalibration[i] != 0 ? (float)rawValue / calibData.mqCalibration[i] : 1.0;
    dataString += "," + String(calibratedValue, 4);
  }

  // Read BME680 sensor
  if (bme680Found && bme.performReading()) {
    dataString += "," + String(bme.temperature, 2);
    dataString += "," + String(bme.humidity, 2);
    dataString += "," + String(bme.pressure / 100.0, 2);
    dataString += "," + String(bme.gas_resistance / 1000.0, 2);
  } else {
    dataString += ",,,,,";
  }

  // Read SGP30 sensor
  if (sgp30Found && sgp.IAQmeasure()) {
    dataString += "," + String(sgp.eCO2);
    dataString += "," + String(sgp.TVOC);
  } else {
    dataString += ",,";
  }

  dataFile.println(dataString);
  dataFile.flush();
}

String getSensorDataJson() {
  CalibrationData calibData;
  readCalibrationData(calibData);

  String json = "{";

  // MQ sensors
  for (int i = 0; i < 4; i++) {
    int rawValue = analogRead(i);
    float calibratedValue = calibData.mqCalibration[i] != 0 ? (float)rawValue / calibData.mqCalibration[i] : 1.0;
    json += "\"mq" + String(i) + "\":" + String(calibratedValue, 4);
    if (i < 3) json += ",";
  }

  // BME680 sensor
  if (bme680Found && bme.performReading()) {
    json += ",\"temperature\":" + String(bme.temperature, 2);
    json += ",\"humidity\":" + String(bme.humidity, 2);
    json += ",\"pressure\":" + String(bme.pressure / 100.0, 2);
    json += ",\"gas_resistance\":" + String(bme.gas_resistance / 1000.0, 2);
  }

  // SGP30 sensor
  if (sgp30Found && sgp.IAQmeasure()) {
    json += ",\"eCO2\":" + String(sgp.eCO2);
    json += ",\"TVOC\":" + String(sgp.TVOC);
  }

  json += "}";
  return json;
}

void calibrateSensors() {
  CalibrationData calibData;
  calibData.magicNumber = CALIBRATION_MAGIC_NUMBER;

  // Calibrate MQ sensors
  for (int i = 0; i < 4; i++) {
    calibData.mqCalibration[i] = analogRead(i);
  }

  // Calibrate SGP30
  if (sgp30Found) {
    if (sgp.getIAQBaseline(&calibData.sgpBaseline[0], &calibData.sgpBaseline[1])) {
      Serial.println("SGP30 baseline values stored");
    } else {
      Serial.println("Failed to get SGP30 baseline values");
      calibData.sgpBaseline[0] = 0;
      calibData.sgpBaseline[1] = 0;
    }
  }

  writeCalibrationData(calibData);
  Serial.println("Calibration data saved to EEPROM");
}

void writeCalibrationData(const CalibrationData& data) {
  EEPROM.put(0, data);
}

void readCalibrationData(CalibrationData& data) {
  EEPROM.get(0, data);
  if (data.magicNumber != CALIBRATION_MAGIC_NUMBER) {
    Serial.println("No calibration data found. Initializing to defaults.");
    data.magicNumber = CALIBRATION_MAGIC_NUMBER;
    for (int i = 0; i < 4; i++) {
      data.mqCalibration[i] = 1; // Avoid division by zero
    }
    data.sgpBaseline[0] = 0;
    data.sgpBaseline[1] = 0;
    writeCalibrationData(data); // Save default calibration
  }
}

void scanI2C() {
  Serial.println("\nI2C Scanner");
  byte error, address;
  int nDevices = 0;

  for (address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    error = Wire.endTransmission();

    if (error == 0) {
      Serial.print("I2C device found at address 0x");
      if (address < 16) Serial.print("0");
      Serial.println(address, HEX);
      nDevices++;
    } else if (error == 4) {
      Serial.print("Unknown error at address 0x");
      if (address < 16) Serial.print("0");
      Serial.println(address, HEX);
    }
  }

  if (nDevices == 0)
    Serial.println("No I2C devices found\n");
  else
    Serial.println("done\n");
}
