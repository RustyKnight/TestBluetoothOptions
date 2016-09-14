//
//  ViewController.swift
//  AudioTest
//
//  Created by Shane Whitehead on 13/09/2016.
//  Copyright © 2016 Beam Communications. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer

extension MPMusicPlaybackState : CustomStringConvertible {
	
	public var description: String {
		switch self {
		case .stopped: return "Stopped"
		case .playing: return "Playing"
		case .paused: return "Paused"
		case .interrupted: return "Interrupted"
		case .seekingForward: return "Seeking Forward"
		case .seekingBackward: return "Seeking Backward"
		}
	}
}


class ViewController: UIViewController {
	
	@IBOutlet weak var monitor: UIButton!
	@IBOutlet weak var configure: UIButton!
	@IBOutlet weak var detect: UIButton!
	
	@IBOutlet weak var hasHeadsetLabel: UILabel!
	@IBOutlet weak var hasBluetoothLabel: UILabel!
	
	let player = MPMusicPlayerController.applicationMusicPlayer()
	override func viewDidLoad() {
		super.viewDidLoad()
		
		AudioSessionManager.shared.requestRecordPermission { (authenticated) in
			print("Record authentication = \(authenticated)")
		}
		
		doMonitor(self)
		
		NotificationCenter.default.addObserver(self, selector: #selector(ViewController.nowPlayingItemChanged), name: NSNotification.Name.MPMusicPlayerControllerNowPlayingItemDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(ViewController.playBackStateChanged), name: NSNotification.Name.MPMusicPlayerControllerPlaybackStateDidChange, object: nil)
		
		player.beginGeneratingPlaybackNotifications()
		player.shuffleMode = .off
		player.repeatMode = .all
		
		let predicate = MPMediaPropertyPredicate(value: "Attack of the Crab Women", forProperty: MPMediaItemPropertyTitle)
		let query = MPMediaQuery()
		query.addFilterPredicate(predicate)
		
		player.setQueue(with: query)
		print("Is Prepared to Play \(player.isPreparedToPlay)")
		player.prepareToPlay()
		player.play()
		print("Playback state \(player.playbackState)")
		print("Now playing \(player.nowPlayingItem)")
		//		guard let items = query.items else {
		//			return
		//		}
		//		for song in items {
		//			print(song.title)
		//		}

		updateOptions()
	}
	
	func updateOptions() {
		hasHeadsetLabel.isHidden = !AudioSessionManager.shared.hasHeadset
		hasBluetoothLabel.isHidden = !AudioSessionManager.shared.hasBluetooth
	}
	
	func nowPlayingItemChanged(_ notification: Notification) {
		print("nowPlayingItemChanged")
		print("Now playing \(player.nowPlayingItem)")
	}
	
	func playBackStateChanged(_ notification: Notification) {
		print("playBackStateChanged")
		print("Playback state \(player.playbackState)")
		if player.playbackState == .paused {
			player.prepareToPlay()
			player.play()
		}
	}
	
	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}
	
	@IBAction func doDetect(_ sender: AnyObject) {
		do {
			try AudioSessionManager.shared.invalidateAndRefresh()
		} catch let error {
			print("detectAvailableDevices failed with \(error)")
		}
		
		updateOptions()
	} 
	
	@IBAction func doConfigure(_ sender: AnyObject) {
		do {
			try AudioSessionManager.shared.configure(withOverride: .none)
		} catch let error {
			print("configureAudioSession failed with \(error)")
		}
	}
	
	@IBAction func doMonitor(_ sender: AnyObject) {
		AudioSessionManager.shared.monitor = !AudioSessionManager.shared.monitor
		monitor.setTitle(AudioSessionManager.shared.monitor ? "Stop" : "Monitor", for: [])
	}
	
	@IBAction func doRouter(_ sender: AnyObject) {
		selectOutput()
	}
	
	func selectOutput() {
		//		let controller = UIAlertController(title: nil,
		//		                                   message: nil,
		//		                                   preferredStyle: UIAlertControllerStyle.actionSheet)
		do {
			let controller = try AudioSessionManager.shared.alertController(
				selected: { (route) in
					print("selected \(route)")
					self.player.play()
				}, errored: { (error) in
					print("Error: ")
					print("\(error)")
			}) {
				print("Cancelled")
			}
			present(controller, animated: true, completion: nil)
		} catch let error {
			print(error)
		}
		
		//		for action in actions {
		//			controller.addAction(action)
		//		}
		
		//		var speakerRouteChecked: Bool = true
		//		do {
		//			let routes = try AudioSessionManager.shared.audioRoutes()
		//			let filteredRoutes = routes.filter({ (route) -> Bool in
		//				return route.portType != AVAudioSessionPortBuiltInMic &&
		//					route.portType != AVAudioSessionPortBuiltInSpeaker &&
		//					route.portType != AVAudioSessionPortBuiltInReceiver
		//			})
		//
		//			for route in filteredRoutes {
		//				let action = UIAlertAction(title: route.portName, style: .default, handler: { (action) in
		//					print(route)
		////					if AudioSessionManager.shared.isBluetoothDevice(port: route.portType) {
		////						do {
		////							try session.setCategory(AVAudioSessionCategoryPlayAndRecord, with: .allowBluetooth)
		////						} catch let error {
		////							print("!! Error \(error)")
		////						}
		////					}
		//				})
		//				if AudioSessionManager.shared.isBluetoothDevice(port: route.portType) {
		//					action.setValue(#imageLiteral(resourceName: "blueTooth"), forKey: "image")
		//				}
		//				if route.isCurrentRoute {
		//					speakerRouteChecked = false
		//					action.setValue(true, forKey: "checked")
		//				}
		//				controller.addAction(action)
		//			}
		//		} catch let error {
		//			print("Failed to list audio routes:  \(error)")
		//		}
		//
		//		let model = UIDevice.current.model
		//		let phoneAction = UIAlertAction(title: model, style: .default, handler: { (action) in
		//			do {
		//				try session.setCategory(AVAudioSessionCategoryPlayAndRecord)
		//				try session.overrideOutputAudioPort(AVAudioSessionPortOverride.none)
		//			} catch let error {
		//				print("!! Error \(error)")
		//			}
		//		})
		//		if speakerRouteChecked {
		//			phoneAction.setValue(true, forKey: "checked")
		//		}
		//		controller.addAction(phoneAction)
		//
		//		let speakerAction = UIAlertAction(title: "Speaker", style: .default, handler: { (action) in
		//			do {
		//				try session.setCategory(AVAudioSessionCategoryPlayAndRecord)
		//				try session.overrideOutputAudioPort(AVAudioSessionPortOverride.speaker)
		//			} catch let error {
		//				print("!! Error \(error)")
		//			}
		//		})
		//		speakerAction.setValue(#imageLiteral(resourceName: "speaker"), forKey: "image")
		//		controller.addAction(speakerAction)
		//
		//		controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		
	}
}
