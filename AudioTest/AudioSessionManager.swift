//
//  AudioSessionManager.swift
//  AudioTest
//
//  Created by Shane Whitehead on 13/09/2016.
//  Copyright © 2016 Beam Communications. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

enum AudioSessionManagerError: Error {
	case noInputsAvailable
}

/*
Try and remember inputs is audio coming in, output is audio going out, I think :P
*/

protocol AudioRouteSelectable {
	var route: AudioRoute? {get}
	var portOverride: AVAudioSessionPortOverride? {get}
}

protocol AudioRouteSelectionErrorable: AudioRouteSelectable {
	var error: Error {get}
}

struct AudioRouteSelectionError: AudioRouteSelectionErrorable, CustomStringConvertible {
	let error: Error
	let route: AudioRoute?
	let portOverride: AVAudioSessionPortOverride?
	
	init(error: Error, route: AudioRoute? = nil, portOverride: AVAudioSessionPortOverride? = nil) {
		self.error = error
		self.route = route
		self.portOverride = portOverride
	}
	
	var description: String {
		var message = "AudioRouteSelectionError: "
		if let route = route {
			message += "Route = [\(route)]"
		} else if let portOverride = portOverride {
			message += "Port Override = [\(portOverride)]"
		}
		message += "; \(error)"
		
		return message
	}
}

struct AudioRouteSelection: AudioRouteSelectable, CustomStringConvertible {
	let route: AudioRoute?
	let portOverride: AVAudioSessionPortOverride?
	
	init(route: AudioRoute? = nil, portOverride: AVAudioSessionPortOverride? = nil) {
		self.route = route
		self.portOverride = portOverride
	}
	
	var description: String {
		var message = "AudioRouteSelection: "
		if let route = route {
			message += "Route = [\(route)]"
		} else if let portOverride = portOverride {
			message += "Port Override = [\(portOverride)]"
		}
		
		return message
	}
}

typealias AudioRouteSelectionCancelled = () -> Void
typealias AudioRouteSelected = (AudioRouteSelectable) -> Void
typealias AudioRouteSelectionErrored = (AudioRouteSelectionErrorable) -> Void

struct AudioRoute: CustomStringConvertible, Hashable {

	var inputRoute: AVAudioSessionPortDescription
	
	init(inputRoute: AVAudioSessionPortDescription) {
		self.inputRoute = inputRoute
	}
	
	var portName: String {
		return inputRoute.portName
	}
	
	var portType: String {
		return inputRoute.portType
	}
	
	var description: String {
		return "AudioRoute: [\(portName)] of [\(portType)] type"
	}
	
	var hashValue: Int {
		return "\(portName),\(portType)".hashValue
	}
	
	static func ==(lhs: AudioRoute, rhs: AudioRoute) -> Bool {
		return lhs.portName == rhs.portName && lhs.portType == rhs.portType
	}
}

extension AVAudioSessionRouteChangeReason : CustomStringConvertible {
	
	public var description: String {
		switch  self {
		case .unknown: return "Unknown"
		case .newDeviceAvailable: return "newDeviceAvilable"
		case .oldDeviceUnavailable: return "oldDeviceUnabailble"
		case .categoryChange: return "CategoryChanged"
		case .override: return "Override"
		case .wakeFromSleep: return "wakeFromSleep"
		case .noSuitableRouteForCategory: return "No Suitable Route for Category"
		case .routeConfigurationChange: return "Route Configuration Changed"
		}
	}
}

extension AVAudioSessionPortOverride: CustomStringConvertible {
	public var description: String {
		switch self {
		case .none: return "None"
		case .speaker: return "Speaker"
		}
	}
}

class AudioSessionManager: NSObject {
	static let shared = AudioSessionManager()

	let session: AVAudioSession = AVAudioSession.sharedInstance()
	var availableRoutes: [AudioRoute] = []
	
	override init() {
		monitor = false
		
		super.init()
		
		do {
			try session.setActive(false)
			try applyDefaults(with: [.allowBluetooth, .defaultToSpeaker])
			availableRoutes = try audioRoutes()
			try session.setActive(false)
			try configure(withOverride: .speaker)
			try session.setActive(true)
		} catch let error {
			print(error)
		}
		
	}
	
	func applyDefaults(with: [AVAudioSessionCategoryOptions] = []) throws {
		var baseOptions: AVAudioSessionCategoryOptions = [.mixWithOthers]
		for option in with {
			baseOptions.insert(option)
		}
		try session.setCategory(AVAudioSessionCategoryPlayAndRecord, with: baseOptions)
		try session.overrideOutputAudioPort(.speaker)
		try session.setMode(AVAudioSessionModeVoiceChat)
	}
	
	func requestRecordPermission(_ block: @escaping PermissionBlock) {
		session.requestRecordPermission(block)
	}
	
