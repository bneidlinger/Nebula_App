import SwiftUI
import Combine
import Foundation
import PhotosUI
import UIKit
import BackgroundTasks
import Security // Add Security framework for Keychain access

// MARK: - Models
struct Theme: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var description: String
    var icon: String // SF Symbol name
    var gradientColors: [Color]
    
    static let presets = [
        Theme(
            name: "Cosmic",
            description: "Deep space, galaxies, nebulae, and celestial bodies",
            icon: "sparkles.tv",
            gradientColors: [Color.purple, Color.blue.opacity(0.8)]
        ),
        Theme(
            name: "Neon City",
            description: "Cyberpunk urban landscapes with glowing neon lights",
            icon: "building.2",
            gradientColors: [Color.pink, Color.purple.opacity(0.8)]
        ),
        Theme(
            name: "Abstract",
            description: "Fluid shapes, bold colors, and geometric patterns",
            icon: "smoke",
            gradientColors: [Color.orange, Color.red.opacity(0.8)]
        ),
        Theme(
            name: "Minimal",
            description: "Clean, simple designs with subtle color gradients",
            icon: "square.on.circle",
            gradientColors: [Color.gray, Color.black.opacity(0.7)]
        ),
        Theme(
            name: "Nature",
            description: "Serene landscapes, forests, oceans, and natural beauty",
            icon: "leaf",
            gradientColors: [Color.green, Color.blue.opacity(0.7)]
        ),
        Theme(
            name: "Custom",
            description: "Create your own unique wallpaper description",
            icon: "wand.and.stars",
            gradientColors: [Color.teal, Color.blue.opacity(0.7)]
        )
    ]
}

// MARK: - WallpaperManager
class WallpaperManager: ObservableObject {
    @Published var currentImage: UIImage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var generationProgress: Double = 0
    
    private let keychain = KeychainSwift()
    private let userDefaults = UserDefaults.standard
    private var progressTimer: Timer?
    
    init() {
        // Load saved wallpaper if exists
        if let imageData = userDefaults.data(forKey: "lastWallpaperImage"),
           let image = UIImage(data: imageData) {
            self.currentImage = image
            self.lastUpdated = userDefaults.object(forKey: "lastWallpaperDate") as? Date
        }
        
        // Schedule daily refresh
        setupBackgroundTasks()
    }
    
    func setAPIKey(_ key: String) {
        keychain.set(key, forKey: "dallE_api_key")
    }
    
    private func getAPIKey() -> String? {
        return keychain.get("dallE_api_key")
    }
    
