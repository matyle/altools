import AppKit
import Vision

/// Region screenshots through the system `screencapture` tool (native selection UI,
/// window picking with Space), followed by annotation, pinning or OCR.
@MainActor
final class CaptureController {
  enum Then { case annotate, pin, ocr }

  private(set) var editors: [AnnotationWindowController] = []
  private var pins: [PinWindow] = []
  private var isCapturing = false

  func capture(then: Then) {
    guard !isCapturing else { return }
    isCapturing = true
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("altools-\(UUID().uuidString).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // -i interactive selection, -x no shutter sound, -o no window shadow when picking a window.
    process.arguments = ["-i", "-x", "-o", file.path]
    process.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async {
        self?.isCapturing = false
        // No file means the user pressed Esc.
        guard let image = NSImage(contentsOf: file) else { return }
        try? FileManager.default.removeItem(at: file)
        self?.handle(image, then: then)
      }
    }
    do {
      try process.run()
    } catch {
      isCapturing = false
      Toast.show("Could not start screencapture: \(error.localizedDescription)", symbol: "xmark.octagon.fill")
    }
  }

  private func handle(_ image: NSImage, then: Then) {
    switch then {
    case .annotate: openEditor(image)
    case .pin: pin(image)
    case .ocr:
      OCR.recognize(image) { text in
        guard let text, !text.isEmpty else {
          ActivityCenter.shared.report("No text found", symbol: "text.viewfinder")
          return
        }
        Pasteboard.copy(text)
        ActivityCenter.shared.report("Copied \(text.count) characters", symbol: "text.viewfinder", image: image)
      }
    }
  }

  func openEditor(_ image: NSImage) {
    let editor = AnnotationWindowController(image: image, capture: self)
    editor.onClose = { [weak self, weak editor] in self?.editors.removeAll { $0 === editor } }
    editors.append(editor)
    editor.show()
  }

  func pin(_ image: NSImage) {
    let pin = PinWindow(image: image)
    pin.onClose = { [weak self, weak pin] in self?.pins.removeAll { $0 === pin } }
    pins.append(pin)
    pin.orderFrontRegardless()
  }

  static func save(_ image: NSImage) {
    let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Altools", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let name = "Screenshot \(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "."))"
    let url = folder.appendingPathComponent(name).appendingPathExtension("png")
    guard let png = image.pngData() else { return }
    do {
      try png.write(to: url)
      ActivityCenter.shared.report("Saved to Pictures", symbol: "square.and.arrow.down.fill", image: image)
    } catch {
      Toast.show("Save failed: \(error.localizedDescription)", symbol: "xmark.octagon.fill")
    }
  }
}

enum OCR {
  /// Recognizes Chinese and English text. Calls back on the main thread with nil on failure.
  static func recognize(_ image: NSImage, completion: @escaping (String?) -> Void) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      completion(nil)
      return
    }
    let request = VNRecognizeTextRequest { request, _ in
      let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
      DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
      } catch {
        DispatchQueue.main.async { completion(nil) }
      }
    }
  }
}
