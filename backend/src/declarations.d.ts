// No published type definitions for these packages; both export minimal shapes.
declare module "ffmpeg-static" {
  const ffmpegPath: string;
  export default ffmpegPath;
}

declare module "ffprobe-static" {
  const ffprobeStatic: { path: string };
  export default ffprobeStatic;
}
