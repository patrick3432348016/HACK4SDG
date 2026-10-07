import Foundation

extension MapModel {
    /// 经纬度 → 场景坐标：先投影到本图中心，再按转正角度旋转（与 simplified 里的 shift 一致）。
    func scenePoint(_ g: GeoPoint) -> Vec2 {
        let v = LocalProjection(origin: center).toLocal(g)
        let cs = cos(rotation), sn = sin(rotation)
        return Vec2(x: v.x * cs - v.y * sn, y: v.x * sn + v.y * cs)
    }
}
