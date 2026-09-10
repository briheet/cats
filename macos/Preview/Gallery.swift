import SwiftUI

struct PreviewGallery: View {
    let reading: SnapshotReading

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DesktopCard(kind: .overview, reading: reading)
            HStack(spacing: 24) {
                DesktopCard(kind: .providers, reading: reading)
                DesktopCard(kind: .mediumAgents, reading: reading)
            }
            HStack(spacing: 24) {
                DesktopCard(kind: .small, reading: reading)
                DesktopCard(kind: .smallAgents, reading: reading)
                DesktopCard(kind: .smallBurnRate, reading: reading)
            }
        }
        .padding(32)
        .background { PreviewBackdrop() }
    }
}
