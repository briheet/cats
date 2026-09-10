import SwiftUI

struct PreviewGallery: View {
    let reading: SnapshotReading

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DesktopCard(kind: .overview, reading: reading)
            HStack(spacing: 24) {
                DesktopCard(kind: .providers, reading: reading)
                DesktopCard(kind: .small, reading: reading)
                DesktopCard(
                    kind: .small,
                    reading: SnapshotReading(state: TelemetryState(theme: reading.state.theme)))
            }
        }
        .padding(32)
        .background { PreviewBackdrop() }
    }
}
