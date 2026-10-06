import UIKit

/// 微缩模型的配色和尺度。按第一版草图：浅色模型、灰影、绿地、橙色地标。
enum SceneStyle {
    /// 1 个场景单位 = 1:1000 模型里的 1 米，所以地图上 1 米 = 0.001 单位。
    static let scale: Float = 0.001
    static let plinthThickness: Float = 0.006

    static let accent = UIColor(red: 0.847, green: 0.353, blue: 0.188, alpha: 1)       // #D85A30
    // ③ 纸雕留白：白色块面 + 细灰描边，颜色只留给小人和地标（强调色点睛）。
    static let background = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        : UIColor(red: 0.980, green: 0.980, blue: 0.972, alpha: 1) }

    // 地面
    static let paving = UIColor(red: 0.969, green: 0.969, blue: 0.976, alpha: 1)        // #F7F7F9
    static func area(_ k: AreaKind) -> UIColor {
        switch k {
        case .water: return UIColor(red: 0.835, green: 0.894, blue: 0.937, alpha: 1)    // #D5E4EF 淡蓝
        case .grass, .park, .wood, .farmland, .pitch, .playground:
            return UIColor(red: 0.862, green: 0.918, blue: 0.827, alpha: 1)             // #DCEAD3 淡绿
        default: return paving
        }
    }
    static func road(_ k: RoadKind) -> (fill: UIColor, edge: UIColor?) {
        switch k {
        case .major, .minor, .residential:
            return (UIColor(red: 0.890, green: 0.890, blue: 0.910, alpha: 1), UIColor(white: 1, alpha: 1))   // 车路：浅灰带白边
        case .service:
            return (UIColor(red: 0.945, green: 0.945, blue: 0.953, alpha: 1), nil)
        case .footway, .cycleway, .steps:
            return (UIColor(red: 0.955, green: 0.955, blue: 0.962, alpha: 1), nil)
        }
    }

    // 楼：三面 #FFFFFF / #F3F3F5 / #E6E6EA 由光照自然形成，描边 #C9C9CE。
    static let facadeTints: [UIColor] = [.white]
    static let glass = UIColor(white: 0.9, alpha: 1)
    static let roof = UIColor.white
    static let construction = UIColor(red: 0.965, green: 0.925, blue: 0.850, alpha: 1)   // 施工：淡沙
    static let school = UIColor(red: 0.905, green: 0.930, blue: 0.960, alpha: 1)         // 学校：淡蓝灰
    static let commercial = UIColor(red: 0.970, green: 0.940, blue: 0.895, alpha: 1)     // 商场：淡暖米
    static let home = UIColor(red: 0.995, green: 0.905, blue: 0.860, alpha: 1)           // 我屋企：淡橙
    static let canopy = UIColor(white: 0.97, alpha: 1)
    static let outline = UIColor(red: 0.788, green: 0.788, blue: 0.808, alpha: 1)

    // 底座侧边：浅灰纸板。
    static let plinthSide = UIColor(red: 0.902, green: 0.902, blue: 0.918, alpha: 1)

    // 树：白色圆球 + 灰干。
    static let treeGreens: [UIColor] = [UIColor(red: 0.780, green: 0.875, blue: 0.735, alpha: 1), UIColor(red: 0.735, green: 0.850, blue: 0.690, alpha: 1)]
    static let trunk = UIColor(red: 0.700, green: 0.640, blue: 0.580, alpha: 1)
    static let skin = UIColor(red: 0.961, green: 0.769, blue: 0.702, alpha: 1)
}
