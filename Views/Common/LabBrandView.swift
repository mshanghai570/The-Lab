//
//  LabBrandView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// The Lab's brand lockup — a beacon inside an outlined hot-pink square,
/// with the app name set in Playfair Display.
struct LabBrandView: View {
	private let pink = Color(red: 1.0, green: 0.0, blue: 151.0 / 255.0)
	private let neonGreen = Color(red: 0.0, green: 1.0, blue: 0.0)

	var body: some View {
		HStack(spacing: 18) {
			ZStack {
				RoundedRectangle(cornerRadius: 20, style: .continuous)
					.stroke(pink, lineWidth: 3)
					.frame(width: 64, height: 64)
					.labGlow(pink, radius: 14, opacity: 0.28)

				Image(systemName: "beacon")
					.font(.system(size: 30, weight: .medium))
					.foregroundStyle(neonGreen)
					.labGlow(neonGreen, radius: 9, opacity: 0.45)
			}

			Text("The Lab")
				.font(.playfair(40, weight: .black))
				.kerning(0.5)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

#Preview {
	LabBrandView()
		.preferredColorScheme(.dark)
		.background(Color.black)
}
