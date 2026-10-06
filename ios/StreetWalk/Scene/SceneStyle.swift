import UIKit

/// 微缩模型的配色和尺度。按第一版草图：浅色模型、灰影、绿地、橙色地标。
enum SceneStyle {
    /// 1 个场景单位 = 1:1000 模型里的 1 米，所以地图上 1 米 = 0.001 单位。
    static let scale: Float = 0.001
    static let plinthThickness: Float = 0.022

    static let accent = UIColor(red: 0.847, green: 0.353, blue: 0.188, alpha: 1)       // #D85A30
    // ③ 纸雕留白：白色块面 + 细灰描边，颜色只留给小人和地标（强调色点睛）。
    static let background = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        : UIColor(red: 0.980, green: 0.980, blue: 0.972, alpha: 1) }

    // 地面
    static let paving = UIColor(red: 0.969, green: 0.969, blue: 0.976, alpha: 1)        // #F7F7F9
    static func area(_ k: AreaKind) -> UIColor {
        switch k {
        case .water: return UIColor(red: 0.894, green: 0.922, blue: 0.941, alpha: 1)    // #E4EBF0
        case .grass, .park, .wood, .farmland, .pitch, .playground:
            return UIColor(red: 0.933, green: 0.945, blue: 0.925, alpha: 1)             // #EEF1EC
        default: return paving
        }
    }
    static func road(_ k: RoadKind) -> (fill: UIColor, edge: UIColor?) {
        switch k {
        case .major, .minor, .residential:
            return (UIColor(red: 0.925, green: 0.925, blue: 0.937, alpha: 1), nil)      // #ECECEF
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
    static let construction = UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 1)
    static let canopy = UIColor(white: 0.97, alpha: 1)
    static let outline = UIColor(red: 0.788, green: 0.788, blue: 0.808, alpha: 1)

    // 底座侧边：浅灰纸板。
    static let plinthSide = UIColor(red: 0.902, green: 0.902, blue: 0.918, alpha: 1)

    // 树：白色圆球 + 灰干。
    static let treeGreens: [UIColor] = [.white, UIColor(white: 0.985, alpha: 1)]
    static let trunk = UIColor(red: 0.70, green: 0.70, blue: 0.72, alpha: 1)
    static let skin = UIColor(red: 0.961, green: 0.769, blue: 0.702, alpha: 1)
}
