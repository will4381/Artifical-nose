import SwiftUI
import Charts

// MARK: - Data Models

struct Sensor: Identifiable {
    let id = UUID()
    let name: String
    var currentValue: Double
    var history: [Double]
}

// MARK: - Custom Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding()
            .foregroundColor(.white)
            .background(Color.accentColor)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .shadow(color: Color.gray.opacity(0.5), radius: 5, x: 0, y: 5)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding()
            .foregroundColor(.accentColor)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var sensors: [Sensor] = [
        Sensor(name: "MQ-3 (Alcohol)", currentValue: 1.0, history: []),
        Sensor(name: "MQ-4 (Methane)", currentValue: 1.0, history: []),
        Sensor(name: "MQ-7 (Carbon Monoxide)", currentValue: 1.0, history: []),
        Sensor(name: "MQ-135 (Air Quality)", currentValue: 1.0, history: []),
        Sensor(name: "BME680 Temperature (°C)", currentValue: 0.0, history: []),
        Sensor(name: "BME680 Humidity (%)", currentValue: 0.0, history: []),
        Sensor(name: "BME680 Pressure (hPa)", currentValue: 0.0, history: []),
        Sensor(name: "SGP30 eCO2 (ppm)", currentValue: 0.0, history: []),
        Sensor(name: "SGP30 TVOC (ppb)", currentValue: 0.0, history: [])
    ]
    
    @State private var arduinoIP: String = ""
    @State private var isConnected: Bool = false
    @State private var isRecording: Bool = false
    @State private var recordingTimeLeft: Int = 10
    @State private var labelInput: String = ""
    @State private var showLabelAlert: Bool = false
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false
    @State private var dataFetchTimer: Timer?
    
    @State private var isCalibrating: Bool = false
    @State private var showCalibrationAlert: Bool = false
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 30) {
                        HeaderView()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        
                        WiFiIntegrationSection(arduinoIP: $arduinoIP,
                                               isConnected: $isConnected,
                                               connectAction: connectToArduino)
                            .padding(.horizontal)
                        
                        CalibrationSection(isCalibrating: $isCalibrating,
                                           calibrateAction: calibrateSensors)
                            .padding(.horizontal)
                        
                        SensorDataSection(sensors: $sensors, geometry: geometry)
                            .padding(.horizontal)
                        
                        CreateEntrySection(
                            isRecording: $isRecording,
                            labelInput: $labelInput,
                            recordingTimeLeft: $recordingTimeLeft,
                            startRecordingAction: startRecording
                        )
                        .padding(.horizontal)
                        
                        Spacer()
                        
                        FooterView()
                            .padding(.bottom, 10)
                    }
                    .padding(.vertical)
                    .frame(width: geometry.size.width)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Artificial Nose")
            .alert(isPresented: $showLabelAlert) {
                Alert(title: Text("Recording Complete"),
                      message: Text("Your data has been recorded and saved."),
                      dismissButton: .default(Text("OK")))
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(title: Text("Error"),
                      message: Text(errorMessage ?? "An unknown error occurred"),
                      dismissButton: .default(Text("OK")))
            }
            .alert(isPresented: $showCalibrationAlert) {
                Alert(title: Text("Calibration Complete"),
                      message: Text("Sensors have been calibrated."),
                      dismissButton: .default(Text("OK")))
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Wi-Fi Integration Functions
    
    func connectToArduino() {
        if isConnected {
            dataFetchTimer?.invalidate()
            isConnected = false
        } else {
            guard !arduinoIP.isEmpty else {
                showError("Please enter the Arduino IP address.")
                return
            }
            isConnected = true
            startFetchingData()
        }
    }
    
    func startFetchingData() {
        dataFetchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            fetchSensorData()
        }
    }
    
    func fetchSensorData() {
        guard let url = URL(string: "http://\(arduinoIP)") else {
            showError("Invalid URL")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                self.showError("Error fetching data: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                self.showError("No data received")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        self.updateSensors(with: json)
                    }
                }
            } catch {
                self.showError("Error parsing JSON: \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }
    
    func updateSensors(with json: [String: Any]) {
        let sensorKeys = ["mq0", "mq1", "mq2", "mq3", "temperature", "humidity", "pressure", "eCO2", "TVOC"]
        
        for (index, key) in sensorKeys.enumerated() {
            if let value = json[key] as? Double, !value.isNaN {
                sensors[index].currentValue = value
                sensors[index].history.append(value)
                if sensors[index].history.count > 50 {
                    sensors[index].history.removeFirst()
                }
            }
        }
    }
    
    // MARK: - Calibration Function
    
    func calibrateSensors() {
        guard isConnected else {
            showError("Not connected to Arduino.")
            return
        }
        
        guard let url = URL(string: "http://\(arduinoIP)/calibrate") else {
            showError("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        isCalibrating = true
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isCalibrating = false
                if let error = error {
                    self.showError("Error during calibration: \(error.localizedDescription)")
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String,
                   status == "Calibration completed" {
                    self.showCalibrationAlert = true
                } else {
                    self.showError("Failed to parse calibration response.")
                }
            }
        }
        task.resume()
    }
    
    // MARK: - Recording Functions
    
    func startRecording() {
        guard !labelInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        guard let url = URL(string: "http://\(arduinoIP)/startRecording") else {
            showError("Invalid URL for start recording")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let postString = "label=\(labelInput)"
        request.httpBody = postString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.showError("Error starting recording: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    self.showError("Invalid response from Arduino")
                    return
                }
                
                self.isRecording = true
                self.startCountdown()
            }
        }
        task.resume()
    }
    
    func startCountdown() {
        recordingTimeLeft = 10
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.recordingTimeLeft > 0 {
                self.recordingTimeLeft -= 1
            } else {
                timer.invalidate()
                self.isRecording = false
                self.labelInput = ""
                self.showLabelAlert = true
            }
        }
    }
    
    func showError(_ message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
    }
}

