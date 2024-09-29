import UIKit
import AVFoundation
import Vision
import CoreML
import Contacts
import CoreMotion

class VisionViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var cameraView: UIView!

    var captureSession: AVCaptureSession!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    var yoloModel: VNCoreMLModel?
    var ultraWideCamera: AVCaptureDevice?
    let speechSynthesizer = AVSpeechSynthesizer()

    var shakeCount = 0
    let motionManager = CMMotionManager()
    var contactPhotos = [String: UIImage]()

    let processingQueue = DispatchQueue(label: "com.app.processingQueue", attributes: .concurrent)

    var detectedObjects: [String: VNRecognizedObjectObservation] = [:]
    let persistenceThreshold = 4
    var objectPersistenceCounts: [String: Int] = [:]

    let FOCAL_LENGTH: CGFloat = 1400
    let AVERAGE_OBJECT_HEIGHT: CGFloat = 0.3

    var lastAnnouncedText: String?
    var lastAnnouncementTime: TimeInterval = 0
    let textAnnouncementCooldown: TimeInterval = 5.0
    var stableTextObservation: (text: String, count: Int)?
    let stableTextThreshold = 3
    var lastTextDetectionTime: TimeInterval = 0
    let textDetectionInterval: TimeInterval = 0.5
    
    var isProcessingFrame = false

    var lastAnnouncedObject: String?
    var lastAnnouncedConfidence: Float = 0.0

    var longPressGesture: UILongPressGestureRecognizer!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        loadYOLOModel()
        configureShakeDetection()
        configureLongPressGesture()
    }

    private func configureLongPressGesture() {
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 3.0 // 3 seconds
        view.addGestureRecognizer(longPressGesture)
    }

    @objc private func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began {
            // Long press detected, return to root view controller
            returnToRootViewController()
        }
    }

    private func returnToRootViewController() {
        DispatchQueue.main.async {
            self.captureSession.stopRunning()

            if let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate,
               let window = sceneDelegate.window {
                UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: {
                    window.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController()
                }, completion: nil)
            }
        }
    }
    

    private func loadYOLOModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let yoloV8x = try yolov8x(configuration: config)
            yoloModel = try VNCoreMLModel(for: yoloV8x.model)
            print("YOLOv8x model loaded successfully.")
        } catch {
            print("Error loading YOLOv8x model: \(error)")
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .hd1280x720

        guard let ultraWideDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Wide-angle camera is not available.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: ultraWideDevice)
            captureSession.addInput(input)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]

            captureSession.addOutput(videoOutput)

            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer.videoGravity = .resizeAspectFill
            videoPreviewLayer.frame = cameraView.bounds

            cameraView.layer.addSublayer(videoPreviewLayer)

            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.captureSession.startRunning()
                print("Camera session started.")
            }
        } catch {
            print("Error setting up camera: \(error)")
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessingFrame = false
            return
        }

        let currentTime = CACurrentMediaTime()

        if currentTime - lastTextDetectionTime >= textDetectionInterval {
            lastTextDetectionTime = currentTime
            detectText(in: pixelBuffer, at: currentTime)
        }

        detectObjects(pixelBuffer: pixelBuffer) {
            self.isProcessingFrame = false
        }
    }

    private func detectText(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                DispatchQueue.main.async {
                    self?.handleNoTextDetected()
                }
                return
            }

            DispatchQueue.main.async {
                self?.processTextObservations(observations, at: time)
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform text detection: \(error)")
        }
    }

    private func processTextObservations(_ observations: [VNRecognizedTextObservation], at time: TimeInterval) {
        let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")

        if let (stableText, count) = stableTextObservation {
            if areStringsSimilar(stableText, recognizedText) {
                stableTextObservation = (stableText, count + 1)
                if count + 1 >= stableTextThreshold {
                    announceStableText(stableText, at: time)
                }
            } else {
                stableTextObservation = (recognizedText, 1)
            }
        } else {
            stableTextObservation = (recognizedText, 1)
        }
    }

    private func announceStableText(_ text: String, at time: TimeInterval) {
        if shouldAnnounceText(text, at: time) {
            print("Detected stable text: \(text)")
            cancelCurrentSpeech()
            speakText("Detected text: \(text)")
            lastAnnouncedText = text
            lastAnnouncementTime = time
        }
    }

    private func shouldAnnounceText(_ text: String, at time: TimeInterval) -> Bool {
        guard time - lastAnnouncementTime >= textAnnouncementCooldown else {
            return false
        }

        if let lastAnnounced = lastAnnouncedText {
            return !areStringsSimilar(lastAnnounced, text)
        }

        return true
    }

    private func areStringsSimilar(_ text1: String, _ text2: String) -> Bool {
        let distance = levenshteinDistance(text1, text2)
        let maxLength = max(text1.count, text2.count)
        let similarityThreshold = 0.8
        return Double(maxLength - distance) / Double(maxLength) >= similarityThreshold
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let m = s1.count
        let n = s2.count
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m {
            matrix[i][0] = i
        }
        for j in 0...n {
            matrix[0][j] = j
        }

        for i in 1...m {
            for j in 1...n {
                if s1[s1.index(s1.startIndex, offsetBy: i - 1)] == s2[s2.index(s2.startIndex, offsetBy: j - 1)] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + 1)
                }
            }
        }

        return matrix[m][n]
    }

    private func handleNoTextDetected() {
        stableTextObservation = nil
        print("No text detected")
    }

    private func detectObjects(pixelBuffer: CVPixelBuffer, completion: @escaping () -> Void) {
        guard let yoloModel = yoloModel else {
            print("YOLOv8x model is not loaded.")
            completion()
            return
        }

        let request = VNCoreMLRequest(model: yoloModel) { [weak self] request, error in
            if let error = error {
                print("Error during YOLO inference: \(error)")
                completion()
                return
            }

            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion()
                return
            }

            DispatchQueue.main.async {
                self?.processYOLOResults(results)
                completion()
            }
        }

        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform YOLO detection: \(error)")
            completion()
        }
    }

    private func processYOLOResults(_ results: [VNRecognizedObjectObservation]) {
        var currentDetectedObjects: [String: VNRecognizedObjectObservation] = [:]
        var highestConfidenceObject: (label: String, confidence: Float, distance: Int)? = nil

        for observation in results {
            guard observation.confidence > 0.5 else { continue }
            guard let label = observation.labels.first?.identifier else { continue }

            currentDetectedObjects[label] = observation

            let distance = calculateDistance(for: observation.boundingBox)

            let roundedDistance = Int(round(distance))

            if highestConfidenceObject == nil || observation.confidence > highestConfidenceObject!.confidence {
                highestConfidenceObject = (label, observation.confidence, roundedDistance)
            }
        }

        updateObjectDetectionUI(currentDetectedObjects)

        if let highestObject = highestConfidenceObject, highestObject.label != lastAnnouncedObject || highestObject.confidence > lastAnnouncedConfidence {
            print("Highest confidence object: \(highestObject.label) with confidence \(highestObject.confidence) and distance \(highestObject.distance)m")
            lastAnnouncedObject = highestObject.label
            lastAnnouncedConfidence = highestObject.confidence
            cancelCurrentSpeech()
            speakText("\(highestObject.label) at \(highestObject.distance) meters")
        }
    }

    private func updateObjectDetectionUI(_ currentDetectedObjects: [String: VNRecognizedObjectObservation]) {
        videoPreviewLayer.sublayers?.removeAll(where: { $0 is CAShapeLayer || $0 is CATextLayer })
        let removedObjects = Set(detectedObjects.keys).subtracting(currentDetectedObjects.keys)
        for removedObject in removedObjects {
            detectedObjects.removeValue(forKey: removedObject)
            objectPersistenceCounts.removeValue(forKey: removedObject)
        }

        detectedObjects = currentDetectedObjects
    }


    private func calculateDistance(for boundingBox: CGRect) -> CGFloat {
        let objectHeightInPixels = boundingBox.height * CGFloat(videoPreviewLayer.bounds.height)
        return (FOCAL_LENGTH * AVERAGE_OBJECT_HEIGHT) / objectHeightInPixels
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoPreviewLayer?.frame = cameraView.bounds
    }

    private func configureShakeDetection() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.2
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
                guard let motion = motion else { return }
                if self?.isDeviceShaking(motion) == true {
                    self?.handleDeviceShake()
                }
            }
        }
    }

    private func isDeviceShaking(_ motion: CMDeviceMotion) -> Bool {
        let userAcceleration = motion.userAcceleration
        let threshold: Double = 2.5
        return abs(userAcceleration.x) > threshold ||
               abs(userAcceleration.y) > threshold ||
               abs(userAcceleration.z) > threshold
    }

    private func handleDeviceShake() {
        shakeCount += 1
        if shakeCount == 3 {
            syncContacts()
            shakeCount = 0
        }
    }

    private func syncContacts() {
        let store = CNContactStore()
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactImageDataKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)

        var newContactPhotos = [String: UIImage]()

        do {
            try store.enumerateContacts(with: request) { (contact, stopPointer) in
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                if let imageData = contact.imageData, let image = UIImage(data: imageData) {
                    newContactPhotos[fullName] = image
                }
            }

            self.contactPhotos = newContactPhotos
            print("Contacts synced: \(contactPhotos.count)")
            speakText("Contacts synced successfully")
            showAlert(title: "Success", message: "Contacts synced successfully!")
        } catch {
            print("Failed to fetch contacts: \(error)")
            speakText("Failed to sync contacts")
            showAlert(title: "Error", message: "Failed to sync contacts: \(error.localizedDescription)")
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }

    private func cancelCurrentSpeech() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.1
        utterance.volume = 0.8
        speechSynthesizer.speak(utterance)
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
