import UIKit
import AVFoundation
import Vision
import CoreML
import Accelerate

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, UITextFieldDelegate {
    
    // MARK: - Properties
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var detectionLayer: CALayer!
    var faceDetectionRequest: VNRequest!
    var eyeDetectionRequest: VNCoreMLRequest?
    var flashView: UIView!
    var captureButton: UIButton!
    var switchCameraButton: UIButton!
    var retakeButton: UIButton!
    var saveButton: UIButton!
    var capturedImageView: UIImageView!
    var whiteBoxView: UIView!
    var isFlashOn = false
    var photoOutput: AVCapturePhotoOutput!
    var capturedImage: UIImage?
    var currentCameraPosition: AVCaptureDevice.Position = .front
    var faceOverlayView: FaceOverlayView!
    var isCapturingImage = false
    var captureModeLabel: UILabel!
    var textField: UITextField!
    var radioButtonGroup: UISegmentedControl!
    var originalTextFieldFrame: CGRect!
    var recordedBoundingBoxes: [CGRect] = []
    var captureResult: String = ""
    
    let maxFrames = 100
    var frameCount = 0
    
    var consecutiveOneEyeFrames: Int = 0
    var oneEyeDetectionWindow: [Bool] = []
    let windowSize = 10
    
    // One-eye counters:
    // Mapping:
    // • If the detected eye is "left" then left is visible and right is closed → we increment oneEyeLeftCount and eventually report "RC" (right closed).
    // • If the detected eye is "right" then right is visible and left is closed → we increment oneEyeRightCount and eventually report "LC" (left closed).
    var oneEyeLeftCount: Int = 0   // corresponds to events where detected eye was "left" → result should be "RC"
    var oneEyeRightCount: Int = 0  // corresponds to events where detected eye was "right" → result should be "LC"
    
    // Added property to store the original screen brightness.
    var originalBrightness: CGFloat = UIScreen.main.brightness
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupCamera()
        setupLayers()
        setupModel()
        setupCaptureButton()
        setupSwitchCameraButton()
        setupCapturedImageView()
        setupRetakeButton()
        setupSaveButton()
        setupWhiteBoxView()
        setupFaceDetection()
        setupFaceOverlay()
        setupCaptureModeLabel()
        setupTextField()
        setupRadioButtons()
        
        bringButtonsToFront()
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Setup Methods
    private func bringButtonsToFront() {
        view.bringSubviewToFront(captureButton)
        view.bringSubviewToFront(switchCameraButton)
        view.bringSubviewToFront(retakeButton)
        view.bringSubviewToFront(saveButton)
        view.bringSubviewToFront(captureModeLabel)
        view.bringSubviewToFront(textField)
        view.bringSubviewToFront(radioButtonGroup)
    }
    
    private func setupFaceOverlay() {
        faceOverlayView = FaceOverlayView(frame: view.bounds)
        view.addSubview(faceOverlayView)
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        configureCamera(for: currentCameraPosition)
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        
        // Mirror the front camera video so LC and RC appear as expected.
        if let connection = previewLayer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (currentCameraPosition == .front)
        }
        
        view.layer.addSublayer(previewLayer)
        
        photoOutput = AVCapturePhotoOutput()
        captureSession.addOutput(photoOutput)
        
        captureSession.startRunning()
    }
    
    private func configureCamera(for position: AVCaptureDevice.Position) {
        captureSession.beginConfiguration()
        
        if let currentInput = captureSession.inputs.first {
            captureSession.removeInput(currentInput)
        }
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("\(position == .front ? "Front" : "Back") camera not available")
            captureSession.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            captureSession.addInput(input)
            
            if position == .back {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = 1.5
                camera.unlockForConfiguration()
            }
        } catch {
            print("Error setting up \(position == .front ? "front" : "back") camera input: \(error)")
            captureSession.commitConfiguration()
            return
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        if let existingOutput = captureSession.outputs.first(where: { $0 is AVCaptureVideoDataOutput }) {
            captureSession.removeOutput(existingOutput)
        }
        
        captureSession.addOutput(videoOutput)
        
        captureSession.commitConfiguration()
    }
    
    private func setupLayers() {
        detectionLayer = CALayer()
        detectionLayer.frame = view.layer.bounds
        view.layer.addSublayer(detectionLayer)
    }
    
    private func setupModel() {
        do {
            // Replace "bestNMS()" with your actual CoreML model loader if needed.
            let model = try VNCoreMLModel(for: bestNMS().model)
            eyeDetectionRequest = VNCoreMLRequest(model: model, completionHandler: handleDetections)
            eyeDetectionRequest?.imageCropAndScaleOption = .scaleFill
        } catch {
            print("Error loading model: \(error)")
        }
    }
    
    private func setupCaptureButton() {
        let buttonWidth: CGFloat = 70
        let buttonHeight: CGFloat = 70
        let xPosition = (view.bounds.width - buttonWidth) / 2
        let yPosition = view.bounds.height - buttonHeight - 50
        
        captureButton = UIButton(frame: CGRect(x: xPosition, y: yPosition, width: buttonWidth, height: buttonHeight))
        captureButton.backgroundColor = .gray
        captureButton.layer.cornerRadius = 35
        captureButton.layer.masksToBounds = true
        captureButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        captureButton.isEnabled = false
        view.addSubview(captureButton)
        
        flashView = UIView(frame: view.frame)
        flashView.backgroundColor = .white
        flashView.alpha = 0.0
        view.addSubview(flashView)
    }
    
    private func setupSwitchCameraButton() {
        switchCameraButton = UIButton(frame: CGRect(x: view.bounds.width - 110, y: 60, width: 100, height: 50))
        switchCameraButton.setTitle("Switch", for: .normal)
        switchCameraButton.backgroundColor = .gray
        switchCameraButton.layer.cornerRadius = 10
        switchCameraButton.layer.masksToBounds = true
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        view.addSubview(switchCameraButton)
    }
    
    private func setupCapturedImageView() {
        capturedImageView = UIImageView(frame: view.frame)
        capturedImageView.contentMode = .scaleAspectFit
        capturedImageView.isHidden = true
        view.addSubview(capturedImageView)
    }
    
    private func setupRetakeButton() {
        let buttonWidth: CGFloat = 100
        let buttonHeight: CGFloat = 50
        let xPosition = (view.bounds.width - buttonWidth) / 2
        let yPosition = view.bounds.height - buttonHeight - 50
        
        retakeButton = UIButton(frame: CGRect(x: xPosition, y: yPosition, width: buttonWidth, height: buttonHeight))
        retakeButton.setTitle("Retake", for: .normal)
        retakeButton.backgroundColor = .red
        retakeButton.layer.cornerRadius = 10
        retakeButton.layer.masksToBounds = true
        retakeButton.addTarget(self, action: #selector(retakePhoto), for: .touchUpInside)
        retakeButton.isHidden = true
        view.addSubview(retakeButton)
    }
    
    private func setupSaveButton() {
        saveButton = UIButton(frame: CGRect(x: view.bounds.width - 110, y: 60, width: 100, height: 50))
        saveButton.setTitle("Save", for: .normal)
        saveButton.layer.cornerRadius = 10
        saveButton.layer.masksToBounds = true
        saveButton.backgroundColor = .green
        saveButton.addTarget(self, action: #selector(savePhoto), for: .touchUpInside)
        saveButton.isHidden = true
        view.addSubview(saveButton)
    }
    
    private func setupWhiteBoxView() {
        let boxSize = CGSize(width: 250, height: 400)
        whiteBoxView = UIView()
        whiteBoxView.frame = CGRect(
            x: (view.bounds.width - boxSize.width) / 2,
            y: (view.bounds.height - boxSize.height) / 2,
            width: boxSize.width,
            height: boxSize.height
        )
        whiteBoxView.layer.borderColor = UIColor.white.cgColor
        whiteBoxView.layer.borderWidth = 2.0
        view.addSubview(whiteBoxView)
    }
    
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: handleDetections)
    }
    
    private func setupCaptureModeLabel() {
        captureModeLabel = UILabel(frame: CGRect(x: 20, y: 60, width: 100, height: 30))
        captureModeLabel.textColor = .white
        captureModeLabel.font = UIFont.boldSystemFont(ofSize: 16)
        captureModeLabel.text = "Capture: Off"
        view.addSubview(captureModeLabel)
    }
    
    private func setupTextField() {
        let textFieldWidth: CGFloat = view.bounds.width - 40
        let textFieldHeight: CGFloat = 40
        let xPosition: CGFloat = 20
        let yPosition: CGFloat = captureButton.frame.minY - textFieldHeight - 20
        
        textField = UITextField(frame: CGRect(x: xPosition, y: yPosition, width: textFieldWidth, height: textFieldHeight))
        textField.borderStyle = .roundedRect
        textField.placeholder = "Enter text here"
        textField.returnKeyType = .done
        textField.delegate = self
        originalTextFieldFrame = textField.frame
        view.addSubview(textField)
    }
    
    private func setupRadioButtons() {
        let radioButtonWidth: CGFloat = view.bounds.width - 40
        let radioButtonHeight: CGFloat = 40
        let xPosition: CGFloat = 20
        let yPosition: CGFloat = switchCameraButton.frame.maxY + 15
        
        // The three modes are independent:
        // "LC" means left closed (i.e. left eye is not visible → result "LC" if only right detections occur),
        // "RC" means right closed (i.e. right eye is not visible → result "RC" if only left detections occur),
        // "AC" means alternating (both eyes detected in one‑eye frames at least once).
        radioButtonGroup = UISegmentedControl(items: ["LC", "RC", "AC"])
        radioButtonGroup.frame = CGRect(x: xPosition, y: yPosition, width: radioButtonWidth, height: radioButtonHeight)
        radioButtonGroup.selectedSegmentIndex = 0
        view.addSubview(radioButtonGroup)
    }
    
    // MARK: - Keyboard Handling
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardHeight = keyboardFrame.cgRectValue.height
            textField.frame.origin.y = view.bounds.height - keyboardHeight - textField.frame.height - 20
        }
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        textField.frame = originalTextFieldFrame
    }
    
    // MARK: - Button Actions
    @objc private func toggleFlash() {
        isFlashOn.toggle()
        
        if currentCameraPosition == .front {
            // For the front camera, ensure the flash is as bright as possible regardless of the device’s current brightness.
            if isFlashOn {
                // Save the current brightness and set it to maximum.
                originalBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 1.0
                flashView.alpha = 1.0
            } else {
                // Restore the original brightness.
                UIScreen.main.brightness = originalBrightness
                flashView.alpha = 0.0
            }
        } else {
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            if backCamera.hasTorch {
                do {
                    try backCamera.lockForConfiguration()
                    backCamera.torchMode = isFlashOn ? .on : .off
                    if isFlashOn {
                        try backCamera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                    }
                    backCamera.unlockForConfiguration()
                } catch {
                    print("Torch could not be used: \(error)")
                }
            }
        }
        
        captureButton.backgroundColor = isFlashOn ? .yellow : .gray
        captureModeLabel.text = isFlashOn ? "Capture: On" : "Capture: Off"
        
        if !isFlashOn && currentCameraPosition == .back {
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            if backCamera.hasTorch {
                do {
                    try backCamera.lockForConfiguration()
                    backCamera.torchMode = .off
                    backCamera.unlockForConfiguration()
                } catch {
                    print("Torch could not be turned off: \(error)")
                }
            }
        }
    }
    
    @objc private func switchCamera() {
        currentCameraPosition = (currentCameraPosition == .front) ? .back : .front
        UIView.transition(with: view, duration: 0.3, options: .transitionFlipFromLeft, animations: {
            self.configureCamera(for: self.currentCameraPosition)
            if let connection = self.previewLayer.connection {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (self.currentCameraPosition == .front)
            }
        }, completion: nil)
    }
    
    @objc private func retakePhoto() {
        isFlashOn = false
        flashView.alpha = 0.0
        capturedImageView.isHidden = true
        retakeButton.isHidden = true
        saveButton.isHidden = true
        captureButton.isHidden = false
        switchCameraButton.isHidden = false
        detectionLayer.isHidden = false
        captureSession.startRunning()
        isCapturingImage = false
        captureButton.backgroundColor = .gray
        captureModeLabel.text = "Capture: Off"
        recordedBoundingBoxes.removeAll()
        frameCount = 0
        consecutiveOneEyeFrames = 0
        // Reset one‑eye counters when retaking
        oneEyeLeftCount = 0
        oneEyeRightCount = 0
        
        // For front camera mode, restore the original brightness.
        if currentCameraPosition == .front {
            UIScreen.main.brightness = originalBrightness
        }
    }
    
    @objc private func savePhoto() {
        guard let image = capturedImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
        isCapturingImage = false
    }
    
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        let alertController = UIAlertController(title: "Saved!", message: "Your photo has been saved to your photo library.", preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
    
    // MARK: - Alert for Mismatch
    private func showAlert(selected: String, result: String) {
        let alertController = UIAlertController(
            title: "Mismatch Detected",
            message: "You have selected: \(selected),\nBut the detection indicates: \(result)\nKindly recapture :)",
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
    
    // MARK: - Vision Handling
    private func handleDetections(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNObservation] else { return }
        
        DispatchQueue.main.async {
            self.detectionLayer.sublayers?.removeAll()
            
            let faceResults = results.compactMap { $0 as? VNFaceObservation }
            let eyeResults = results.compactMap { $0 as? VNRecognizedObjectObservation }
            
            // (Optional) Process face detections if needed.
            for face in faceResults {
                let _ = self.transformBoundingBox(face.boundingBox)
            }
            
            let confidentEyeResults = eyeResults.filter { $0.confidence > 0.6 }
            print("Confident eye results count: \(confidentEyeResults.count)")
            
            // If flash is on and both eyes are detected with proper spacing, trigger capture.
            if self.isFlashOn && self.areEyesProperlySpaced(confidentEyeResults) {
                if confidentEyeResults.count == 2 && !self.isCapturingImage {
                    self.isCapturingImage = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.captureImage()
                    }
                }
            }
            
            // When exactly one eye is detected, update our one‑eye counters.
            if confidentEyeResults.count == 1 {
                if let detection = confidentEyeResults.first {
                    let transformedRect = self.transformBoundingBox(detection.boundingBox)
                    let center = CGPoint(x: transformedRect.midX, y: transformedRect.midY)
                    let midX = self.view.bounds.midX
                    var detectedEye: String = ""
                    if self.currentCameraPosition == .back {
                        detectedEye = (center.x < midX) ? "right" : "left"
                    } else {
                        detectedEye = (center.x < midX) ? "left" : "right"
                    }
                    // IMPORTANT: Use the following mapping:
                    // If detected eye is "left" → left is visible, so right is closed → increment oneEyeRightCount (which later gives "RC")
                    // If detected eye is "right" → right is visible, so left is closed → increment oneEyeLeftCount (which later gives "LC")
                    if detectedEye == "left" {
                        self.oneEyeRightCount += 1
                    } else {
                        self.oneEyeLeftCount += 1
                    }
                }
                self.oneEyeDetectionWindow.append(true)
            } else {
                self.oneEyeDetectionWindow.append(false)
            }
            
            if self.oneEyeDetectionWindow.count > self.windowSize {
                self.oneEyeDetectionWindow.removeFirst()
            }
            
            let oneEyeDetectedInWindow = self.oneEyeDetectionWindow.filter { $0 }.count
            print("Consecutive frames with one eye detected: \(oneEyeDetectedInWindow)")
            
            self.captureButton.isEnabled = (oneEyeDetectedInWindow >= self.windowSize / 2)
            self.captureButton.backgroundColor = self.captureButton.isEnabled ? .white : .gray
            
            // Optionally draw bounding boxes.
            for observation in confidentEyeResults {
                let transformedRect = self.transformBoundingBox(observation.boundingBox)
                if self.isRectInsideWhiteBox(rect: transformedRect) {
                    self.drawBoundingBox(rect: transformedRect, color: UIColor.blue.cgColor, confidence: observation.confidence)
                    self.recordedBoundingBoxes.append(transformedRect)
                    if self.recordedBoundingBoxes.count > self.maxFrames {
                        self.recordedBoundingBoxes.removeFirst()
                    }
                }
            }
            
            // Update the capture result based solely on our one‑eye counters.
            self.updateCaptureResult()
        }
    }
    
    // MARK: - Capture Result Update (Independent Modes)
    private func updateCaptureResult() {
        var result = ""
        // Compute detection result based on our one‑eye counters.
        // If no one‑eye events have occurred, return "None".
        if oneEyeLeftCount == 0 && oneEyeRightCount == 0 {
            result = "None"
        }
        else if oneEyeLeftCount > 0 && oneEyeRightCount > 0 {
            // Use a ratio threshold to filter out noise.
            let minCount = min(oneEyeLeftCount, oneEyeRightCount)
            let maxCount = max(oneEyeLeftCount, oneEyeRightCount)
            let ratio = Double(minCount) / Double(maxCount)
            if ratio < 0.3 {
                // Dominated by one type:
                if oneEyeLeftCount > oneEyeRightCount {
                    // oneEyeLeftCount dominated → events where detected eye was "right" → result "LC"
                    result = "LC"
                } else {
                    // oneEyeRightCount dominated → result "RC"
                    result = "RC"
                }
            } else {
                result = "AC"
            }
        }
        else if oneEyeLeftCount > 0 {
            // Only events where detected eye was "right" occurred → result "LC"
            result = "LC"
        } else if oneEyeRightCount > 0 {
            // Only events where detected eye was "left" occurred → result "RC"
            result = "RC"
        }
        captureResult = result
        print("Updated capture result: \(captureResult)")
    }
    
    /// Convert a normalized Vision bounding box to view coordinates.
    private func transformBoundingBox(_ boundingBox: CGRect) -> CGRect {
        let width = boundingBox.width * view.bounds.width
        let height = boundingBox.height * view.bounds.height
        let x = boundingBox.origin.x * view.bounds.width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * view.bounds.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func drawBoundingBox(rect: CGRect, color: CGColor, confidence: VNConfidence? = nil) {
        let boxLayer = CAShapeLayer()
        boxLayer.frame = rect
        boxLayer.borderColor = color
        boxLayer.borderWidth = 2.0
        detectionLayer.addSublayer(boxLayer)
        
        if let confidence = confidence {
            let confidenceLabel = CATextLayer()
            confidenceLabel.string = String(format: "%.2f", confidence)
            confidenceLabel.fontSize = 14
            confidenceLabel.foregroundColor = UIColor.white.cgColor
            confidenceLabel.backgroundColor = UIColor.black.cgColor
            confidenceLabel.alignmentMode = .center
            confidenceLabel.frame = CGRect(x: rect.origin.x, y: rect.origin.y - 20, width: 50, height: 20)
            detectionLayer.addSublayer(confidenceLabel)
        }
    }
    
    private func captureImage() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        
        if let availablePreviewPixelFormatTypes = settings.availablePreviewPhotoPixelFormatTypes.first {
            settings.previewPhotoFormat = [
                kCVPixelBufferPixelFormatTypeKey as String: availablePreviewPixelFormatTypes
            ]
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        guard let eyeDetectionRequest = eyeDetectionRequest else {
            print("Error: eyeDetectionRequest is nil")
            return
        }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: currentCameraPosition == .front ? .leftMirrored : .right, options: [:])
        do {
            try requestHandler.perform([faceDetectionRequest, eyeDetectionRequest])
        } catch {
            print("Error performing request: \(error)")
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else { return }
        guard let image = UIImage(data: imageData) else { return }
        
        let overlayedImage = overlayTextAndRadioButton(on: image)
        
        capturedImageView.image = overlayedImage
        capturedImageView.isHidden = false
        retakeButton.isHidden = false
        saveButton.isHidden = false
        captureButton.isHidden = true
        switchCameraButton.isHidden = true
        detectionLayer.isHidden = true
        captureSession.stopRunning()
        
        capturedImage = overlayedImage
        isCapturingImage = false
        
        // Update result one last time before checking.
        updateCaptureResult()
        
        let selectedSegmentText = radioButtonGroup.titleForSegment(at: radioButtonGroup.selectedSegmentIndex) ?? ""
        if selectedSegmentText != self.captureResult {
            showAlert(selected: selectedSegmentText, result: self.captureResult)
        }
    }
    
    private func overlayTextAndRadioButton(on image: UIImage) -> UIImage {
        UIGraphicsBeginImageContext(image.size)
        image.draw(at: .zero)
        
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.white.cgColor)
        context?.setStrokeColor(UIColor.black.cgColor)
        context?.setLineWidth(2.0)
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 150),
            .foregroundColor: UIColor.red
        ]
        
        let text = textField.text ?? ""
        let selectedSegmentIndex = radioButtonGroup.selectedSegmentIndex
        let selectedSegmentText = radioButtonGroup.titleForSegment(at: selectedSegmentIndex) ?? ""
        
        let overlayText = "\(text) - \(selectedSegmentText)"
        let textRect = CGRect(x: 30, y: 30, width: image.size.width - 40, height: 200)
        overlayText.draw(in: textRect, withAttributes: textAttributes)
        
        let overlayedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return overlayedImage ?? image
    }
    
    private func areEyesProperlySpaced(_ eyeResults: [VNRecognizedObjectObservation]) -> Bool {
        guard eyeResults.count == 2 else { return false }
        
        let eye1 = eyeResults[0]
        let eye2 = eyeResults[1]
        
        let center1 = CGPoint(x: eye1.boundingBox.midX, y: eye1.boundingBox.midY)
        let center2 = CGPoint(x: eye2.boundingBox.midX, y: eye2.boundingBox.midY)
        
        let dx = center1.x - center2.x
        let dy = center1.y - center2.y
        let distance = sqrt(dx * dx + dy * dy)
        
        let minDistance: CGFloat = 0.1
        let maxDistance: CGFloat = 0.3
        
        return distance >= minDistance && distance <= maxDistance
    }
    
    private func isRectInsideWhiteBox(rect: CGRect) -> Bool {
        return whiteBoxView.frame.contains(rect)
    }
}

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        return sqrt(pow(x - point.x, 2) + pow(y - point.y, 2))
    }
}