// MARK: - HeaderView

struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Artificial Nose")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            
            Text("Real-time Scent Detection")
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - WiFiIntegrationSection

struct WiFiIntegrationSection: View {
    @Binding var arduinoIP: String
    @Binding var isConnected: Bool
    var connectAction: () -> Void
    
    var body: some View {
        GroupBox(label:
                    Label("Wi-Fi Integration", systemImage: "wifi")
                        .font(.headline)
        ) {
            VStack(alignment: .leading, spacing: 15) {
                TextField("Enter Arduino IP Address", text: $arduinoIP)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.decimalPad)
                
                Button(action: connectAction) {
                    Label(isConnected ? "Disconnect" : "Connect", systemImage: isConnected ? "link.slash" : "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - CalibrationSection

struct CalibrationSection: View {
    @Binding var isCalibrating: Bool
    var calibrateAction: () -> Void
    
    var body: some View {
        GroupBox(label:
                    Label("Calibration", systemImage: "gauge.badge.plus")
                        .font(.headline)
        ) {
            VStack(alignment: .leading, spacing: 15) {
                Button(action: calibrateAction) {
                    if isCalibrating {
                        HStack {
                            ProgressView()
                            Text("Calibrating...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Calibrate Sensors", systemImage: "gauge.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isCalibrating)
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - SensorDataSection

struct SensorDataSection: View {
    @Binding var sensors: [Sensor]
    let geometry: GeometryProxy
    
    var body: some View {
        GroupBox(label:
                    Label("Sensor Data", systemImage: "waveform.path.ecg")
                        .font(.headline)
        ) {
            let columns = [
                GridItem(.adaptive(minimum: geometry.size.width > 700 ? 300 : geometry.size.width - 40), spacing: 20)
            ]
            
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(sensors) { sensor in
                    SensorView(sensor: sensor)
                }
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - SensorView

struct SensorView: View {
    let sensor: Sensor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(sensor.name)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.2f", sensor.currentValue))
                    .foregroundColor(.accentColor)
            }
            .font(.headline)
            
            if !sensor.history.isEmpty {
                Chart {
                    ForEach(Array(sensor.history.enumerated()), id: \.offset) { offset, value in
                        LineMark(
                            x: .value("Time", offset),
                            y: .value("Value", value)
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: getChartScale(for: sensor.history))
                .frame(height: 100)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(8)
            } else {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            if let trend = getTrend(for: sensor) {
                HStack {
                    Image(systemName: trend.isIncreasing ? "arrow.up" : "arrow.down")
                        .foregroundColor(trend.isIncreasing ? .green : .red)
                    Text("\(trend.percentageChange > 0 ? "+" : "")\(String(format: "%.1f", trend.percentageChange))% \(trend.isIncreasing ? "Increase" : "Decrease")")
                                            .font(.caption)
                                            .foregroundColor(trend.isIncreasing ? .green : .red)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
                            .shadow(color: Color.gray.opacity(0.2), radius: 5, x: 0, y: 5)
                        }
                        
                        // Helper Functions
                        func getChartScale(for history: [Double]) -> ClosedRange<Double> {
                            let validHistory = history.filter { !$0.isNaN }
                            guard let min = validHistory.min(), let max = validHistory.max(), min != max else {
                                return 0...1
                            }
                            let padding = (max - min) * 0.1
                            return (min - padding)...(max + padding)
                        }
                        
                        func getTrend(for sensor: Sensor) -> (isIncreasing: Bool, percentageChange: Double)? {
                            let validHistory = sensor.history.filter { !$0.isNaN }
                            guard validHistory.count >= 2 else { return nil }
                            let previous = validHistory[validHistory.count - 2]
                            let current = validHistory.last!
                            let change = current - previous
                            let percentage = previous != 0 ? (change / previous) * 100 : 0
                            return (change > 0, abs(percentage))
                        }
                    }

                    // MARK: - CreateEntrySection

                    struct CreateEntrySection: View {
                        @Binding var isRecording: Bool
                        @Binding var labelInput: String
                        @Binding var recordingTimeLeft: Int
                        var startRecordingAction: () -> Void
                        
                        var body: some View {
                            GroupBox(label: Label("Create an Entry", systemImage: "pencil.tip").font(.headline)) {
                                VStack(alignment: .leading, spacing: 15) {
                                    TextField("Enter Scent Label", text: $labelInput)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .disabled(isRecording)
                                    
                                    Button(action: startRecordingAction) {
                                        if isRecording {
                                            HStack {
                                                ProgressView()
                                                Text("Recording... (\(recordingTimeLeft)s)")
                                            }
                                            .frame(maxWidth: .infinity)
                                        } else {
                                            Label("Start Recording", systemImage: "record.circle")
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(labelInput.trimmingCharacters(in: .whitespaces).isEmpty || isRecording)
                                }
                                .padding(.vertical, 10)
                            }
                        }
                    }

                    // MARK: - FooterView

                    struct FooterView: View {
                        var body: some View {
                            Text("RELATIVE COMPANIES ARTIFICIAL NOSE ALPHA 1.0 © 2024")
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }
                    }

                    // MARK: - Preview

                    struct ContentView_Previews: PreviewProvider {
                        static var previews: some View {
                            Group {
                                ContentView()
                                    .previewDevice("iPhone 14")
                                
                                ContentView()
                                    .previewDevice("iPad Pro (12.9-inch) (6th generation)")
                            }
                        }
                    }
