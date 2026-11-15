//
//  HomeView.swift
//  GlutenDetector
//
//  Camera capture + photo library picking, image preview, graceful handling
//  of cancel/permission-denied, and an English / Arabic language switch.
//

import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

struct HomeView: View {
    // Current language (also pushed to all screens by GlutenDetectorApp).
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.english.rawValue
    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }

    // The captured/selected image, shown as a preview and passed to Result.
    @State private var selectedImage: UIImage?

    // Drives the camera sheet.
    @State private var showCamera = false

    // Drives navigation to Result once the user is happy with the photo.
    @State private var goToResult = false

    // PhotosPicker's selection (library).
    @State private var photosPickerItem: PhotosPickerItem?

    // Friendly permission-denied alert (never crash, always explain).
    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // App logo (add the image to Assets.xcassets with the name "AppLogo").
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .padding(.top, 24)

                    Text(lang.t(.appTitle))
                        .font(.largeTitle.bold())

                    Text(lang.t(.tagline))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Live preview of whatever was just captured/selected.
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .padding(.horizontal)
                    }

                    VStack(spacing: 12) {
                        Button {
                            handleTakePhotoTapped()
                        } label: {
                            Label(lang.t(.takePhoto), systemImage: "camera.fill")
                        }
                        .primaryButton()

                        PhotosPicker(selection: $photosPickerItem, matching: .images) {
                            Label(lang.t(.chooseLibrary), systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.gray)
                                .cornerRadius(12)
                        }

                        if selectedImage != nil {
                            Button {
                                goToResult = true
                            } label: {
                                Label(lang.t(.checkLabel), systemImage: "arrow.right.circle.fill")
                            }
                            .primaryButton(color: AppColor.safe)
                        }
                    }
                    .padding(.horizontal)

                    NavigationLink(destination: HistoryView()) {
                        Label(lang.t(.viewHistory), systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 24)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(lang.t(.home))
            // Language switch: always in the TOP-LEFT corner of the screen.
            // (In Arabic the layout is mirrored, so "trailing" is the left side.)
            .toolbar {
                ToolbarItem(placement: lang.isArabic ? .topBarTrailing : .topBarLeading) {
                    Button {
                        languageRaw = lang.toggled.rawValue
                    } label: {
                        Label(lang.switchButtonTitle, systemImage: "globe")
                    }
                }
            }
            .navigationDestination(isPresented: $goToResult) {
                ResultView(capturedImage: selectedImage)
            }
            // When the user comes back from Result ("Scan Again"), reset so a fresh
            // scan starts clean (and picking the same library photo again works).
            .onChange(of: goToResult) { _, isShowing in
                if !isShowing {
                    selectedImage = nil
                    photosPickerItem = nil
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $selectedImage)
                    .ignoresSafeArea()
            }
            // Load the picked PhotosPicker item into a UIImage.
            .onChange(of: photosPickerItem) { _, newItem in
                Task {
                    guard let newItem,
                          let data = try? await newItem.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data) else {
                        return
                    }
                    await MainActor.run {
                        selectedImage = uiImage
                    }
                }
            }
            .alert(lang.t(.cameraUnavailableTitle), isPresented: $showPermissionAlert) {
                Button(lang.t(.openSettings)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(lang.t(.cancel), role: .cancel) {}
            } message: {
                Text(permissionAlertMessage)
            }
        }
    }

    /// Checks camera availability + permission before presenting the
    /// camera sheet — never just crash or silently fail.
    private func handleTakePhotoTapped() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            permissionAlertMessage = lang.t(.noCameraMsg)
            showPermissionAlert = true
            return
        }

        // Without this Info.plist key iOS kills the app the moment the camera is
        // touched. Show a clear message instead of crashing.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            permissionAlertMessage = lang.t(.missingKeyMsg)
            showPermissionAlert = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        permissionAlertMessage = lang.t(.cameraDeniedMsg)
                        showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            permissionAlertMessage = lang.t(.cameraOffMsg)
            showPermissionAlert = true
        @unknown default:
            permissionAlertMessage = lang.t(.cameraUnavailableMsg)
            showPermissionAlert = true
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