    func fetchNewWallpaper(theme: Theme, customPrompt: String? = nil) {
        guard let apiKey = getAPIKey() else {
            self.errorMessage = "API key not found. Please set your API key in settings."
            return
        }
        
        isLoading = true
        errorMessage = nil
        generationProgress = 0.1 // Start progress
        
        // Simulate progress during API call
        startProgressSimulation()
        
        let url = URL(string: "https://api.openai.com/v1/images/generations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create prompt based on theme or custom input
        let prompt: String
        if let customPrompt = customPrompt, !customPrompt.isEmpty {
            prompt = customPrompt
        } else {
            prompt = "Create a high-resolution futuristic \(theme.description) wallpaper for a smartphone. Use dramatic lighting and a cohesive color palette. Highly detailed."
        }
        
        // Get device screen dimensions for appropriate image size
        let screenSize = UIScreen.main.bounds.size
        let orientation = screenSize.width < screenSize.height ? "portrait" : "landscape"
        // Choose size based on orientation
        let requestedSize = orientation == "portrait" ? "1024x1792" : "1792x1024"
        
        let requestBody: [String: Any] = [
            "model": "dall-e-3", // Using latest model
            "prompt": prompt,
            "n": 1,
            "size": requestedSize,
            "quality": "hd"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            handleError("Failed to create request: \(error.localizedDescription)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                // Set progress to show we're about to process the result
                self?.generationProgress = 0.7
                
                if let error = error {
                    self?.handleError("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self?.handleError("No data received")
                    return
                }
                
                // Handle API errors with better parsing
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let errorObject = json["error"] as? [String: Any],
                               let message = errorObject["message"] as? String {
                                self?.handleError("API Error: \(message)")
                            } else {
                                self?.handleError("API Error: Status code \(httpResponse.statusCode)")
                            }
                        } else {
                            self?.handleError("API Error: Status code \(httpResponse.statusCode)")
                        }
                    } catch {
                        self?.handleError("API Error: Status code \(httpResponse.statusCode)")
                    }
                    return
                }
                
                // Parse successful response
                do {
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let images = jsonResponse["data"] as? [[String: Any]],
                       let imageUrl = images.first?["url"] as? String {
                        self?.generationProgress = 0.8
                        self?.downloadImage(from: imageUrl)
                    } else {
                        self?.handleError("Failed to parse API response")
                    }
                } catch {
                    self?.handleError("JSON parsing error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func startProgressSimulation() {
        // Cancel any existing timer
        progressTimer?.invalidate()
        
        // Simulate progress for better UX
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.isLoading && self.generationProgress < 0.6 {
                self.generationProgress += 0.05
            } else {
                timer.invalidate()
            }
        }
    }
    
    private func handleError(_ message: String) {
        self.isLoading = false
        self.errorMessage = message
        self.generationProgress = 0
        // Make sure to invalidate timer on error
        progressTimer?.invalidate()
    }
    
    private func downloadImage(from url: String) {
        guard let imageUrl = URL(string: url) else {
            self.handleError("Invalid image URL")
            return
        }
        
        URLSession.shared.dataTask(with: imageUrl) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.generationProgress = 0.9
                
                if let error = error {
                    self?.handleError("Image download failed: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data, let image = UIImage(data: data) else {
                    self?.handleError("Could not process downloaded image")
                    return
                }
                
                // Save image to UserDefaults for persistence
                self?.userDefaults.set(data, forKey: "lastWallpaperImage")
                
                // Update current date
                let now = Date()
                self?.lastUpdated = now
                self?.userDefaults.set(now, forKey: "lastWallpaperDate")
                
                self?.currentImage = image
                self?.saveImageToPhotos(image: image)
                
                // Finish progress and remove loading state
                self?.generationProgress = 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.isLoading = false
                    self?.generationProgress = 0
                    // Make sure to invalidate timer when complete
                    self?.progressTimer?.invalidate()
                }
            }
        }.resume()
    }
    
    private func saveImageToPhotos(image: UIImage) {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.errorMessage = "Photo library access denied"
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                request.creationDate = Date()
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if !success, let error = error {
                        self.errorMessage = "Failed to save to Photos: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // MARK: - Background Task Scheduling
    private func setupBackgroundTasks() {
        // Register for background fetch
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.yourapp.refreshWallpaper", using: nil) { [weak self] task in
            guard let self = self else {
                task.setTaskCompleted(success: false)
                return
            }
            
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        scheduleAppRefresh()
    }
    
    private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.yourapp.refreshWallpaper")
        
        // Schedule for next day
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.day! += 1
        components.hour = 2 // 2 AM
        components.minute = 0
        
        request.earliestBeginDate = Calendar.current.date(from: components)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Successfully scheduled app refresh")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule next refresh before doing work
        scheduleAppRefresh()
        
        // Create a task expiration handler
        let taskIdentifier = UIBackgroundTaskIdentifier.invalid
        
        // Create expiration handler
        task.expirationHandler = { [weak self] in
            // Cancel any ongoing work
            self?.isLoading = false
            if taskIdentifier != .invalid {
                UIApplication.shared.endBackgroundTask(taskIdentifier)
            }
        }
        
        // Create a background task to ensure our network calls complete
        let bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Cleanup if we're about to exceed background time
            self?.isLoading = false
        }
        
        // Get the user's preferred theme
        if let themeName = userDefaults.string(forKey: "selectedTheme"),
           let theme = Theme.presets.first(where: { $0.name == themeName }) {
            // Generate new wallpaper based on saved theme
            fetchNewWallpaper(theme: theme)
            
            // Listen for the generation to complete or fail
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                // This is a fallback in case the operation takes too long
                task.setTaskCompleted(success: !self.isLoading)
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        } else {
            task.setTaskCompleted(success: false)
            UIApplication.shared.endBackgroundTask(bgTask)
        }
    }
    
    deinit {
        progressTimer?.invalidate()
    }
}

