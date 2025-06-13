//
//  CutViewController.swift
//  TrimmerTest
//
//  Created by Haider on 13/06/2025.
//

import UIKit

class CutViewController: UIViewController {

    @IBOutlet weak var playerView: UIView!
    @IBOutlet weak var trimmerView: TrimmerView!
    @IBOutlet weak var pickButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var exportButton: UIButton!
    @IBOutlet weak var selectedDurationLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}
