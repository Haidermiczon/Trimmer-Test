//
//  TrimmerViewController.swift
//  TrimmerTest
//
//  Created by Haider on 20/05/2025.
//

import UIKit
import AVFoundation
import PhotosUI
import MobileCoreServices


class TrimmerViewController: UIViewController,
                             UIImagePickerControllerDelegate, UINavigationControllerDelegate {
 
    @IBOutlet weak var playerView: UIView!
    @IBOutlet weak var trimmerView: TrimmerView!
    @IBOutlet weak var pickButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var exportButton: UIButton!
    @IBOutlet weak var selectedDurationLabel: UILabel!
    
    var player: AVPlayer?
    var playbackTimeCheckerTimer: Timer?
    var trimmerPositionChangedTimer: Timer?
    private let imagePicker = UIImagePickerController()
    var fetchResult: PHFetchResult<PHAsset>?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupImagePicker()
        loadLibrary()
        setupUI()
    }
    
    private func setupUI() {
        exportButton.isEnabled = false
        exportButton.setTitle("Export", for: .normal)
        exportButton.addTarget(self, action: #selector(exportButtonTapped), for: .touchUpInside)
    }
    
    private func setupImagePicker() {
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = [kUTTypeMovie as String]
        imagePicker.allowsEditing = false
        imagePicker.delegate = self
    }

    private func loadLibrary() {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if status == .authorized {
                    self.fetchResult = PHAsset.fetchAssets(with: .video, options: nil)
//                    self.showVideoPicker()
                } else {
                    self.showPermissionDeniedAlert()
                }
            }
        }
    }
    
    @IBAction func didTapPickButton(_ sender: Any) {
        self.showVideoPicker()
    }
    
    func showVideoPicker() {
        present(imagePicker, animated: true)
    }
   
    @IBAction func didTapPlayButton(_ sender: Any) {
        
    }
    
    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        guard let mediaType = info[.mediaType] as? String,
              mediaType == (kUTTypeMovie as String),
              let url = info[.mediaURL] as? URL else {
            return
        }
        
        let asset = AVURLAsset(url: url)
        self.trimmerView.asset = asset
        self.trimmerView.delegate = self
        self.addVideoPlayer(with: asset, playerView: self.playerView)
        self.exportButton.isEnabled = true
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        // Handle cancel action if needed
    }
    
    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "Photo Library Access Denied",
            message: "Please enable photo library access in Settings to select videos.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        })
        
        present(alert, animated: true)
    }
   
    
    private func addVideoPlayer(with asset: AVAsset, playerView: UIView) {
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)

        NotificationCenter.default.addObserver(self, selector: #selector(TrimmerViewController.itemDidFinishPlaying(_:)),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: playerItem)

        let layer: AVPlayerLayer = AVPlayerLayer(player: self.player)
        layer.backgroundColor = UIColor.white.cgColor
        layer.frame = CGRect(x: 0, y: 0, width: playerView.frame.width, height: playerView.frame.height)
        layer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        playerView.layer.sublayers?.forEach({$0.removeFromSuperlayer()})
        playerView.layer.addSublayer(layer)
    }
    
    @objc func itemDidFinishPlaying(_ notification: Notification) {
        if let startTime = trimmerView.startTime {
            player?.seek(to: startTime)
            if (player?.isPlaying != true) {
                player?.play()
            }
        }
    }
    
    func startPlaybackTimeChecker() {

        stopPlaybackTimeChecker()
        playbackTimeCheckerTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self,
                                                        selector:
            #selector(TrimmerViewController.onPlaybackTimeChecker), userInfo: nil, repeats: true)
    }

    func stopPlaybackTimeChecker() {

        playbackTimeCheckerTimer?.invalidate()
        playbackTimeCheckerTimer = nil
    }
    
    @objc func onPlaybackTimeChecker() {

        guard let startTime = trimmerView.startTime, let endTime = trimmerView.endTime, let player = player else {
            return
        }

        let playBackTime = player.currentTime()
        trimmerView.seek(to: playBackTime)

        if playBackTime >= endTime {
            player.seek(to: startTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
            trimmerView.seek(to: startTime)
        }
    }

    @objc private func exportButtonTapped() {
        guard let asset = trimmerView.asset as? AVURLAsset else {
            print("No video selected")
            return
        }
        
        let startTime = trimmerView.startTime ?? CMTime.zero
        let endTime = trimmerView.endTime ?? asset.duration
        
        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.center = view.center
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, 
                                                    presetName: AVAssetExportPresetHighestQuality) else {
            print("Cannot create export session")
            activityIndicator.removeFromSuperview()
            return
        }
        
        // Configure export session
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_video_\(Date().timeIntervalSince1970).mov")
        
        // Delete any existing file at the output URL
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)
        
        // Export the video
        exportSession.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                activityIndicator.removeFromSuperview()
                
                switch exportSession.status {
                case .completed:
                    print("Export completed successfully")
                    self?.saveVideoToLibrary(outputURL)
                case .failed:
                    print("Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                    self?.showAlert(title: "Export Failed", message: exportSession.error?.localizedDescription ?? "Unknown error occurred")
                case .cancelled:
                    print("Export was cancelled")
                default: 
                    break
                }
            }
        }
    }
    
    private func saveVideoToLibrary(_ videoURL: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.showAlert(title: "Success", message: "Video saved to photo library")
                } else if let error = error {
                    self?.showAlert(title: "Error", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension TrimmerViewController: TrimmerViewDelegate {
    func positionBarStoppedMoving(_ playerTime: CMTime) {
        player?.seek(to: playerTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        player?.play()
        startPlaybackTimeChecker()
    }

    func didChangePositionBar(_ playerTime: CMTime) {
        stopPlaybackTimeChecker()
        player?.pause()
        player?.seek(to: playerTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        let duration = (trimmerView.endTime! - trimmerView.startTime!).seconds
        print(duration)
    }
}