	var monitor: Bool {
		didSet {
			print("monitor: \(monitor)")
			if monitor {
				NotificationCenter.default.addObserver(self,
				                                       selector: #selector(AudioSessionManager.routeChanged),
				                                       name: NSNotification.Name.AVAudioSessionRouteChange,
				                                       object: nil)
			} else {
				NotificationCenter.default.removeObserver(self)
			}
		}
	}
	
	func invalidateAndRefresh() throws {
		availableRoutes = try audioRoutes()
	}
	
	func routeChanged(_ notification: Notification) {
		print("RouteChanged")
		guard let userInfo = notification.userInfo else {
			print("!! No userInfo?")
			return
		}
		guard let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt else {
			print("!! No reason?")
			return
		}
		guard let reason = AVAudioSessionRouteChangeReason(rawValue: reasonValue) else {
			print("!! Invalid reason value?")
			return
		}
		
		print(">> RouteChanged because \(reason)")
		
		let oldRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
		
		// :P
		let oldOutput = oldRoute?.outputs.first?.portType
		
		let newRoute = session.currentRoute
		let newOutput = newRoute.outputs.first?.portType
		
		print("Old = \(oldRoute?.outputs.first)")
		print("New = \(newRoute.outputs.first)")
		
		print(">> oldOutput = \(oldOutput)")
		print(">> newOutput = \(newOutput)")
		
		switch reason {
		case .oldDeviceUnavailable:
			if oldOutput == AVAudioSessionPortHeadphones {
				// Special Scenario:
				// when headphones are plugged in before the call and plugged out during the call
				// route will change to {input: MicrophoneBuiltIn, output: Receiver}
				// manually refresh session and support all devices again.
				do {
					try session.setActive(false)
					try applyDefaults(with: [.allowBluetooth])
					try session.setActive(true)
				} catch let error {
					print("!! Unable to update from headphones: \(error)")
				}
			}
			break
		case .newDeviceAvailable:
			if isBluetoothDevice(port: newOutput!) {
				print(">> Switched to bluetooth!")
			} else if newOutput == AVAudioSessionPortHeadphones {
				print(">> Switched to headphones!")
			} else {
				print(">> Switched to [\(newOutput)]")
			}
			break
		case .override:
			if isBluetoothDevice(port: oldOutput!) {
				guard let inputs = session.availableInputs else {
					return
				}
				for input in inputs {
					print("...[\(input.portType)]")
					if isBluetoothDevice(port: input.portType) {
						print(">> Bluetooth is available in current inputs")
					}
				}
			}
			break
		case .routeConfigurationChange:
			if isBluetoothDevice(port: oldOutput!) {
				var hasBluetooth = false
				guard let inputs = session.availableInputs else {
					print("!! Not available inputs")
					return
				}
				
				for input in inputs {
					if isBluetoothDevice(port: input.portType) {
						hasBluetooth = true
						break
					}
				}
				
				print(">> hasBluetooth = \(hasBluetooth)")
			}
			break
		default:
			print(">> Some other reason: \(reason)")
			break
		}
	}
	
	func isBluetoothDevice(port: String) -> Bool {
		return port == AVAudioSessionPortBluetoothA2DP
			|| port == AVAudioSessionPortBluetoothHFP
	}
	
	fileprivate func audioRoutes() throws -> [AudioRoute] {
		// Cycle the audio session in order to update the available
		// inputs/outputs
		try session.setActive(false)
		
		try applyDefaults(with: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker])
		
		try session.setActive(true)
		
		var routes: [AudioRoute] = []
		
		if let inputs = session.availableInputs {
			for input in inputs {
				print(">> Input: \(input)")
				routes.append(AudioRoute(inputRoute: input))
			}
		}
		
