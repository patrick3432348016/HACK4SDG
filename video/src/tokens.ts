import { loadFont as loadFraunces } from "@remotion/google-fonts/Fraunces";
import { loadFont as loadInter } from "@remotion/google-fonts/Inter";

// One place for every colour, font and motion constant in the film.
// Colours come from the app (Design.swift, SceneStyle.swift, the app icon).
export const C = {
  paper: "#FAFAF8",
  paper2: "#F4F3EF",
  line: "#E4E2DC",
  ink: "#1F1E1C",
  ink2: "#6B6A66",
  orange: "#D85A30",
  orangeDeep: "#A9441F",
  orangeTint: "#FAECE7",
  roofA: "#FEE7DB",
  roofB: "#FAD9C8",
  roofC: "#F2C9B5",
  green: "#1D9E75",
  greenTint: "#E1F5EE",
  greenInk: "#085041",
  amber: "#EF9F27",
  amberTint: "#FAEEDA",
  tree: "#C7DFBB",
  treeDark: "#B5D3A8",
  water: "#D5E4EF",
  grey: "#B4B2A9",
};

export const F = {
  serif: loadFraunces("normal", { weights: ["400", "500", "600"], subsets: ["latin"] }).fontFamily,
  sans: loadInter("normal", { weights: ["400", "500", "600"], subsets: ["latin"] }).fontFamily,
  zh: "'PingFang HK', 'Source Han Sans SC', sans-serif",
};

export const FPS = 30;
export const W = 1920;
export const H = 1080;

// Soft paper shadow used on every card.
export const paperShadow = "0 1px 2px rgba(60,40,20,0.06), 0 12px 32px rgba(60,40,20,0.10)";
export const deepShadow = "0 2px 4px rgba(60,40,20,0.08), 0 30px 70px rgba(60,40,20,0.18)";
