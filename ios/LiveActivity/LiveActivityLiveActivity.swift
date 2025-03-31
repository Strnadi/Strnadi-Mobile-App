//
//  LiveActivityLiveActivity.swift
//  LiveActivity
//
//  Created by Jan Drobílek on 30/3/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState // don't forget to add this line, otherwise, live activity will not display it.

  public struct ContentState: Codable, Hashable { }

  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    return "\(id)_\(key)"
  }
}

let sharedDefault = UserDefaults(suiteName: "group.delta.strnadi")!

//let text = sharedDefault.string(forKey: context.attributes.prefixedKey("testText")) ?? "No value set"

struct LiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            HStack(spacing: 12) {
                Image("Strnad")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                Text("Aplikace Strnadi nahrává")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal)
            .activityBackgroundTint(Color.white)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("Strnad")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)  // updated from 50 to 40
                        .padding(6)
                        .background(Circle().fill(Color.white))
                        .clipShape(Circle())
                        .shadow(radius: 3)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "record.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .padding(6)
                        .background(Circle().fill(Color.black))  // changed background from white to black
                        .clipShape(Circle())
                        .foregroundColor(.red)
                        .shadow(radius: 3)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Aplikace Strnadi nahrává")
                        .font(.headline)
                        .fontWeight(.medium)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            } compactLeading: {
                Image("Strnad")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } compactTrailing: {
                Image(systemName: "record.circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.red)
            } minimal: {
                Image(systemName: "record.circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.red)
            }
            //.widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

/*
#Preview("Notification", as: .content, using: LiveActivitiesAppAttributes.preview) {
   LiveActivityLiveActivity()
} contentStates: {
    LiveActivityAttributes.ContentState.smiley
    LiveActivityAttributes.ContentState.starEyes
}
*/
