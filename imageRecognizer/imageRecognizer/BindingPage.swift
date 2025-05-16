import SwiftUI

struct BindingPage: View {
    @State var realtime = false
    
    var body: some View {
        Group {
             if realtime {
                 RealtimeView(realtime: $realtime)
             } else {
                 StaticView(realtime: $realtime)
             }
         }
    }
}

#Preview {
    BindingPage()
}
