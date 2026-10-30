import SwiftUI
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation
import UIKit

@main
struct TendiesStudioApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var videoName = "No video selected"
    @State private var wallpaperName = "MyWallpaper"
    @State private var fps = 30.0
    @State private var width = 1290
    @State private var height = 2796
    @State private var scale = 3
    @State private var identifier = 9136
    @State private var reverseOnLoop = false
    @State private var jpegQuality = 0.72
    @State private var importing = false
    @State private var converting = false
    @State private var status = "Choose a MOV or MP4 video"
    @State private var progress = 0.0
    @State private var outputURL: URL?
    @State private var sharing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Video") {
                    Button { importing = true } label: {
                        Label(videoName, systemImage: "video.badge.plus")
                    }
                    Text("Import a video from Files. Short clips are recommended.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Wallpaper") {
                    TextField("Wallpaper name", text: $wallpaperName)
                    Picker("Resolution", selection: Binding(
                        get: { "\(width)x\(height)" },
                        set: { value in
                            let parts = value.split(separator: "x").compactMap { Int($0) }
                            if parts.count == 2 { width = parts[0]; height = parts[1] }
                        })) {
                        Text("iPhone 17 Pro Max · 1320 × 2868").tag("1320x2868")
                        Text("iPhone 16 Pro Max · 1320 × 2868").tag("1320x2868")
                        Text("iPhone 16 Pro · 1206 × 2622").tag("1206x2622")
                        Text("iPhone 15 Pro Max · 1290 × 2796").tag("1290x2796")
                        Text("iPhone 15 Pro · 1179 × 2556").tag("1179x2556")
                    }
                    Stepper("Frame rate: \(Int(fps)) FPS", value: $fps, in: 1...60, step: 1)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("JPEG compression")
                            Spacer()
                            Text("\(Int(jpegQuality * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $jpegQuality, in: 0.50...0.90, step: 0.05)
                        Text("Lower quality makes smaller files. 70–75% is a balanced starting point.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Stepper("Scale: @\(scale)x", value: $scale, in: 1...3)
                    Stepper("Identifier: \(identifier)", value: $identifier, in: 1...99999)
                    Toggle("Reverse video on loop", isOn: $reverseOnLoop)
                    Text("Videos are limited to 300 frames at the selected frame rate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Export") {
                    if converting { ProgressView(value: progress) }
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task { await convert() }
                    } label: {
                        HStack {
                            Spacer()
                            if converting { ProgressView().padding(.trailing, 6) }
                            Text(converting ? "Converting…" : "Create .tendies")
                            Spacer()
                        }
                    }
                    .disabled(videoURL == nil || converting || wallpaperName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if outputURL != nil {
                        Button { sharing = true } label: {
                            Label("Share Tendies file", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Tendies Studio")
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
                do {
                    let picked = try result.get()
                    let access = picked.startAccessingSecurityScopedResource()
                    defer { if access { picked.stopAccessingSecurityScopedResource() } }
                    let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + picked.lastPathComponent)
                    try FileManager.default.copyItem(at: picked, to: local)
                    videoURL = local
                    videoName = picked.lastPathComponent
                    outputURL = nil
                    status = "Ready to convert"
                } catch { errorMessage(error) }
            }
            .sheet(isPresented: $sharing) {
                if let outputURL { ShareSheet(items: [outputURL]) }
            }
            .alert("Export failed", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
    }

    @MainActor
    private func convert() async {
        guard let videoURL else { return }
        converting = true
        progress = 0
        status = "Preparing frames…"
        let name = wallpaperName.replacingOccurrences(of: "/", with: "-")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".tendies")
        do {
            try? FileManager.default.removeItem(at: destination)
            let w = width, h = height, s = scale, f = fps, id = identifier, reverse = reverseOnLoop, quality = jpegQuality
            try await Task.detached(priority: .userInitiated) {
                try TendiesExporter.export(videoURL: videoURL, outputURL: destination,
                                           wallpaperName: name, width: w, height: h,
                                           scale: s, fps: f, identifier: id, reverseOnLoop: reverse,
                                           jpegQuality: quality)
            }.value
            outputURL = destination
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let megabytes = Double(bytes) / 1_048_576.0
            status = String(format: "Created %@ · %.1f MB", destination.lastPathComponent, megabytes)
            progress = 1
        } catch {
            self.error = error.localizedDescription
            status = "Conversion failed"
        }
        converting = false
    }

    private func errorMessage(_ error: Error) { self.error = error.localizedDescription }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum TendiesExporter {
    static func export(videoURL: URL, outputURL: URL, wallpaperName: String,
                       width: Int, height: Int, scale: Int, fps: Double, identifier: Int,
                       reverseOnLoop: Bool, jpegQuality: Double) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("tendies-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let asset = AVURLAsset(url: videoURL)
        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else { throw ExportError.invalidVideo }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width * 2, height: height * 2)

        let descriptors = temp.appendingPathComponent("descriptors", isDirectory: true)
        let uuid = UUID().uuidString.uppercased()
        let providerUUID = UUID().uuidString.uppercased()
        let root = descriptors.appendingPathComponent(uuid, isDirectory: true)
        let versions = root.appendingPathComponent("versions/1/contents", isDirectory: true)
        let resolution = "\(width)w-\(height)h@\(scale)x~iphone"
        let wallpaperFolder = "\(wallpaperName)-\(resolution).wallpaper"
        let bgName = "\(wallpaperName)_Background-\(resolution).ca"
        let floatName = "\(wallpaperName)_Floating-\(resolution).ca"
        let wallpaper = versions.appendingPathComponent(wallpaperFolder, isDirectory: true)
        let bg = wallpaper.appendingPathComponent(bgName, isDirectory: true)
        let floating = wallpaper.appendingPathComponent(floatName, isDirectory: true)
        let assets = bg.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        try fm.createDirectory(at: floating, withIntermediateDirectories: true)

        let step = 1.0 / max(1.0, fps)
        let count = max(1, Int(ceil(duration * fps)))
        guard count <= 300 else { throw ExportError.tooManyFrames }
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var written = 0
        for index in 0..<count {
            let seconds = min(Double(index) * step, max(0, duration - 0.001))
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let cg = try generator.copyCGImage(at: time, actualTime: nil)
            let ci = CIImage(cgImage: cg)
            let target = CGRect(x: 0, y: 0, width: width, height: height)
            let sx = CGFloat(width) / ci.extent.width
            let sy = CGFloat(height) / ci.extent.height
            let factor = max(sx, sy)
            let scaled = ci.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            let crop = scaled.cropped(to: CGRect(x: scaled.extent.midX - CGFloat(width)/2,
                                                 y: scaled.extent.midY - CGFloat(height)/2,
                                                 width: CGFloat(width), height: CGFloat(height)))
            guard let image = context.createCGImage(crop, from: target, format: .RGBA8, colorSpace: colorSpace) else {
                throw ExportError.frameFailed
            }
            let url = assets.appendingPathComponent(String(format: "%05d.jpg", index))
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw ExportError.frameFailed
            }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw ExportError.frameFailed }
            written += 1
        }
        guard written > 0 else { throw ExportError.noFrames }

        // Keep one copy of each source frame. PosterBoard's CAKeyframeAnimation
        // performs the reverse leg with autoreverses, rather than duplicating JPEG assets.
        let frameValues = (0..<written).map { index in
            "            <CGImage src=\"assets/\(String(format: "%05d", index)).jpg\"/>"
        }.joined(separator: "\n")
        let autoReverses = reverseOnLoop ? "1" : "0"
        let clipDuration = Double(written) / max(1.0, fps)
        let caml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
          <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" hidden="0" name="_FLOATING" position="\(width / 2) \(height / 2)">
            <sublayers>
              <CATransformLayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" allowsHitTesting="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="Chip" position="\(width / 2) \(height / 2)">
                <sublayers>
                  <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="CALayer1" position="\(width / 2) \(height / 2)">
                    <contents type="CGImage" src="assets/00000.jpg"/>
                    <animations>
                      <animation type="CAKeyframeAnimation" calculationMode="linear" keyPath="contents" beginTime="1e-100" duration="\(clipDuration)" removedOnCompletion="0" repeatCount="inf" repeatDuration="0" speed="1" timeOffset="0" autoreverses="\(autoReverses)">
                        <values>
        \(frameValues)
                        </values>
                      </animation>
                    </animations>
                  </CALayer>
                </sublayers>
              </CATransformLayer>
            </sublayers>
            <states>
              <LKState name="Locked"><elements/></LKState>
              <LKState name="Unlock"><elements/></LKState>
              <LKState name="Sleep"><elements/></LKState>
            </states>
            <stateTransitions>
              <LKStateTransition fromState="*" toState="Unlock"><elements/></LKStateTransition>
              <LKStateTransition fromState="Unlock" toState="*"><elements/></LKStateTransition>
              <LKStateTransition fromState="*" toState="Locked"><elements/></LKStateTransition>
              <LKStateTransition fromState="Locked" toState="*"><elements/></LKStateTransition>
              <LKStateTransition fromState="*" toState="Sleep"><elements/></LKStateTransition>
              <LKStateTransition fromState="Sleep" toState="*"><elements/></LKStateTransition>
            </stateTransitions>
          </CALayer>
        </caml>
        """
        try caml.write(to: bg.appendingPathComponent("main.caml"), atomically: true, encoding: .utf8)
        let empty = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>view</key><dict><key>backgroundColor</key><string>0 0 0 0</string>
        <key>drawsAsynchronously</key><false/><key>sublayers</key><array/></dict></dict></plist>
        """
        try empty.write(to: floating.appendingPathComponent("main.caml"), atomically: true, encoding: .utf8)
        let index = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>assetManifest</key><string>assetManifest.caml</string>
          <key>documentHeight</key><real>\(height)</real>
          <key>documentResizesToView</key><true/>
          <key>documentWidth</key><real>\(width)</real>
          <key>dynamicGuidesEnabled</key><true/>
          <key>geometryFlipped</key><false/>
          <key>guidesEnabled</key><true/>
          <key>interactiveMouseEventsEnabled</key><true/>
          <key>interactiveShowsCursor</key><true/>
          <key>interactiveTouchEventsEnabled</key><false/>
          <key>loopEnd</key><real>0.0</real>
          <key>loopStart</key><real>0.0</real>
          <key>loopingEnabled</key><false/>
          <key>multitouchDisablesMouse</key><false/>
          <key>multitouchEnabled</key><false/>
          <key>presentationMouseEventsEnabled</key><true/>
          <key>presentationShowsCursor</key><true/>
          <key>presentationTouchEventsEnabled</key><false/>
          <key>rootDocument</key><string>main.caml</string>
          <key>savesWindowFrame</key><false/>
          <key>scalesToFitInPlayer</key><true/>
          <key>showsTouches</key><true/>
          <key>snappingEnabled</key><true/>
          <key>timelineMarkers</key><string>[(null)]</string>
          <key>touchesColor</key><string>1 1 0 0.8</string>
          <key>unitsInPixelsInPlayer</key><true/>
        </dict>
        </plist>
        """
        let manifest = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict/></plist>"
        for dir in [bg, floating] {
            try index.write(to: dir.appendingPathComponent("index.xml"), atomically: true, encoding: .utf8)
            try manifest.write(to: dir.appendingPathComponent("assetManifest.caml"), atomically: true, encoding: .utf8)
        }
        let wallpaperInfo: [String: Any] = [
            "appearanceAware": 1,
            "assets": ["lockAndHome": ["default": [
                "backgroundAnimationFileName": bgName,
                "floatingAnimationFileNameKey": floatName,
                "identifier": identifier, "name": wallpaperName, "type": "LayeredAnimation"
            ]]],
            "contentVersion": 2.01, "family": wallpaperName, "identifier": identifier,
            "logicalScreenClass": resolution, "name": wallpaperName, "version": 1
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: wallpaperInfo, format: .xml, options: 0)
        try plist.write(to: wallpaper.appendingPathComponent("Wallpaper.plist"))
        let providerInfo = try PropertyListSerialization.data(fromPropertyList: ["kConfigurationLastUseDateKey": Date()], format: .xml, options: 0)
        try providerInfo.write(to: root.appendingPathComponent("providerInfo.plist"))
        try "PRPosterRoleLockScreen".write(to: root.appendingPathComponent("com.apple.posterkit.role.identifier"), atomically: true, encoding: .utf8)
        try providerUUID.write(to: root.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"), atomically: true, encoding: .utf8)
        let userInfo: [String: Any] = [
            "posterEnvironmentOverrides": Data("e30=".utf8),
            "wallpaperRepresentingFileName": wallpaperFolder,
            "wallpaperRepresentingIdentifier": String(identifier)
        ]
        let userInfoData = try PropertyListSerialization.data(fromPropertyList: userInfo, format: .xml, options: 0)
        try userInfoData.write(to: root.appendingPathComponent("com.apple.posterkit.provider.contents.userInfo"))
        let archive = try Archive(url: outputURL, accessMode: .create)
        guard let enumerator = fm.enumerator(at: descriptors, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw ExportError.archiveFailed
        }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = String(file.path.dropFirst(temp.path.count + 1))
            try archive.addEntry(with: relative, fileURL: file, compressionMethod: .deflate)
        }
    }

    enum ExportError: LocalizedError {
        case invalidVideo, frameFailed, noFrames, archiveFailed, tooManyFrames
        var errorDescription: String? {
            switch self {
            case .invalidVideo: return "The selected video is invalid."
            case .frameFailed: return "A video frame could not be encoded."
            case .noFrames: return "No frames were created."
            case .archiveFailed: return "The Tendies archive could not be packaged."
            case .tooManyFrames: return "This video exceeds the 300-frame limit at the selected FPS. Lower the FPS or choose a shorter clip."
            }
        }
    }
}