// MARK: - Views
struct ContentView: View {
    @StateObject private var wallpaperManager = WallpaperManager()
    @State private var selectedTheme: Theme = Theme.presets[0]
    @State private var customPrompt: String = ""
    @State private var showingSettings = false
    @State private var apiKey: String = ""
    @State private var showingAPIKeyInput = false
    @State private var showingGuide = false
    
    // Environment values
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(UIColor.systemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEBULA")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white)
                    
                    Text("AI Wallpaper Generator")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Theme Selection
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Theme.presets) { theme in
                            ThemeCard(
                                theme: theme,
                                isSelected: selectedTheme.id == theme.id,
                                action: {
                                    withAnimation {
                                        selectedTheme = theme
                                        // Save selected theme to UserDefaults
                                        UserDefaults.standard.set(theme.name, forKey: "selectedTheme")
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                
                // Custom prompt field (if custom theme selected)
                if selectedTheme.name == "Custom" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR VISION")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                        
                        TextField("Describe your perfect wallpaper...", text: $customPrompt)
                            .padding()
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: selectedTheme.gradientColors),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                // Wallpaper preview
                ZStack {
                    if let image = wallpaperManager.currentImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 500)
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.5), radius: 20)
                            .padding(.vertical, 16)
                    } else {
                        // Placeholder
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: selectedTheme.gradientColors),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(0.3)
                            .frame(height: 400)
                            .overlay(
                                VStack(spacing: 12) {
                                    Image(systemName: selectedTheme.icon)
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Text("No wallpaper generated yet")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            )
                    }
                    
