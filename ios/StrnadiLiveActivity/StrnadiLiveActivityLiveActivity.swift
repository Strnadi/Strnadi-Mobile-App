//
//  StrnadiLiveActivityLiveActivity.swift
//  StrnadiLiveActivity
//
//  Created by Jan Drobílek on 29/3/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct StrnadiLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct StrnadiLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StrnadiLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension StrnadiLiveActivityAttributes {
    fileprivate static var preview: StrnadiLiveActivityAttributes {
        StrnadiLiveActivityAttributes(name: "World")
    }
}

extension StrnadiLiveActivityAttributes.ContentState {
    fileprivate static var smiley: StrnadiLiveActivityAttributes.ContentState {
        StrnadiLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: StrnadiLiveActivityAttributes.ContentState {
         StrnadiLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: StrnadiLiveActivityAttributes.preview) {
   StrnadiLiveActivityLiveActivity()
} contentStates: {
    StrnadiLiveActivityAttributes.ContentState.smiley
    StrnadiLiveActivityAttributes.ContentState.starEyes
}
