//
//  NCViewerImagemeter.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 22/03/2019.
//  Copyright © 2019 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

class NCViewerImagemeter: NSObject {
    
    private var imagemeterView: IMImagemeterView!
    
    private let appDelegate = UIApplication.shared.delegate as! AppDelegate

    private var nameArchiveImagemeter: String = ""
    private var pathArchiveImagemeter: String = ""
    
    private var annotation: IMImagemeterCodable.imagemeterAnnotation?
    
    private var audioPlayer = AVAudioPlayer()
    private var timer = Timer()
    
    private var durationPlayer: TimeInterval = 0
    private var counterSecondPlayer: TimeInterval = 0

    private var metadata: tableMetadata!
    private var detail: CCDetail!

    private var safeAreaBottom: Int = 0
    
    @objc public init(metadata: tableMetadata, detail: CCDetail) {
        super.init()
        
        self.metadata = metadata
        self.detail = detail
        
        guard let rootView = UIApplication.shared.keyWindow else {
            return
        }
        if #available(iOS 11.0, *) {
            safeAreaBottom = Int(rootView.safeAreaInsets.bottom)
        }
        
        nameArchiveImagemeter = (metadata.fileNameView as NSString).deletingPathExtension
        pathArchiveImagemeter = CCUtility.getDirectoryProviderStorageFileID(metadata.fileID) + "/" + nameArchiveImagemeter
        
        self.imagemeterView = IMImagemeterView.instanceFromNib() as? IMImagemeterView
        self.imagemeterView.frame = CGRect(x: 0, y: 0, width: Int(detail.view.frame.width), height: Int(detail.view.frame.height) - Int(k_detail_Toolbar_Height) - safeAreaBottom - 1)
        
        detail.view.addSubview(imagemeterView)
        
        do {
            
            let annoPath = (pathArchiveImagemeter + "/anno-" + nameArchiveImagemeter + ".imm").url
            let annoData = try Data(contentsOf: annoPath, options: .mappedIfSafe)
            if let annotation = IMImagemeterCodable.sharedInstance.decoderAnnotetion(annoData) {
                
                self.annotation = annotation
                imageImagemeter()
                audioImagemeter()
                
            } else {
                appDelegate.messageNotification("_error_", description: "_error_decompressing_", visible: true, delay: TimeInterval(k_dismissAfterSecond), type: TWMessageBarMessageType.error, errorCode: Int(k_CCErrorInternalError))
            }
            
        } catch {
            print("error:\(error)")
        }
    }

    @objc private func updateTimer() {
        counterSecondPlayer += 1
        imagemeterView.progressView.progress = Float(counterSecondPlayer / durationPlayer)
    }
    
    private func imageImagemeter() {
        
        guard let annotation = self.annotation else {
            return
        }
        
        let imageFilename = annotation.image.filename
        if let image = UIImage(contentsOfFile: pathArchiveImagemeter + "/" + imageFilename) {
            
            let factor = image.size.width / image.size.height
            
            imagemeterView.imageHeightConstraint.constant = imagemeterView.bounds.size.width / factor
            imagemeterView.image.image = image
        }
    }
    
    @objc func audioImagemeter() {
        
        guard let annotation = self.annotation else {
            return
        }
        
        for view in imagemeterView.image.subviews {
            view.removeFromSuperview()
        }
        
        for element in annotation.elements {
            
            let coordinateNormalize =  IMImagemeterCodable.sharedInstance.convertCoordinate(x: element.center.x, y: element.center.y, width: imagemeterView.bounds.width, height: imagemeterView.imageHeightConstraint.constant)            
            let x = coordinateNormalize.x
            let y = coordinateNormalize.y
            
            let button = UIButton()
            button.frame = CGRect(x: x, y: y, width: 30, height: 30)
            button.setImage(UIImage(named: "audioPlay"), for: .normal)
            button.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)
            button.tag = element.id
    
            imagemeterView.image.addSubview(button)
        }
    }
    
    @objc private func buttonAction(sender: UIButton!) {
        
        guard let annotation = self.annotation else {
            return
        }
        
        for element in annotation.elements {
            if element.id == sender.tag {
                do {

                    let fileNamePath =  pathArchiveImagemeter + "/" + element.audio_recording.recording_filename
                    try audioPlayer = AVAudioPlayer(contentsOf: URL(fileURLWithPath: fileNamePath))
                    audioPlayer.delegate = self
                    audioPlayer.prepareToPlay()
                    audioPlayer.play()

                    durationPlayer = TimeInterval(audioPlayer.duration)
                    timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateTimer), userInfo: nil, repeats: true)

                } catch {
                    
                }
            }
        }
    }
}

extension NCViewerImagemeter: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        
        updateTimer()
        timer.invalidate()
        counterSecondPlayer = 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.imagemeterView.progressView.progress = 0
        }
    }
}

class IMImagemeterView: UIView {
    
    @IBOutlet weak var image: UIImageView!
    @IBOutlet weak var imageHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var progressView: UIProgressView!
    
    class func instanceFromNib() -> UIView {
        return UINib(nibName: "IMImagemeterView", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as! UIView
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        image.isUserInteractionEnabled = true
        
        progressView.progressTintColor = NCBrandColor.sharedInstance.brandElement
        progressView.trackTintColor = UIColor(red: 247.0/255.0, green: 247.0/255.0, blue: 247.0/255.0, alpha: 1.0)
        progressView.progress = 0
    }
}
