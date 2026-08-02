//
//	LabBeakerIcon.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// The Lab's illuminated beaker mark.
///
/// A black glass body, a neon green outline, a hot pink "chemical" blooming
/// inside, and a faint reflection — backlit the way lab glass would look on
/// an OLED display.
struct LabBeakerIcon: View {
	var size: CGFloat = 64

	private var lineWidth: CGFloat { size * 0.028 }

	var body: some View {
		let scale = CGAffineTransform(scaleX: size, y: size)

		ZStack {
			// Black glass body — translucent dark silhouette of the flask.
			LabBeakerShape.glass.applying(scale)
				.fill(
					LinearGradient(
						colors: [
							LabTheme.surfaceSecondary.opacity(0.85),
							.black.opacity(0.35)
						],
						startPoint: .top,
						endPoint: .bottom
					)
				)

			// Hot pink chemical — glows inside the glass.
			LabBeakerShape.liquid.applying(scale)
				.fill(
					LinearGradient(
						colors: [
							LabTheme.accent,
							LabTheme.accent.opacity(0.5)
						],
						startPoint: .top,
						endPoint: .bottom
					)
				)
				.labGlow(LabTheme.accent, radius: size * 0.10, opacity: 0.35)

			// A brighter pink edge keeps the chemical legible at small sizes.
			LabBeakerShape.liquid.applying(scale)
				.stroke(
					LabTheme.accent.opacity(0.95),
					style: StrokeStyle(lineWidth: lineWidth * 0.55, lineCap: .round, lineJoin: .round)
				)

			// Bubbles in the chemical.
			LabBeakerShape.bubble(x: 0.42, y: 0.70, r: 0.045).applying(scale)
				.fill(LabTheme.accent.opacity(0.55))
			LabBeakerShape.bubble(x: 0.58, y: 0.62, r: 0.03).applying(scale)
				.fill(LabTheme.accent.opacity(0.4))

			// Faint reflection on the glass.
			LabBeakerShape.reflection.applying(scale)
				.stroke(
					Color.white.opacity(0.16),
					style: StrokeStyle(lineWidth: size * 0.024, lineCap: .round)
				)

			// Neon green outline — the light source.
			LabBeakerShape.glass.applying(scale)
				.stroke(
					LabTheme.neon,
					style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
				)
				.labGlow(LabTheme.neon, radius: size * 0.09, opacity: 0.5)
		}
		.frame(width: size, height: size)
	}
}

// MARK: - Geometry

private enum LabBeakerShape {
	/// Erlenmeyer-style flask outline, normalized to the unit square.
	static var glass: Path {
		var path = Path()
		path.move(to: CGPoint(x: 0.36, y: 0.08))
		path.addLine(to: CGPoint(x: 0.64, y: 0.08))		   // neck rim
		path.addLine(to: CGPoint(x: 0.60, y: 0.30))		   // neck, right
		path.addQuadCurve(
			to: CGPoint(x: 0.90, y: 0.68),
			control: CGPoint(x: 0.86, y: 0.30)				// right shoulder
		)
		path.addQuadCurve(
			to: CGPoint(x: 0.10, y: 0.68),
			control: CGPoint(x: 0.50, y: 0.98)				// round bottom
		)
		path.addQuadCurve(
			to: CGPoint(x: 0.40, y: 0.30),
			control: CGPoint(x: 0.14, y: 0.30)				// left shoulder
		)
		path.addLine(to: CGPoint(x: 0.36, y: 0.08))		   // neck, left
		path.closeSubpath()
		return path
	}

	/// The chemical — a rounded-bottom wedge inside the flask.
	static var liquid: Path {
		var path = Path()
		path.move(to: CGPoint(x: 0.17, y: 0.56))
		path.addLine(to: CGPoint(x: 0.83, y: 0.56))		   // surface
		path.addQuadCurve(
			to: CGPoint(x: 0.10, y: 0.68),
			control: CGPoint(x: 0.50, y: 0.97)				// follows the glass
		)
		path.closeSubpath()
		return path
	}

	/// A single bubble inside the chemical.
	static func bubble(x: Double, y: Double, r: Double) -> Path {
		Path(
			ellipseIn: CGRect(
				x: x - r,
				y: y - r,
				width: r * 2,
				height: r * 2
			)
		)
	}

	/// A faint diagonal highlight on the upper-left of the glass.
	static var reflection: Path {
		var path = Path()
		path.move(to: CGPoint(x: 0.30, y: 0.16))
		path.addLine(to: CGPoint(x: 0.22, y: 0.34))
		return path
	}
}

#Preview {
	ZStack {
		LabTheme.oledBlack
		VStack(spacing: 24) {
			LabBeakerIcon(size: 96)
			LabBeakerIcon(size: 48)
		}
	}
	.ignoresSafeArea()
}