                    // Loading overlay
                    if wallpaperManager.isLoading {
                        ZStack {
                            Color.black.opacity(0.7)
                                .cornerRadius(20)
                            
                            VStack(spacing: 20) {
                                // Custom animated loader
                                ZStack {
                                    Circle()
                                        .stroke(lineWidth: 6)
                                        .opacity(0.3)
                                        .foregroundColor(Color.white)
                                    
                                    Circle()
                                        .trim(from: 0.0, to: CGFloat(min(wallpaperManager.generationProgress, 1.0)))
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: selectedTheme.gradientColors),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                        )
                                        .rotationEffect(Angle(degrees: 270.0))
                                        .animation(.linear, value: wallpaperManager.generationProgress)
                                }
                                .frame(width: 60, height: 60)
                                
                                Text(generationStatusText)
                                    .foregroundColor(.white)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                
                                if wallpaperManager.generationProgress > 0 {
                                    Text("\(Int(wallpaperManager.generationProgress * 100))%")
                                        .foregroundColor(.white)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                }
                            }
                        }
                        .frame(width: 180, height: 180)
                    }
                }
                .padding(.horizontal)
                
                // Last updated info and buttons
                VStack(spacing: 16) {
                    // Last updated timestamp
                    if let date = wallpaperManager.lastUpdated {
                        Text("Last generated: \(date, formatter: dateFormatter)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    // Error message
                    if let errorMessage = wallpaperManager.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Generate button
                    Button(action: {
                        hapticFeedback()
                        wallpaperManager.fetchNewWallpaper(
                            theme: selectedTheme,
                            customPrompt: selectedTheme.name == "Custom" ? customPrompt : nil
                        )
                    }) {
                        HStack {
                            Text("GENERATE")
                                .fontWeight(.bold)
                                .tracking(1)
                            
                            Image(systemName: "sparkles")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: selectedTheme.gradientColors),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(
                            color: (selectedTheme.gradientColors.first ?? Color.blue).opacity(0.5),
                            radius: 10,
                            y: 5
                        )
                    }
                    .disabled(wallpaperManager.isLoading)
                    .padding(.horizontal)
                    
                    // Action buttons row
                    HStack(spacing: 30) {
                        // Settings button
                        Button(action: {
                            hapticFeedback()
                            showingSettings = true
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "gear")
                                    .font(.system(size: 20))
                                
                                Text("Settings")
                                    .font(.caption)
                            }
                            .foregroundColor(.gray)
                        }
                        
                        // Apply button
                        Button(action: {
                            hapticFeedback()
                            showingGuide = true
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20))
                                
                                Text("Apply")
                                    .font(.caption)
                            }
                            .foregroundColor(.gray)
                        }
                        .disabled(wallpaperManager.currentImage == nil)
                        .opacity(wallpaperManager.currentImage == nil ? 0.5 : 1)
                        
                        // Info button
                        Button(action: {
                            hapticFeedback()
                            // Show info popup
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 20))
                                
                                Text("Info")
                                    .font(.caption)
                            }
                            .foregroundColor(.gray)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                wallpaperManager: wallpaperManager,
                apiKey: $apiKey,
                showingAPIKeyInput: $showingAPIKeyInput
            )
        }
        .alert("Enter DALL-E API Key", isPresented: $showingAPIKeyInput) {
            SecureField("API Key", text: $apiKey)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                wallpaperManager.setAPIKey(apiKey)
            }
        }
        .alert("How to Set as Wallpaper", isPresented: $showingGuide) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your wallpaper has been saved to Photos. Open the Photos app, select the image, tap the share button, then choose 'Use as Wallpaper'.")
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Check if API key is set on first launch
            if UserDefaults.standard.string(forKey: "apiKeySet") == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingAPIKeyInput = true
                    UserDefaults.standard.set(true, forKey: "apiKeySet")
                }
            }
            
            // Load saved theme if available
            if let savedThemeName = UserDefaults.standard.string(forKey: "selectedTheme"),
               let savedTheme = Theme.presets.first(where: { $0.name == savedThemeName }) {
                selectedTheme = savedTheme
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private var generationStatusText: String {
        let progress = wallpaperManager.generationProgress
        
        if progress < 0.3 {
            return "Initializing request..."
        } else if progress < 0.6 {
            return "Generating image..."
        } else if progress < 0.8 {
            return "Processing results..."
        } else if progress < 0.95 {
            return "Finalizing wallpaper..."
        } else {
            return "Completed!"
        }
    }
    
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - Theme Card Component
struct ThemeCard: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: theme.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : .gray)
                
                Text(theme.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .gray)
            }
            .frame(width: 90, height: 90)
            .background(
                isSelected ?
                LinearGradient(
                    gradient: Gradient(colors: theme.gradientColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) :
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.2)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                        Color.white.opacity(0.6) :
                        Color.gray.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    var wallpaperManager: WallpaperManager
    @Binding var apiKey: String
    @Binding var showingAPIKeyInput: Bool
    @State private var downloadLocation = "Photos Library"
    @State private var autoChangeWallpaper = true
    @State private var imageQuality = "High"
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("API Key")
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Button("Change") {
                                    showingAPIKeyInput = true
                                }
                                .foregroundColor(.blue)
                            }
                        } header: {
                            Text("API Configuration")
                                .foregroundColor(.gray)
                        }
                        .listRowBackground(Color.black.opacity(0.6))
                        
                        Section {
                            Toggle("Auto-Generate Daily", isOn: $autoChangeWallpaper)
                                .foregroundColor(.white)
                            
                            Picker("Image Quality", selection: $imageQuality) {
                                Text("Standard").tag("Standard")
                                Text("High").tag("High")
                            }
                            .foregroundColor(.white)
                            .pickerStyle(SegmentedPickerStyle())
                            
                            Picker("Save Location", selection: $downloadLocation) {
                                Text("Photos Library").tag("Photos Library")
                                Text("App Only").tag("App Only")
                            }
                            .foregroundColor(.white)
                            .pickerStyle(SegmentedPickerStyle())
                        } header: {
                            Text("Wallpaper Settings")
                                .foregroundColor(.gray)
                        }
                        .listRowBackground(Color.black.opacity(0.6))
                        
                        Section {
                            NavigationLink(destination:
                                Text("How to set your wallpaper")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black)
                            ) {
                                Text("How to set wallpaper")
                                    .foregroundColor(.white)
                            }
                            
                            NavigationLink(destination:
                                Text("About Nebula")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black)
                            ) {
                                Text("About")
                                    .foregroundColor(.white)
                            }
                        } header: {
                            Text("Help")
                                .foregroundColor(.gray)
                        }
                        .listRowBackground(Color.black.opacity(0.6))
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - KeychainSwift for API key security
class KeychainSwift {
    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // First attempt to delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Then add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Error saving to Keychain: \(status)")
        }
    }
    
    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data,
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        
        return nil
    }
    
    func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
}

// MARK: - App Entry Point
@main
struct AIWallpaperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
