import Foundation

extension MapModel {
    /// Project geographic coordinates around the map centre, then rotate consistently with simplified.shift.
    func scenePoint(_ g: GeoPoint) -> Vec2 {
        let v = LocalProjection(origin: center).toLocal(g)
        let cs = cos(rotation), sn = sin(rotation)
        return Vec2(x: v.x * cs - v.y * sn, y: v.x * sn + v.y * cs)
    }
}
