//
//  AppDelegate.swift
//  OverflowAreaBeaconRef
//
//  Created by David G. Young on 8/22/20.
//  Copyright © 2020 davidgyoungtech. All rights reserved.
//

import UIKit
import CoreBluetooth
import CoreLocation


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, CBPeripheralManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate, CLLocationManagerDelegate, OverflowDetectorDelegate, FusedBeaconInterface {
    
    
    // Fields needed for beacon scanning and advertising
    var locationManager: CLLocationManager!
    var peripheralManager: CBPeripheralManager? = nil
    var centralManager: CBCentralManager? = nil
    let centralQueue = DispatchQueue.global(qos: .userInitiated)
    let peripheralQueue = DispatchQueue.global(qos: .userInitiated)
    let backgroundBeaconManager = BackgroundBeaconManager.shared
    var beaconUuid: UUID? = nil
    var beaconMajor: UInt16? = nil
    var beaconMinor: UInt16? = nil
    var measuredPower: Int8? = nil
    var active = false
    var errors: Set<String> = []

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        self.centralManager = CBCentralManager(delegate: self, queue: centralQueue)

        self.peripheralManager = CBPeripheralManager(delegate: self, queue: peripheralQueue, options: [:])
        BackgroundBeaconManager.shared.peripheralManager = self.peripheralManager!
                
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 3000.0
        
        if #available(iOS 9.0, *) {
          locationManager.allowsBackgroundLocationUpdates = true
        } else {
          // not needed on earlier versions
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            self.updateAuthWarnings()

            if let error = error {
                NSLog("error: \(error)")
            }
            
        }
        // start updating location at beginning just to give us unlimited background running time
        self.locationManager.startUpdatingLocation()
        // start ranging beacons to force BLE scans.  If this is not done, delivery of overflow area advertisements will not be made when the
        // app is not in the foreground.  Enabling beacon ranging appears to unlock this background delivery, at least when the screen is on.
        let minor = Int.random(in: 1..<10000)
        BeaconStateModel.shared.myMajor = 1
        BeaconStateModel.shared.myMinor = minor

        configure(iBeaconUuid: UUID(uuidString: "2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6")!, overflowMatchingByte: 0xaa,  major: 1, minor: UInt16(minor), measuredPower: -59)
        _ = startScanning(delegate: self)
        _ = startTx()

        periodicallySendScreenOnNotifications()
        extendBackgroundRunningTime()
        updateAuthWarnings()
        
        return true
    }
    func didDetectBeacon(type: String, major: UInt16, minor: UInt16, rssi: Int, proximityUuid: UUID?, distance: Double?){
        NSLog("Detected beacon major: \(major) minor: \(minor) of type: \(type)")
        updateBeaconListView(type: type, major: major, minor: minor, rssi: rssi, proximityUuid: proximityUuid, distance: distance)
    }
    
    func updateBeaconListView(type: String, major: UInt16, minor: UInt16, rssi: Int, proximityUuid: UUID?, distance: Double?){

        DispatchQueue.main.async {
            var beaconViewItems = BeaconStateModel.shared.beacons
            let majorMinor = "major: \(major), minor:\(minor)"
            let beaconString = "\(majorMinor), rssi: \(rssi) (\(type))"
            let beaconViewItem = BeaconViewItem(beaconString: beaconString)
            var updatedExisting = false
            var index = 0
            for existingBeaconViewItem in beaconViewItems {
                if existingBeaconViewItem.beaconString.contains(majorMinor) {
                    beaconViewItems[index] = beaconViewItem
                    updatedExisting = true
                    break
                }
                index += 1
            }
            if (!updatedExisting) {
                beaconViewItems.append(beaconViewItem)
            }
            BeaconStateModel.shared.beacons = beaconViewItems
        }
    }
    
    func periodicallySendScreenOnNotifications() {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()+30.0) {
            self.sendNotification()
            self.periodicallySendScreenOnNotifications()
        }
    }

    func sendNotification() {
        DispatchQueue.main.async {
            let center = UNUserNotificationCenter.current()
            center.removeAllDeliveredNotifications()
            let content = UNMutableNotificationContent()
            content.title = "Scanning OverflowArea beacons"
            content.body = ""
            content.categoryIdentifier = "low-priority"
            //let soundName = UNNotificationSoundName("silence.mp3")
            //content.sound = UNNotificationSound(named: soundName)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == CBManagerState.poweredOn {
            _ = startScanning(delegate: self)
            DispatchQueue.main.async {
                self.errors.remove("Bluetooth off")
                BeaconStateModel.shared.error = self.errors.first
            }
        }
        if central.state == CBManagerState.poweredOff {
            DispatchQueue.main.async {
                self.errors.insert("Bluetooth off")
                BeaconStateModel.shared.error = self.errors.first
            }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let beaconBytes = BackgroundBeaconManager.shared.extractBeaconBytes(peripheral: peripheral, advertisementData: advertisementData, countToExtract: 4) {
            let major = UInt16(beaconBytes[0]) << 8 + UInt16(beaconBytes[1])
            let minor = UInt16(beaconBytes[2]) << 8 + UInt16(beaconBytes[3])
            NSLog("I just read overflow area advert with major: \(major) minor: \(minor)")
            self.didDetectBeacon(type: "OverflowArea", major: major, minor: minor, rssi: RSSI.intValue, proximityUuid: nil, distance: nil)
        }
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == CBManagerState.poweredOn {
            DispatchQueue.main.async {
                self.errors.remove("Bluetooth off")
                BeaconStateModel.shared.error = self.errors.first
                _ = self.startTx()
            }
        }
        else{
        }
        NSLog("Bluetooth power state changed to \(peripheral.state)")
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    }
    
    var backgroundTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    var threadStarted = false
    var threadShouldExit = false
    func extendBackgroundRunningTime() {
      if (threadStarted) {
        // if we are in here, that means the background task is already running.
        // don't restart it.
        return
      }
      threadStarted = true
      NSLog("Attempting to extend background running time")
      
      self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "DummyTask", expirationHandler: {
        NSLog("Background task expired by iOS.")
        UIApplication.shared.endBackgroundTask(self.backgroundTask)
      })

    
      var lastLogTime = 0.0
      DispatchQueue.global().async {
        let startedTime = Int(Date().timeIntervalSince1970) % 10000000
        NSLog("*** STARTED BACKGROUND THREAD")
        while(!self.threadShouldExit) {
            DispatchQueue.main.async {
                let now = Date().timeIntervalSince1970
                let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
                if abs(now - lastLogTime) >= 2.0 {
                    lastLogTime = now
                    if backgroundTimeRemaining < 10.0 {
                      NSLog("About to suspend based on background thread running out.")
                    }
                    if (backgroundTimeRemaining < 200000.0) {
                     NSLog("Thread \(startedTime) background time remaining: \(backgroundTimeRemaining)")
                    }
                    else {
                      //NSLog("Thread \(startedTime) background time remaining: INFINITE")
                    }
                }
            }
            sleep(1)
        }
        self.threadStarted = false
        NSLog("*** EXITING BACKGROUND THREAD")
      }

    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    }
    
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthWarnings()
    }
    
    func updateAuthWarnings() {
        if CLLocationManager.locationServicesEnabled() {
            self.errors.remove("Location disabled in settings")
            if CLLocationManager.authorizationStatus() == .authorizedAlways {
                self.errors.remove("Location permission not set to always")
            }
            else {
                self.errors.insert("Location permission not set to always")
            }
        }
        else {
            self.errors.insert("Location disabled in settings")
        }
        if CBManager.authorization == .allowedAlways {
            self.errors.remove("Bluetooth permission denied")
        }
        else {
            self.errors.insert("Bluetooth permission denied")
        }
        UNUserNotificationCenter.current().getNotificationSettings(completionHandler: { settings in
            if settings.authorizationStatus == UNAuthorizationStatus.authorized {
                self.errors.remove("Notification permission denied")
            }
            else {
                self.errors.insert("Notification permission denied")
            }
            DispatchQueue.main.async {
                BeaconStateModel.shared.error = self.errors.first
            }
        })

        DispatchQueue.main.async {
            BeaconStateModel.shared.error = self.errors.first
        }

    }
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        for beacon in beacons {
            NSLog("I just read iBeacon advert with major: \(beacon.major) minor: \(beacon.minor)")

            self.didDetectBeacon(type: "iBeacon", major: beacon.major.uint16Value, minor: beacon.minor.uint16Value, rssi: beacon.rssi, proximityUuid: beacon.proximityUUID, distance: beacon.accuracy)
        }
    }
    // NOTE:  This is chained from SceneDelegate.swift
    func applicationDidEnterBackground(_ application: UIApplication) {
        active = false
        _ = startTx()
    }
    // NOTE:  This is chained from SceneDelegate.swift
    func applicationDidBecomeActive(_ application: UIApplication) {
        active = true
        _ = startTx()
    }

    // MARK: UISceneSession Lifecycle
    

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // MARK:
    func configure(iBeaconUuid: UUID, overflowMatchingByte: UInt8, major: UInt16, minor: UInt16, measuredPower: Int8) {
        self.backgroundBeaconManager.matchingByte = 0xaa
        self.beaconUuid = iBeaconUuid
        self.beaconMajor = major
        self.beaconMinor = minor
        self.measuredPower = measuredPower
    }
    
    // Must be called on main thread
    @objc
    func startTx() -> Bool {
            if self.peripheralManager?.state == CBManagerState.poweredOn {
                if let major = self.beaconMajor, let minor = self.beaconMinor, let uuid = self.beaconUuid, let power = self.measuredPower {
                    self.backgroundBeaconManager.stopAdvertising()
                    // Always set up to advertise overflow (even when we are in th foreground), becasue we are blocked from
                    // doing so when we are in the background.
                    let overflowBytes = [UInt8(major >> 8), UInt8(major & 0xff), UInt8(minor >> 8), UInt8(minor & 0xff)]
                    self.backgroundBeaconManager.startAdvertising(beaconBytes: overflowBytes, rotate: !active)
                    // In the foreground we will immediately overrwrite this advert with iBeacon
                    if (active) {
                        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()+0.1) {
                            self.peripheralManager?.stopAdvertising()
                            // We are in the foreground.  Advertise iBeacon.  But wait a bit before we do or it does not take effect
                            let peripheralData = CLBeaconRegion(uuid: uuid, major: major, minor: minor, identifier: "dummy").peripheralData(withMeasuredPower: power as NSNumber)
                            self.peripheralManager?.startAdvertising(peripheralData as? [String: Any])
                        }
                    }
                    return true
                    
                }
                else {
                  NSLog("Configure not called.  Cannot transmit")
                    return false
                }
            }
            else {
                NSLog("Cannot start transmitting without bluetooth powered off")
                return false
            }
    }
    
    func stopTx() {
        self.backgroundBeaconManager.stopAdvertising()
    }
    
    func startScanning(delegate: OverflowDetectorDelegate) -> Bool {
        if centralManager?.state == CBManagerState.poweredOn {
            locationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: beaconUuid!))
            centralManager?.scanForPeripherals(withServices: OverflowAreaUtils.allOverflowServiceUuids(), options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            return true
        }
        else {
            NSLog("Cannot start scanning yet... peripheral is not powered on")
            return false
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        for constraint in locationManager.rangedBeaconConstraints {
            locationManager.stopRangingBeacons(satisfying: constraint)
        }
    }
}

protocol FusedBeaconInterface {
    func configure(iBeaconUuid: UUID, overflowMatchingByte: UInt8, major: UInt16, minor: UInt16, measuredPower: Int8)
    func startTx() -> Bool
    func stopTx()
    func startScanning(delegate: OverflowDetectorDelegate) -> Bool
    func stopScanning()
}

protocol OverflowDetectorDelegate {
    func didDetectBeacon(type: String, major: UInt16, minor: UInt16, rssi: Int, proximityUuid: UUID?, distance: Double?)
}

