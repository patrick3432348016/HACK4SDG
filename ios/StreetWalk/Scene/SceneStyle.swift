import UIKit

/// Diorama palette and scale from the first sketch: pale model, gray shadows, greenery, and orange landmarks.
/// All colors have light/dark variants resolved using DioramaController.isDark.
enum SceneStyle {
    /// Scale 1:1000: one map metre equals 0.001 scene units.
    static let scale: Float = 0.001
    static let plinthThickness: Float = 0.006

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    /// Separate light/dark palettes.
    private static func pair(_ light: UIColor, _ dark: UIColor) -> UIColor { UIColor { $0.userInterfaceStyle == .dark ? dark : light } }

    static let accent = rgb(0.847, 0.353, 0.188)                                           // #D85A30
    // Reference 3 paper-art whitespace: white surfaces and thin gray outlines; reserve accent colors for people and landmarks.
    // Dark mode uses dark-gray card with lighter outlines, preserving visual hierarchy.
    static let background = pair(rgb(0.980, 0.980, 0.972), rgb(0.11, 0.11, 0.12))

    // Ground.
    static let paving = pair(rgb(0.969, 0.969, 0.976), rgb(0.185, 0.185, 0.200))          // #F7F7F9
    static let water = pair(rgb(0.835, 0.894, 0.937), rgb(0.160, 0.215, 0.265))           // #Pale blue D5E4EF.
    static let green = pair(rgb(0.862, 0.918, 0.827), rgb(0.180, 0.235, 0.180))           // #Pale green DCEAD3.
    static let waterEdge = pair(rgb(0.62, 0.74, 0.84), rgb(0.23, 0.31, 0.39))
    static let greenEdge = pair(rgb(0.66, 0.78, 0.60), rgb(0.26, 0.34, 0.25))
    static func area(_ k: AreaKind) -> UIColor {
        switch k {
        case .water: return water
        case .grass, .park, .wood, .farmland, .pitch, .playground: return green
        default: return paving
        }
    }
    static func areaEdge(_ k: AreaKind) -> UIColor { k == .water ? waterEdge : greenEdge }

    private static let carRoad = pair(rgb(0.890, 0.890, 0.910), rgb(0.235, 0.235, 0.255))
    private static let carRoadEdge = pair(.white, rgb(0.275, 0.275, 0.295))
    private static let serviceRoad = pair(rgb(0.945, 0.945, 0.953), rgb(0.215, 0.215, 0.232))
    private static let footRoad = pair(rgb(0.955, 0.955, 0.962), rgb(0.205, 0.205, 0.222))
    static func road(_ k: RoadKind) -> (fill: UIColor, edge: UIColor?) {
        switch k {
        case .major, .minor, .residential: return (carRoad, carRoadEdge)   // Vehicle roads: light gray with white borders.
        case .service: return (serviceRoad, nil)
        case .footway, .cycleway, .steps: return (footRoad, nil)
        }
    }

    // Building faces naturally shade to #FFFFFF/#F3F3F5/#E6E6EA; outline #C9C9CE.
    static let facadeTints: [UIColor] = [pair(.white, rgb(0.300, 0.300, 0.320))]
    static let roof = pair(.white, rgb(0.330, 0.330, 0.350))
    static let construction = pair(rgb(0.965, 0.925, 0.850), rgb(0.340, 0.310, 0.255))   // Construction: pale sand.
    static let school = pair(rgb(0.905, 0.930, 0.960), rgb(0.265, 0.295, 0.345))         // School: pale blue-gray.
    static let commercial = pair(rgb(0.970, 0.940, 0.895), rgb(0.345, 0.315, 0.275))     // Mall: warm pale beige.
    static let home = pair(rgb(0.995, 0.905, 0.860), rgb(0.450, 0.255, 0.180))           // Home: pale/dark orange.
    static let canopy = pair(UIColor(white: 0.97, alpha: 1), UIColor(white: 0.28, alpha: 1))
    static let outline = pair(rgb(0.788, 0.788, 0.808), rgb(0.500, 0.500, 0.530))

    // Base sides: light-gray card.
    static let plinthSide = pair(rgb(0.902, 0.902, 0.918), rgb(0.150, 0.150, 0.165))

    // Landmark pavilion roof: white, slightly dimmed in dark mode to reduce glare.
    static let pavilionRoof = pair(.white, UIColor(white: 0.86, alpha: 1))

    // Trees: pale-green crowns and gray trunks. Vertex colors brighten in linear space, requiring darker dark-mode values.
    static let treeGreens: [UIColor] = [pair(rgb(0.780, 0.875, 0.735), rgb(0.060, 0.110, 0.052)),
                                        pair(rgb(0.735, 0.850, 0.690), rgb(0.048, 0.095, 0.042))]
    static let trunk = pair(rgb(0.700, 0.640, 0.580), rgb(0.110, 0.088, 0.070))
    static let skin = rgb(0.961, 0.769, 0.702)
}