		return routes.sorted(by: { (first, second) -> Bool in
			first.portName > second.portName
		})
	}
	
	var hasBluetooth: Bool {
		for route in availableRoutes {
			if isBluetoothDevice(port: route.portType) {
				return true
			}
		}
		return false
	}
	
	var hasHeadset: Bool {
		for route in availableRoutes {
			if route.portType == AVAudioSessionPortHeadsetMic || route.portType == AVAudioSessionPortHeadphones {
				return true
			}
		}
		return false
	}
	
	func configure(withOverride override: AVAudioSessionPortOverride) throws {
		
		try session.setActive(false)
		
		// Does the device have any input types (microphone)
		guard let _ = session.availableInputs else {
			throw AudioSessionManagerError.noInputsAvailable
		}
		
		// PlayAndRecord in order to redirect output audio
		try applyDefaults(with: [.allowBluetooth])

		try session.setActive(true)
		
		print("Override with \(override)")
		try session.overrideOutputAudioPort(override)
	}
	
	func configure(withRoute route: AudioRoute) throws {
		
		try session.setActive(false)
		
		// Does the device have any input types (microphone)
		guard let _ = session.availableInputs else {
			throw AudioSessionManagerError.noInputsAvailable
		}
		
		if isBluetoothDevice(port: route.portName) {
			try applyDefaults(with: [.allowBluetooth])
		} else {
			try applyDefaults()
		}
		
		try session.setPreferredInput(route.inputRoute)
		
		try session.setActive(true)
	}
	
	var currentInput: AVAudioSessionPortDescription? {
		let currentRoute = session.currentRoute
		return currentRoute.inputs.first
	}
	var currentOutput: AVAudioSessionPortDescription? {
		let currentRoute = session.currentRoute
		return currentRoute.outputs.first
	}
	
	func audioAlertActions(selected: AudioRouteSelected? = nil, errored: AudioRouteSelectionErrored? = nil) -> [UIAlertAction] {
		var actions: [UIAlertAction] = []
		
		let input = currentInput
		let output = currentOutput
		
		print("Current set to \(input); \(output)")
		
		var checked: Bool = false
		let routes = availableRoutes
		let filteredRoutes = routes.filter({ (route) -> Bool in
			return route.portType != AVAudioSessionPortBuiltInMic &&
				route.portType != AVAudioSessionPortBuiltInSpeaker &&
				route.portType != AVAudioSessionPortBuiltInReceiver
		})
		
		for route in filteredRoutes {
			let action = UIAlertAction(title: route.portName, style: .default, handler: { (action) in
				do {
					try AudioSessionManager.shared.configure(withRoute: route)
					selected?(AudioRouteSelection(route: route))
				} catch let error {
					errored?(AudioRouteSelectionError(error: error, route: route))
				}
			})
			if AudioSessionManager.shared.isBluetoothDevice(port: route.portType) {
				action.setValue(#imageLiteral(resourceName: "blueTooth"), forKey: "image")
			}
			if route.portName == input?.portName {
				checked = true
				action.setValue(true, forKey: "checked")
			}
			
			actions.append(action)
		}
		
		let model = UIDevice.current.model
		let phoneAction = UIAlertAction(title: model, style: .default, handler: { (action) in
			do {
				try AudioSessionManager.shared.configure(withOverride: AVAudioSessionPortOverride.none)
				selected?(AudioRouteSelection(portOverride: .none))
			} catch let error {
				print("!! Error \(error)")
				errored?(AudioRouteSelectionError(error: error, portOverride: .none))
			}
		})
		if !checked && AVAudioSessionPortBuiltInReceiver == output?.portName {
			phoneAction.setValue(true, forKey: "checked")
		}
		actions.append(phoneAction)

		let speakerAction = UIAlertAction(title: "Speaker", style: .default, handler: { (action) in
			do {
				try AudioSessionManager.shared.configure(withOverride: AVAudioSessionPortOverride.speaker)
				selected?(AudioRouteSelection(portOverride: .speaker))
			} catch let error {
				errored?(AudioRouteSelectionError(error: error, portOverride: .speaker))
			}
		})
//		AVAudioSessionPortBuiltInReceiver
		if !checked && AVAudioSessionPortBuiltInSpeaker == output?.portName {
			speakerAction.setValue(true, forKey: "checked")
		}
		speakerAction.setValue(#imageLiteral(resourceName: "speaker"), forKey: "image")
		actions.append(speakerAction)
		
		return actions
	}
	
	func alertController(selected: AudioRouteSelected? = nil, errored: AudioRouteSelectionErrored? = nil, cancelled: AudioRouteSelectionCancelled? = nil) -> UIAlertController {
		let controller = UIAlertController(title: nil,
		                                   message: nil,
		                                   preferredStyle: UIAlertControllerStyle.actionSheet)
		var actions = AudioSessionManager.shared.audioAlertActions(selected: selected, errored: errored)
		actions.append(UIAlertAction(title: "Cancel", style: .cancel, handler: {(action) in
			cancelled?()
		}))
		for action in actions {
			controller.addAction(action)
		}
		return controller
	}
}

/**
newDict = leftDict + rightDict
*/

/**
`+` operator for merging two dictionaries

`newDict = leftDict + rightDict`

- parameter left:  Dictionary to be merged
- parameter right: Dictionary to be merged

- returns: A new dictionary which is a merge of the left and right values,
where the right will override any duplicate keys from the left
*/
func + <K, V> (left: [K:V], right: [K:V]) -> [K:V] {
	var new = [K:V]()
	for (k, v) in left {
		new[k] = v
	}
	for (k, v) in right {
		new[k] = v
	}
	return new
}

/**
+= operator for merging two dictionaries, inplace

leftDict += rightDict
*/

/**
`+=` operator for merging two dictionaries, inplace

`leftDict += rightDict`

- parameter left:  Source dictionary
- parameter right: Dictionary to be merged
*/
func += <K, V> ( left: inout [K:V], right: [K:V]?) {
	guard let right = right else { return }
	right.forEach { key, value in
		left.updateValue(value, forKey: key)
	}
}
