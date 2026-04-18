import SwiftUI

struct ErrorPageView: View {
    let error: BrowsingError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                // Emoji
                Text(error.message.emoji)
                    .font(.system(size: 56))

                // Title
                Text(error.message.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                    .multilineTextAlignment(.center)

                // Subtitle
                Text(error.message.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                // Retry button
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                        Text("Try Again")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: Colors.accentPrimary))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

//                // Error code (debug)
//                Text("\(error.errorDomain) (\(error.errorCode))")
//                    .font(.system(size: 10))
//                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted).opacity(0.5))
//                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Colors.surfaceSecondary))
    }
}
