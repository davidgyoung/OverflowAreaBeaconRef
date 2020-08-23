//
//  CollisionAvoider.swift
//
//  Created by David G. Young on 5/9/20.
//  Copyright © 2020 David G. Young, all rights reserved.
//  Licensed under Apache 2
//

import Foundation

/*
 The purpose of this class is to avoid collisions in background advertisements
 that use the overflow area.
 
 Advertisements are shifted for broadcast to one of several positions within the overflow area
 Detected advertisements are searched at particular positions.  Positions that do not contain our advertisement are
 expected to be all zero.  If they are not, that means another app is using thier bits and they are confirmed to be polluted.
 
 We wait to use an advertisement detected in particular position
 */
class OverflowAreaCollisionAvoider {
    public static let shared = OverflowAreaCollisionAvoider()
    public var numberOfPositions = 2
    let OverflowAreaSize = 16
    // Bit 69 of the overflow area advert causes an Apple WAtch pair notification on a receiving phone if
    // it is only a few cm away.  So we can avoid it when using two positions by having an offset of 1 when
    // we have two positions.
    private var PositionByteOffset = 1
    // The setting below can be used to help make overflow work even if the app is in the foreground.  Use only with above setting at 1 or higher
    public let AlwaysSetFirstBit = true
    // If set to true, we will ignore unverfied positions until we see thorough rotatio that they are not polluted.
    // This will not be possible on iOS 14 devices as they cannot change their CB service advertisements in the background, so it should be set to false unless you know you will be used with iOS 14.
    public let IgnoreUnverifiedPositions = false
    // TODO: Need to purge this cache periodically
    var positionStatusByDeviceId: [String:[Int:String]] = [:]

    private init() {
        
    }
    public func shiftAdvertisement(matchingByte: UInt8, payloadToAdvertise: [UInt8], position: Int) -> [UInt8] {
        var overflowAreaBytes: [UInt8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
        overflowAreaBytes[startByteNumber(position: position)] = matchingByte
        for i in 0...payloadToAdvertise.count-1 {
            overflowAreaBytes[startByteNumber(position: position)+i+1] = payloadToAdvertise[i]
        }
        return overflowAreaBytes
    }

    public func extractPayload(overflowAreaBytes: [UInt8], matchingByte: UInt8, payloadSize: Int, deviceId: String?) -> [UInt8]? {
        var payload: [UInt8]? = nil
        var foundPosition: Int? = nil
        let hexString = String(format: "%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X", overflowAreaBytes[0],overflowAreaBytes[1],overflowAreaBytes[2],overflowAreaBytes[3],overflowAreaBytes[4],overflowAreaBytes[5],overflowAreaBytes[6],overflowAreaBytes[7],overflowAreaBytes[8],overflowAreaBytes[9],overflowAreaBytes[10],overflowAreaBytes[11],overflowAreaBytes[12],overflowAreaBytes[13],overflowAreaBytes[14],overflowAreaBytes[15])
        if BackgroundBeaconManager.shared.debugLoggingEnabled {
            NSLog("searching for pattern match in overflow area advertisement \(hexString)")
        }

        for position in 0...numberOfPositions-1 {
            let startByte = startByteNumber(position: position)
            if overflowAreaBytes[startByte] == matchingByte {
                foundPosition = position
                payload = []
                for i in 1...payloadSize {
                    payload?.append(overflowAreaBytes[startByte+i])
                }
                break
            }
        }
        if let deviceId = deviceId {
            if let foundPosition = foundPosition {
                let pollutionStatus = positionStatusByDeviceId[deviceId]?[foundPosition] ?? "unknown"
                if pollutionStatus == "unknown" && IgnoreUnverifiedPositions {
                    if BackgroundBeaconManager.shared.debugLoggingEnabled {
                        NSLog("Position \(foundPosition) in the overflow area has not been verified unpolluted yet for device \(deviceId).  Ignoring detection")
                    }
                    payload = nil
                }
                else if pollutionStatus == "polluted" {
                    NSLog("Position \(foundPosition) in the overflow area is known to be polluted for device \(deviceId).  Ignoring detection")
                    payload = nil
                }
            }
            // Check the other positions to see if they are all 0.  If not, we know they are
            // polluted
            for position in 0...numberOfPositions-1 {
                if position != foundPosition {
                    let startByte = startByteNumber(position: position)
                    var allZero = true
                    for i in 0...payloadSize {
                        if overflowAreaBytes[startByte+i] != 0 {
                            allZero = false
                            break
                        }
                    }
                    if positionStatusByDeviceId[deviceId] == nil {
                        positionStatusByDeviceId[deviceId] = [:]
                    }
                    if allZero {
                        positionStatusByDeviceId[deviceId]?[position] = "unpolluted"
                    }
                    else {
                        positionStatusByDeviceId[deviceId]?[position] = "polluted"
                    }
                }
            }

        }
        return payload
    }
    func startByteNumber(position: Int) -> Int {
        return (OverflowAreaSize/numberOfPositions)*position+PositionByteOffset
    }
}
