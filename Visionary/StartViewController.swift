import UIKit
import AVFoundation
import Contacts
import CoreMotion

class StarryBackgroundView: UIView {
    var stars: [CAShapeLayer] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        createStars()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func createStars() {
        let starCount = 100
        for _ in 0..<starCount {
            let star = CAShapeLayer()
            let starSize = CGFloat.random(in: 1...3)
            star.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: starSize, height: starSize)).cgPath
            star.fillColor = UIColor.white.cgColor
            star.position = CGPoint(x: CGFloat.random(in: 0...frame.width),
                                    y: CGFloat.random(in: 0...frame.height))
            layer.addSublayer(star)
            stars.append(star)
            
            animateStar(star)
        }
    }
    
    private func animateStar(_ star: CAShapeLayer) {
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.duration = Double.random(in: 1...3)
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 0.5
        scaleAnimation.autoreverses = true
        scaleAnimation.repeatCount = .infinity
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.duration = Double.random(in: 1...3)
        opacityAnimation.fromValue = 1.0
        opacityAnimation.toValue = 0.3
        opacityAnimation.autoreverses = true
        opacityAnimation.repeatCount = .infinity
        
        star.add(scaleAnimation, forKey: "starScale")
        star.add(opacityAnimation, forKey: "starOpacity")
    }
}

class StartViewController: UIViewController {

    @IBOutlet weak var StartButton: UIButton!
    
    let speechSynthesizer = AVSpeechSynthesizer()
    var shakeCount = 0
    let motionManager = CMMotionManager()
    var contactPhotos = [String: UIImage?]()
    var starryBackgroundView: StarryBackgroundView!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureStarryBackground()
        configureStartButton()
        configureShakeDetection()
        startFloatingAnimation()
        
        addTapGestureRecognizer()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        starryBackgroundView.frame = view.bounds
        StartButton.frame = CGRect(x: (view.bounds.width - 200) / 2, y: (view.bounds.height - 200) / 2, width: 200, height: 200)
    }

    private func configureStarryBackground() {
        starryBackgroundView = StarryBackgroundView(frame: view.bounds)
        view.insertSubview(starryBackgroundView, at: 0)
    }

    private func configureStartButton() {
        StartButton.removeConstraints(StartButton.constraints)

        StartButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            StartButton.widthAnchor.constraint(equalToConstant: 200),
            StartButton.heightAnchor.constraint(equalToConstant: 200),
            StartButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            StartButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        StartButton.setTitle("START", for: .normal)
        StartButton.titleLabel?.font = UIFont(name: "AvenirNext-Bold", size: 48) ?? UIFont.boldSystemFont(ofSize: 48)
        StartButton.backgroundColor = .systemGreen
        StartButton.setTitleColor(.white, for: .normal)
        StartButton.layer.cornerRadius = 100
        StartButton.clipsToBounds = true
        
        StartButton.layer.shadowColor = UIColor.black.cgColor
        StartButton.layer.shadowOffset = CGSize(width: 0, height: 5)
        StartButton.layer.shadowRadius = 10
        StartButton.layer.shadowOpacity = 0.3
        StartButton.layer.masksToBounds = false
    }

    @IBAction func StartButtonTapped(_ sender: Any) {
        startAction()
    }

    private func addTapGestureRecognizer() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleViewTap))
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleViewTap() {
        startAction()
    }

    private func startAction() {
        animateButtonTap {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            if let visionViewController = storyboard.instantiateViewController(withIdentifier: "VisionVC") as? VisionViewController {
                visionViewController.modalPresentationStyle = .fullScreen
                visionViewController.modalTransitionStyle = .crossDissolve
                self.present(visionViewController, animated: false, completion: {
                    self.speakText("Walking Stick Online")
                })
            }
        }
    }

    private func startFloatingAnimation() {
        let floatAnimation = CABasicAnimation(keyPath: "transform.translation.y")
        floatAnimation.duration = 1.0
        floatAnimation.fromValue = -15
        floatAnimation.toValue = 15
        floatAnimation.autoreverses = true
        floatAnimation.repeatCount = .infinity
        floatAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        StartButton.layer.add(floatAnimation, forKey: "floatAnimation")
        
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.duration = 1.5
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 1.1
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        StartButton.layer.add(pulseAnimation, forKey: "pulseAnimation")
    }

    private func animateButtonTap(completion: @escaping () -> Void) {
        let centerPoint = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let finalRadius = hypot(view.bounds.width, view.bounds.height) / 2

        let circleView = UIView()
        circleView.frame = CGRect(x: 0, y: 0, width: finalRadius * 2, height: finalRadius * 2)
        circleView.center = centerPoint
        circleView.backgroundColor = UIColor.white
        circleView.layer.cornerRadius = finalRadius
        circleView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        view.addSubview(circleView)

        UIView.animate(withDuration: 1.2, delay: 0, options: [.curveEaseInOut], animations: {
            circleView.transform = CGAffineTransform.identity
        }, completion: { _ in
            circleView.removeFromSuperview()
            completion()
        })
    }

    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)

        if let siriVoice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Siri_female_en-US_compact") {
            utterance.voice = siriVoice
        } else if let defaultVoice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Samantha-compact") {
            utterance.voice = defaultVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.1
        utterance.volume = 0.8
        utterance.preUtteranceDelay = 0.2

        speechSynthesizer.speak(utterance)
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

        do {
            try store.enumerateContacts(with: request) { (contact, stopPointer) in
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)

                if let imageData = contact.imageData, let image = UIImage(data: imageData) {
                    self.contactPhotos[fullName] = image
                } else {
                    self.contactPhotos[fullName] = nil
                }
            }
            print("Contacts synced: \(contactPhotos.count)")
            speakText("Contacts synced successfully")
        } catch {
            print("Failed to fetch contacts: \(error)")
            speakText("Failed to sync contacts")
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
