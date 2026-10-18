import React from "react";
import { Composition, useCurrentFrame } from "remotion";
import { ThreeCanvas } from "@remotion/three";

const Scene: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <ThreeCanvas width={960} height={540} shadows camera={{ position: [12, 12, 12], fov: 30 }} style={{ background: "#FAFAF8" }} onCreated={({ camera }) => camera.lookAt(0, 0, 0)}>
      <ambientLight intensity={0.6} />
      <directionalLight position={[Math.cos(f / 20) * 10, 10, Math.sin(f / 20) * 10]} intensity={1.6} castShadow shadow-mapSize-width={2048} shadow-mapSize-height={2048} />
      <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow><planeGeometry args={[20, 20]} /><meshStandardMaterial color="#F4F3EF" /></mesh>
      <mesh position={[0, 2, 0]} castShadow receiveShadow><boxGeometry args={[2, 4, 2]} /><meshStandardMaterial color="#F2C9B5" /></mesh>
      <mesh position={[3, 0.5, 2]} castShadow><boxGeometry args={[1.5, 1, 1.5]} /><meshStandardMaterial color="#D85A30" /></mesh>
    </ThreeCanvas>
  );
};
export const LabRoot: React.FC = () => <Composition id="Lab" component={Scene} durationInFrames={60} fps={30} width={960} height={540} />;
