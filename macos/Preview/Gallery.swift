import SwiftUI

struct PreviewGallery: View {
    let reading: SnapshotReading

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            DesktopCard(kind: .overview, reading: reading)
            VStack(spacing: 24) {
                DesktopCard(kind: .providers, reading: reading)
                DesktopCard(
                    kind: .providers,
                    reading: SnapshotReading(state: TelemetryState(theme: reading.state.theme)))
            }
        }
        .padding(32)
        .background { PreviewBackdrop() }
    }
}
