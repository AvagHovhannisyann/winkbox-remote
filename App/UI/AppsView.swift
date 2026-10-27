import SwiftUI

/// The box's apps as big tiles; a tap opens the app on the TV.
struct AppsView: View {
    @EnvironmentObject var tv: TV
    @State private var opening: String?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apps").font(.sf(26, .bold)).foregroundColor(.white)
                    Text("Tap to open on your TV").font(.sf(14)).foregroundColor(.white.opacity(0.55))
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(TVApp.all) { app in
                        Button {
                            Haptics.press()
                            tv.open(app)
                            showOpening(app.name)
                        } label: {
                            AppTile(app: app)
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .top) {
            if let name = opening {
                HStack(spacing: 8) {
                    Image(systemName: "tv").font(.system(size: 13, weight: .bold))
                    Text("Opening \(name)").font(.sf(14, .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .glass(Capsule())
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func showOpening(_ name: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { opening = name }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                if opening == name { opening = nil }
            }
        }
    }
}

struct AppTile: View {
    let app: TVApp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color(hex: app.tint)
                LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
                BrandArt(id: app.id)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 7)
            Text(app.name)
                .font(.sf(14, .semibold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.leading, 4)
        }
    }
}

/// Each app's logo, drawn rather than shipped as an image, so the tiles stay sharp at any size.
struct BrandArt: View {
    let id: String

    var body: some View {
        switch id {
        case "org.smarttube.stable":
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0xFF0033))
                    .frame(width: 38, height: 27)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 13, weight: .black)).foregroundColor(.white))
                Text("YouTube").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
            }
        case "ru.rt.itv.stb.wink":
            HStack(spacing: 3) {
                Text("WINK")
                Image(systemName: "chevron.right").font(.system(size: 19, weight: .black)).foregroundColor(.accent)
                Text("TV")
            }
            .font(.system(size: 23, weight: .heavy))
            .foregroundColor(.white)
        case "com.apple.atve.androidtv.appletv":
            HStack(spacing: 1) {
                Image(systemName: "applelogo").font(.system(size: 27, weight: .medium)).offset(y: -2)
                Text("tv").font(.system(size: 33, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
        case "com.spotify.tv.android":
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(Color(hex: 0x1ED760))
                    SpotifyWaves().stroke(Color.black, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
                .frame(width: 30, height: 30)
                Text("Spotify").font(.system(size: 22, weight: .bold)).foregroundColor(Color(hex: 0x1ED760))
            }
        case "com.plexapp.android":
            HStack(spacing: 0) {
                Text("ple").foregroundColor(.white)
                Text("x").foregroundColor(Color(hex: 0xE5A00D))
            }
            .font(.system(size: 32, weight: .heavy, design: .rounded))
        case "com.amazon.amazonvideo.livingroom":
            VStack(spacing: 1) {
                Text("prime video").font(.system(size: 21, weight: .bold)).foregroundColor(.white)
                PrimeSmile().stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 62, height: 9)
            }
        case "org.xbmc.kodi":
            HStack(spacing: 8) {
                KodiMark().fill(Color(hex: 0x17B2E7)).frame(width: 30, height: 30)
                Text("KODI").font(.system(size: 24, weight: .medium)).foregroundColor(Color(hex: 0x111111))
            }
        case "org.videolan.vlc":
            HStack(spacing: 8) {
                Image(systemName: "cone.fill").font(.system(size: 28, weight: .bold))
                Text("VLC").font(.system(size: 25, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
        case "com.phlox.tvwebbrowser":
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 25, weight: .semibold))
                Text("TV Bro").font(.system(size: 24, weight: .heavy, design: .rounded))
            }
            .foregroundColor(Color(hex: 0x1D5FD6))
        case "io.github.jqssun.airplay":
            VStack(spacing: 5) {
                Image(systemName: "airplayvideo").font(.system(size: 28, weight: .medium))
                Text("WinkBox TV").font(.sf(12, .semibold)).opacity(0.7)
            }
            .foregroundColor(.white)
        default:
            Image(systemName: "gearshape.fill").font(.system(size: 34)).foregroundColor(Color(hex: 0x9FE8DD))
        }
    }
}

/// Spotify's three sound waves.
private struct SpotifyWaves: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (y, w, lift) in [(0.36, 0.64, 0.12), (0.52, 0.54, 0.10), (0.67, 0.42, 0.08)] as [(CGFloat, CGFloat, CGFloat)] {
            let left = CGPoint(x: r.midX - r.width * w / 2, y: r.minY + r.height * y)
            let right = CGPoint(x: r.midX + r.width * w / 2, y: r.minY + r.height * (y + 0.04))
            p.move(to: left)
            p.addQuadCurve(to: right, control: CGPoint(x: r.midX - r.width * 0.04, y: left.y - r.height * lift))
        }
        return p
    }
}

/// Amazon's smile with its arrowhead.
private struct PrimeSmile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.1))
        p.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.06, y: r.minY + r.height * 0.2),
                       control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.7))
        p.move(to: CGPoint(x: r.maxX - r.width * 0.2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.12))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.maxY * 0.85))
        return p
    }
}

/// Kodi's mark as four diamonds.
private struct KodiMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = min(r.width, r.height) * 0.22
        for (x, y) in [(0.5, 0.2), (0.2, 0.5), (0.8, 0.5), (0.5, 0.8)] as [(CGFloat, CGFloat)] {
            let c = CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            p.move(to: CGPoint(x: c.x, y: c.y - s))
            p.addLine(to: CGPoint(x: c.x + s, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: c.y + s))
            p.addLine(to: CGPoint(x: c.x - s, y: c.y))
            p.closeSubpath()
        }
        return p
    }
}
