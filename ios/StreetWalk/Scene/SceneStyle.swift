import UIKit

/// 微缩模型的配色和尺度。按第一版草图：浅色模型、灰影、绿地、橙色地标。
enum SceneStyle {
    /// 1 个场景单位 = 1:1000 模型里的 1 米，所以地图上 1 米 = 0.001 单位。
    static let scale: Float = 0.001
    static let plinthThickness: Float = 0.022

    static let accent = UIColor(red: 0.847, green: 0.353, blue: 0.188, alpha: 1)       // #D85A30
    static let background = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        : UIColor(red: 0.957, green: 0.953, blue: 0.937, alpha: 1) }

    // 地面
    static let paving = UIColor(red: 0.925, green: 0.918, blue: 0.890, alpha: 1)
    static func area(_ k: AreaKind) -> UIColor {
        switch k {
        case .urban: return UIColor(red: 0.905, green: 0.898, blue: 0.875, alpha: 1)
        case .residential: return UIColor(red: 0.935, green: 0.928, blue: 0.902, alpha: 1)
        case .school: return UIColor(red: 0.925, green: 0.910, blue: 0.870, alpha: 1)
        case .military: return UIColor(red: 0.890, green: 0.900, blue: 0.865, alpha: 1)
        case .farmland: return UIColor(red: 0.855, green: 0.890, blue: 0.760, alpha: 1)
        case .grass: return UIColor(red: 0.800, green: 0.870, blue: 0.680, alpha: 1)
        case .wood: return UIColor(red: 0.730, green: 0.815, blue: 0.600, alpha: 1)
        case .park: return UIColor(red: 0.760, green: 0.860, blue: 0.620, alpha: 1)
        case .playground: return UIColor(red: 0.910, green: 0.860, blue: 0.770, alpha: 1)
        case .pitch: return UIColor(red: 0.640, green: 0.790, blue: 0.540, alpha: 1)
        case .water: return UIColor(red: 0.730, green: 0.840, blue: 0.900, alpha: 1)
        case .parking: return UIColor(red: 0.880, green: 0.875, blue: 0.855, alpha: 1)
        case .plaza: return UIColor(red: 0.950, green: 0.943, blue: 0.920, alpha: 1)
        }
    }
    static func road(_ k: RoadKind) -> (fill: UIColor, edge: UIColor?) {
        switch k {
        case .major, .minor: return (UIColor(red: 0.800, green: 0.790, blue: 0.765, alpha: 1), UIColor(red: 0.700, green: 0.690, blue: 0.665, alpha: 1))
        case .residential: return (UIColor(red: 0.835, green: 0.825, blue: 0.800, alpha: 1), UIColor(red: 0.745, green: 0.735, blue: 0.710, alpha: 1))
        case .service: return (UIColor(red: 0.860, green: 0.852, blue: 0.830, alpha: 1), nil)
        case .footway: return (UIColor(red: 0.975, green: 0.968, blue: 0.948, alpha: 1), UIColor(red: 0.860, green: 0.850, blue: 0.825, alpha: 1))
        case .cycleway: return (UIColor(red: 0.900, green: 0.820, blue: 0.775, alpha: 1), nil)
        case .steps: return (UIColor(red: 0.930, green: 0.920, blue: 0.895, alpha: 1), UIColor(red: 0.820, green: 0.810, blue: 0.790, alpha: 1))
        }
    }

    // 楼
    static let facadeTints: [UIColor] = [
        UIColor(red: 0.955, green: 0.948, blue: 0.930, alpha: 1),
        UIColor(red: 0.925, green: 0.918, blue: 0.900, alpha: 1),
        UIColor(red: 0.935, green: 0.925, blue: 0.895, alpha: 1),
    ]
    static let glass = UIColor(red: 0.700, green: 0.750, blue: 0.785, alpha: 1)
    static let roof = UIColor(red: 0.965, green: 0.960, blue: 0.945, alpha: 1)
    static let construction = UIColor(red: 0.910, green: 0.860, blue: 0.760, alpha: 1)
    static let canopy = UIColor(red: 0.880, green: 0.875, blue: 0.860, alpha: 1)

    // 底座侧边：浅木色
    static let plinthSide = UIColor(red: 0.780, green: 0.650, blue: 0.490, alpha: 1)

    // 树
    static let treeGreens: [UIColor] = [
        UIColor(red: 0.490, green: 0.640, blue: 0.350, alpha: 1),
        UIColor(red: 0.420, green: 0.590, blue: 0.320, alpha: 1),
        UIColor(red: 0.560, green: 0.690, blue: 0.390, alpha: 1),
    ]
    static let trunk = UIColor(red: 0.520, green: 0.420, blue: 0.330, alpha: 1)
    static let skin = UIColor(red: 0.961, green: 0.769, blue: 0.702, alpha: 1)
}
