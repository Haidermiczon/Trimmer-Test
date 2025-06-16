//
//  CutViewController.swift
//  TrimmerTest
//
//  Created by Haider on 13/06/2025.
//

import UIKit
import AVFoundation
import PhotosUI
import MobileCoreServices
import AVKit

class CutViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet weak var playerView: UIView!
    @IBOutlet weak var trimmerView: TrimmerView!
    @IBOutlet weak var pickButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var exportButton: UIButton!
    @IBOutlet weak var selectedDurationLabel: UILabel!
    
    private var debounceWorkItem: DispatchWorkItem?
    var player: AVPlayer?
    private var playerViewController: AVPlayerViewController?
    private let imagePicker = UIImagePickerController()
    var fetchResult: PHFetchResult<PHAsset>?
    var duration: Double = 0.0 {
        didSet {
            selectedDurationLabel.text = String(format: "Selected: %.1f", duration)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupImagePicker()
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
    
    @IBAction func didTapPickButton(_ sender: Any) {
        present(imagePicker, animated: true)
    }
    
    @IBAction func didTapPlayButton(_ sender: Any) {
        if player?.isPlaying == true {
            player?.pause()
            return
        }
        player?.play()
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
        self.trimmerView.maxDuration = asset.duration.seconds
//        self.trimmerView.maskingMode = .dimSelectedArea
        self.trimmerView.asset = asset
        self.trimmerView.delegate = self

        let start = trimmerView.startTime ?? .zero
        let end = trimmerView.endTime ?? asset.duration

        if let trimmedItem = createPreviewComposition(from: asset, startTime: start, endTime: end) {
            self.player = AVPlayer(playerItem: trimmedItem)

            // Reuse existing player view controller or create a new one
            if let playerVC = self.playerViewController {
                playerVC.player = self.player
            } else {
                let playerVC = AVPlayerViewController()
                playerVC.player = self.player
                playerVC.showsPlaybackControls = true
                self.addChild(playerVC)
                playerVC.view.frame = self.playerView.bounds
                self.playerView.addSubview(playerVC.view)
                playerVC.didMove(toParent: self)
                self.playerViewController = playerVC
            }

            self.player?.play()
        }

        self.exportButton.isEnabled = true
        self.duration = (trimmerView.endTime! - trimmerView.startTime!).seconds
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
    private func addVideoPlayer(with asset: AVAsset, playerView: UIView) {
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        
        // Remove old playerViewController if exists
        playerViewController?.view.removeFromSuperview()
        playerViewController?.removeFromParent()
        
        // Create new playerViewController
        let playerVC = AVPlayerViewController()
        playerVC.player = self.player
        playerVC.showsPlaybackControls = true
        
        // Add as child view controller
        self.addChild(playerVC)
        playerVC.view.frame = playerView.bounds
        playerView.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)
        
        self.playerViewController = playerVC
    }
    
    
    @objc private func exportButtonTapped() {
        guard let asset = trimmerView.asset as? AVURLAsset else {
            print("No video selected")
            return
        }
        let startTime = trimmerView.startTime ?? CMTime.zero
        let endTime = trimmerView.endTime ?? asset.duration
        let videoEnd = asset.duration
        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.center = view.center
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)
        // Create composition
        let composition = AVMutableComposition()
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            print("No video track found")
            activityIndicator.removeFromSuperview()
            return
        }
        let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        // Add [0, startTime]
        if startTime > .zero {
            try? compVideoTrack?.insertTimeRange(CMTimeRange(start: .zero, end: startTime), of: videoTrack, at: .zero)
        }
        // Add [endTime, videoEnd]
        if endTime < videoEnd {
            let atTime = (startTime > .zero) ? startTime : .zero
            try? compVideoTrack?.insertTimeRange(CMTimeRange(start: endTime, end: videoEnd), of: videoTrack, at: atTime)
        }
        // Add audio if present
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            if startTime > .zero {
                try? compAudioTrack?.insertTimeRange(CMTimeRange(start: .zero, end: startTime), of: audioTrack, at: .zero)
            }
            if endTime < videoEnd {
                let atTime = (startTime > .zero) ? startTime : .zero
                try? compAudioTrack?.insertTimeRange(CMTimeRange(start: endTime, end: videoEnd), of: audioTrack, at: atTime)
            }
        }
        // Export
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cut_video_\(Date().timeIntervalSince1970).mov")
        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            print("Cannot create export session")
            activityIndicator.removeFromSuperview()
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
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
    
    private func createPreviewComposition(from asset: AVAsset, startTime: CMTime, endTime: CMTime) -> AVPlayerItem? {
        let videoEnd = asset.duration
        let composition = AVMutableComposition()
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else { return nil }
        
        let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        // Add [0, startTime]
        if startTime > .zero {
            try? compVideoTrack?.insertTimeRange(CMTimeRange(start: .zero, end: startTime), of: videoTrack, at: .zero)
        }
        // Add [endTime, videoEnd]
        if endTime < videoEnd {
            let atTime = (startTime > .zero) ? startTime : .zero
            try? compVideoTrack?.insertTimeRange(CMTimeRange(start: endTime, end: videoEnd), of: videoTrack, at: atTime)
        }
        
        // Add audio if available
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            if startTime > .zero {
                try? compAudioTrack?.insertTimeRange(CMTimeRange(start: .zero, end: startTime), of: audioTrack, at: .zero)
            }
            if endTime < videoEnd {
                let atTime = (startTime > .zero) ? startTime : .zero
                try? compAudioTrack?.insertTimeRange(CMTimeRange(start: endTime, end: videoEnd), of: audioTrack, at: atTime)
            }
        }
        
        return AVPlayerItem(asset: composition)
    }
    
}

extension CutViewController: TrimmerViewDelegate {
    func positionBarStoppedMoving(_ playerTime: CMTime) {
        player?.seek(to: playerTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        player?.play()
    }
    
    func didChangePositionBar(_ playerTime: CMTime) {
        player?.pause()
        player?.seek(to: playerTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        
        // Cancel any pending work
           debounceWorkItem?.cancel()
           
           // Create new debounce task
           let workItem = DispatchWorkItem { [weak self] in
               guard let self = self else { return }
               let asset = self.trimmerView.asset!
               let start = self.trimmerView.startTime!
               let end = self.trimmerView.endTime!

               if let trimmedItem = self.createPreviewComposition(from: asset, startTime: start, endTime: end) {
                   self.player = AVPlayer(playerItem: trimmedItem)
                   self.playerViewController?.player = self.player
                   self.player?.play()
               }

               self.duration = (end - start).seconds
           }

           // Store and schedule the new task
           debounceWorkItem = workItem
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}
