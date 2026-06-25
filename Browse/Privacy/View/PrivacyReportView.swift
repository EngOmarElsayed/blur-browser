import SwiftUI
import FactoryKit

struct PrivacyReportView: View {
    @InjectedObservable(\.privacyReportStore) private var store

    var body: some View {
        if store.snapshot.hasBrowsingHistory {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy Report")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)

                PrivacyReportCard(privacySnapshot: store.snapshot)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(height: 350)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
