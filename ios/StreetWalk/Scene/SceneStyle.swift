import UIKit

/// 微缩模型的配色和尺度。按第一版草图：浅色模型、灰影、绿地、橙色地标。
/// 颜色都是浅 / 深两套的动态色；场景搭建时按 DioramaController.isDark 解析。
enum SceneStyle {
    /// 1 个场景单位 = 1:1000 模型里的 1 米，所以地图上 1 米 = 0.001 单位。
    static let scale: Float = 0.001
    static let plinthThickness: Float = 0.006

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    /// 浅色 / 深色各一套。
    private static func pair(_ light: UIColor, _ dark: UIColor) -> UIColor { UIColor { $0.userInterfaceStyle == .dark ? dark : light } }

    static let accent = rgb(0.847, 0.353, 0.188)                                           // #D85A30
    // ③ 纸雕留白：白色块面 + 细灰描边，颜色只留给小人和地标（强调色点睛）。
    // 深色：深灰纸板 + 稍亮描边，层级不变，只是整体压暗。
    static let background = pair(rgb(0.980, 0.980, 0.972), rgb(0.11, 0.11, 0.12))

    // 地面
    static let paving = pair(rgb(0.969, 0.969, 0.976), rgb(0.185, 0.185, 0.200))          // #F7F7F9
    static let water = pair(rgb(0.835, 0.894, 0.937), rgb(0.160, 0.215, 0.265))           // #D5E4EF 淡蓝
    static let green = pair(rgb(0.862, 0.918, 0.827), rgb(0.180, 0.235, 0.180))           // #DCEAD3 淡绿
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
        case .major, .minor, .residential: return (carRoad, carRoadEdge)   // 车路：浅灰带白边
        case .service: return (serviceRoad, nil)
        case .footway, .cycleway, .steps: return (footRoad, nil)
        }
    }

    // 楼：三面 #FFFFFF / #F3F3F5 / #E6E6EA 由光照自然形成，描边 #C9C9CE。
    static let facadeTints: [UIColor] = [pair(.white, rgb(0.300, 0.300, 0.320))]
    static let roof = pair(.white, rgb(0.330, 0.330, 0.350))
    static let construction = pair(rgb(0.965, 0.925, 0.850), rgb(0.340, 0.310, 0.255))   // 施工：淡沙
    static let school = pair(rgb(0.905, 0.930, 0.960), rgb(0.265, 0.295, 0.345))         // 学校：淡蓝灰
    static let commercial = pair(rgb(0.970, 0.940, 0.895), rgb(0.345, 0.315, 0.275))     // 商场：淡暖米
    static let home = pair(rgb(0.995, 0.905, 0.860), rgb(0.450, 0.255, 0.180))           // 我屋企：淡橙 / 暗橙
    static let canopy = pair(UIColor(white: 0.97, alpha: 1), UIColor(white: 0.28, alpha: 1))
    static let outline = pair(rgb(0.788, 0.788, 0.808), rgb(0.500, 0.500, 0.530))

    // 底座侧边：浅灰纸板。
    static let plinthSide = pair(rgb(0.902, 0.902, 0.918), rgb(0.150, 0.150, 0.165))

    // 地标小凉亭：白顶；深色时稍压暗，不刺眼。
    static let pavilionRoof = pair(.white, UIColor(white: 0.86, alpha: 1))

    // 树：淡绿圆球 + 灰干。树用顶点色，按线性空间显示会偏亮，所以深色值取得更低。
    static let treeGreens: [UIColor] = [pair(rgb(0.780, 0.875, 0.735), rgb(0.060, 0.110, 0.052)),
                                        pair(rgb(0.735, 0.850, 0.690), rgb(0.048, 0.095, 0.042))]
    static let trunk = pair(rgb(0.700, 0.640, 0.580), rgb(0.110, 0.088, 0.070))
    static let skin = rgb(0.961, 0.769, 0.702)
}
