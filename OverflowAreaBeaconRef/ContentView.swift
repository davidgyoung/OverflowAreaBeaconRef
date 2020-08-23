//
//  ContentView.swift
//  OverflowAreaBeaconRef
//
//  Created by David G. Young on 8/22/20.
//  Copyright © 2020 davidgyoungtech. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var beaconStateModel = BeaconStateModel.shared

    var body: some View {
       VStack {
            Text("This device major: \(beaconStateModel.myMajor) minor: \(beaconStateModel.myMinor)")
            Text("Error condition: \(beaconStateModel.error ?? "None known")")
            Text("I detect \(beaconStateModel.beacons.count) beacons")
            List(beaconStateModel.beacons) { beaconViewItem in
                Text(beaconViewItem.beaconString)
            }.id(UUID())
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct BeaconViewItem: Identifiable {
  var id = UUID()
  var beaconString: String
}

class BeaconStateModel: ObservableObject {
    static let shared = BeaconStateModel()
    private init() {
        
    }
    @Published var beacons: [BeaconViewItem] = []
    @Published var myMajor = 0
    @Published var myMinor = 0
    @Published var error: String? = nil
}

